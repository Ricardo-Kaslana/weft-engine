/*
 * weft_glue.c — flat FFI boundary between Weft (Dart) and QuickJS.
 *
 * Design rules (see docs/adr/0033):
 * - Only pointers and integers cross the Dart FFI boundary; JSValue never
 *   crosses by value, so the shim is ABI-independent.
 * - JSON is the single marshaling format for results, bridge payloads and
 *   events. Values that are not JSON-representable (undefined, functions,
 *   symbols, circular objects) collapse to `null` with an `undef` flag.
 * - The shim owns the promise plumbing for asynchronous bridge calls: the
 *   JS-visible `__weftBridge(ns, method, argsJson)` returns a promise that
 *   Dart later resolves through weft_resolve().
 * - Budgets are enforced natively: JS_SetMemoryLimit for heap, JS_SetMaxStackSize
 *   for stack, and an interrupt handler comparing a monotonic deadline set by
 *   Dart for wall-clock timeouts (covers scripts, promise jobs and any other
 *   synchronous JS execution).
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#if defined(_WIN32)
#include <windows.h>
#endif

#include "quickjs/quickjs.h"
#include "quickjs/cutils.h"

#if defined(_WIN32)
#define WEFT_EXPORT __declspec(dllexport)
#else
/* visibility keeps the entry points in the dynamic symbol table; `used` keeps
 * them from being dropped when the shim is linked into an executable instead
 * of a shared library (iOS compiles it into the app image, and nothing in C
 * references these functions — Dart resolves them with dlsym). */
#define WEFT_EXPORT __attribute__((visibility("default"), used))
#endif

typedef void WeftBridgeNotify(const char *request_json, void *user);

void weft_register_bridge_function(JSContext *ctx);

typedef struct WeftPending {
    uint64_t id;
    JSContext *ctx;
    JSValue resolve;
    JSValue reject;
    struct WeftPending *next;
} WeftPending;

typedef struct WeftRuntime {
    JSRuntime *rt;
    JSContext *ctx;
    double deadline_ms; /* monotonic ms; 0 disables the deadline */
    WeftBridgeNotify *notify;
    void *notify_user;
    uint64_t next_call_id;
    WeftPending *pending_head;
} WeftRuntime;

static double weft_monotonic_ms(void) {
#if defined(_WIN32)
    LARGE_INTEGER freq, counter;
    if (!QueryPerformanceFrequency(&freq) || !QueryPerformanceCounter(&counter)) {
        return 0.0;
    }
    return (double)counter.QuadPart * 1000.0 / (double)freq.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
#endif
}

static int weft_interrupt_handler(JSRuntime *rt, void *opaque) {
    WeftRuntime *wr = (WeftRuntime *)opaque;
    (void)rt;
    return wr->deadline_ms > 0.0 && weft_monotonic_ms() >= wr->deadline_ms;
}

/* --- JSON envelope helpers (DynBuf uses plain realloc by default) --- */

static void weft_json_escape(DynBuf *out, const char *str) {
    const unsigned char *p;
    dbuf_putc(out, '"');
    for (p = (const unsigned char *)str; *p; p++) {
        unsigned char c = *p;
        switch (c) {
        case '"':
            dbuf_putstr(out, "\\\"");
            break;
        case '\\':
            dbuf_putstr(out, "\\\\");
            break;
        case '\b':
            dbuf_putstr(out, "\\b");
            break;
        case '\f':
            dbuf_putstr(out, "\\f");
            break;
        case '\n':
            dbuf_putstr(out, "\\n");
            break;
        case '\r':
            dbuf_putstr(out, "\\r");
            break;
        case '\t':
            dbuf_putstr(out, "\\t");
            break;
        default:
            if (c < 0x20) {
                char buf[8];
                snprintf(buf, sizeof(buf), "\\u%04x", c);
                dbuf_putstr(out, buf);
            } else {
                dbuf_putc(out, c);
            }
        }
    }
    dbuf_putc(out, '"');
}

static char *weft_dbuf_take(DynBuf *out) {
    dbuf_putc(out, '\0');
    return (char *)out->buf;
}

static const char *weft_classify(const char *message) {
    if (message == NULL) {
        return "script";
    }
    if (strstr(message, "out of memory") != NULL) {
        return "memory";
    }
    if (strstr(message, "stack overflow") != NULL) {
        return "stack";
    }
    if (strstr(message, "interrupted") != NULL) {
        return "timeout";
    }
    return "script";
}

/* Consumes the pending exception and renders it as a failure envelope. */
static char *weft_exception_envelope(JSContext *ctx) {
    JSValue exc = JS_GetException(ctx); /* the thrown value itself */
    const char *kind;
    const char *message = "script error";
    const char *converted = NULL;
    int own_converted = 0;
    DynBuf out;

    converted = JS_ToCString(ctx, exc);
    if (converted == NULL) {
        /* Converting the thrown value itself threw (e.g. a symbol). */
        JSValue dropped = JS_GetException(ctx);
        JS_FreeValue(ctx, dropped);
    } else {
        own_converted = 1;
        message = converted;
    }
    kind = weft_classify(message);
    dbuf_init(&out);
    dbuf_putstr(&out, "{\"ok\":false,\"kind\":");
    weft_json_escape(&out, kind);
    dbuf_putstr(&out, ",\"message\":");
    weft_json_escape(&out, message);
    dbuf_putc(&out, '}');
    if (own_converted) {
        JS_FreeCString(ctx, converted);
    }
    JS_FreeValue(ctx, exc);
    return weft_dbuf_take(&out);
}

/* Consumes `result` and renders it as a success envelope. */
static char *weft_result_envelope(JSContext *ctx, JSValue result) {
    DynBuf out;
    JSValue stringified;
    const char *json = NULL;
    int undef = 1;

    stringified = JS_JSONStringify(ctx, result, JS_UNDEFINED, JS_UNDEFINED);
    if (!JS_IsException(stringified) && !JS_IsUndefined(stringified)) {
        json = JS_ToCString(ctx, stringified);
    }
    if (json != NULL) {
        undef = 0;
    } else {
        /* Non-JSON results (functions, symbols, circular objects) and
         * undefined collapse to `null` per the marshaling contract. */
        JSValue dropped = JS_GetException(ctx);
        JS_FreeValue(ctx, dropped);
    }

    dbuf_init(&out);
    dbuf_putstr(&out, "{\"ok\":true,\"value\":");
    if (undef) {
        dbuf_putstr(&out, "null");
    } else {
        dbuf_putstr(&out, json);
    }
    dbuf_putstr(&out, ",\"undef\":");
    dbuf_putstr(&out, undef ? "1" : "0");
    dbuf_putc(&out, '}');

    if (json != NULL) {
        JS_FreeCString(ctx, json);
    }
    JS_FreeValue(ctx, stringified);
    JS_FreeValue(ctx, result);
    return weft_dbuf_take(&out);
}

/* --- lifecycle --- */

WEFT_EXPORT WeftRuntime *weft_new_runtime(size_t memory_limit, size_t stack_limit) {
    WeftRuntime *wr = (WeftRuntime *)calloc(1, sizeof(WeftRuntime));
    if (wr == NULL) {
        return NULL;
    }
    wr->rt = JS_NewRuntime();
    if (wr->rt == NULL) {
        free(wr);
        return NULL;
    }
    JS_SetRuntimeOpaque(wr->rt, wr);
    JS_SetMemoryLimit(wr->rt, memory_limit);
    JS_SetMaxStackSize(wr->rt, stack_limit);
    JS_SetInterruptHandler(wr->rt, weft_interrupt_handler, wr);
    wr->ctx = JS_NewContext(wr->rt);
    if (wr->ctx == NULL) {
        JS_FreeRuntime(wr->rt);
        free(wr);
        return NULL;
    }
    weft_register_bridge_function(wr->ctx);
    return wr;
}

WEFT_EXPORT void weft_set_deadline(WeftRuntime *wr, double deadline_monotonic_ms) {
    if (wr != NULL) {
        wr->deadline_ms = deadline_monotonic_ms;
    }
}

WEFT_EXPORT double weft_now_ms(void) {
    return weft_monotonic_ms();
}

WEFT_EXPORT void weft_free_runtime(WeftRuntime *wr) {
    WeftPending *pending;
    if (wr == NULL) {
        return;
    }
    pending = wr->pending_head;
    while (pending != NULL) {
        WeftPending *next = pending->next;
        JS_FreeValue(pending->ctx, pending->resolve);
        JS_FreeValue(pending->ctx, pending->reject);
        free(pending);
        pending = next;
    }
    wr->pending_head = NULL;
    if (wr->ctx != NULL) {
        JS_FreeContext(wr->ctx);
        wr->ctx = NULL;
    }
    if (wr->rt != NULL) {
        JS_FreeRuntime(wr->rt);
        wr->rt = NULL;
    }
    free(wr);
}

/* --- script execution --- */

WEFT_EXPORT char *weft_eval(WeftRuntime *wr, const char *code, size_t code_len,
                            const char *filename) {
    JSValue result;
    char *envelope;
    if (wr == NULL || code == NULL) {
        return NULL;
    }
    result = JS_Eval(wr->ctx, code, code_len, filename != NULL ? filename : "weft",
                     JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result)) {
        envelope = weft_exception_envelope(wr->ctx);
    } else {
        envelope = weft_result_envelope(wr->ctx, result);
    }
    return envelope;
}

/* Drains promise jobs. Returns 0 when drained, 1 when the microtask budget
 * stopped the pump before the queue emptied, -1 when a job threw. */
WEFT_EXPORT int weft_pump_jobs(WeftRuntime *wr, int max_jobs, int *executed_out,
                               char **error_out) {
    int executed = 0;
    JSContext *job_ctx = NULL;
    if (wr == NULL) {
        return -1;
    }
    if (max_jobs <= 0) {
        max_jobs = 1;
    }
    for (;;) {
        int status = JS_ExecutePendingJob(wr->rt, &job_ctx);
        if (status == 0) {
            if (executed_out != NULL) {
                *executed_out = executed;
            }
            return 0;
        }
        if (status < 0) {
            /* A pending job threw; the exception sits on that context. */
            if (error_out != NULL) {
                *error_out = weft_exception_envelope(job_ctx != NULL ? job_ctx : wr->ctx);
            }
            return -1;
        }
        executed++;
        if (executed >= max_jobs) {
            if (executed_out != NULL) {
                *executed_out = executed;
            }
            return 1;
        }
    }
}

/* --- bridge (JS -> Dart -> JS) --- */

WEFT_EXPORT void weft_install_bridge(WeftRuntime *wr, WeftBridgeNotify *notify,
                                     void *user) {
    if (wr != NULL) {
        wr->notify = notify;
        wr->notify_user = user;
    }
}

static JSValue weft_bridge_cfunc(JSContext *ctx, JSValueConst this_val, int argc,
                                 JSValueConst *argv) {
    WeftRuntime *wr = (WeftRuntime *)JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
    const char *ns = NULL;
    const char *method = NULL;
    const char *args = NULL;
    uint64_t call_id;
    JSValueConst resolving[2];
    JSValue promise;
    WeftPending *pending;
    DynBuf request;
    (void)this_val;

    if (wr == NULL || wr->notify == NULL) {
        return JS_ThrowInternalError(ctx, "weft bridge unavailable");
    }
    if (argc < 3 || !JS_IsString(argv[0]) || !JS_IsString(argv[1]) ||
        !JS_IsString(argv[2])) {
        return JS_ThrowTypeError(ctx, "__weftBridge expects (ns, method, argsJson)");
    }
    ns = JS_ToCString(ctx, argv[0]);
    method = JS_ToCString(ctx, argv[1]);
    args = JS_ToCString(ctx, argv[2]);
    if (ns == NULL || method == NULL || args == NULL) {
        if (ns != NULL) JS_FreeCString(ctx, ns);
        if (method != NULL) JS_FreeCString(ctx, method);
        if (args != NULL) JS_FreeCString(ctx, args);
        return JS_ThrowInternalError(ctx, "bridge arguments are not strings");
    }

    call_id = ++wr->next_call_id;
    promise = JS_NewPromiseCapability(ctx, resolving);
    if (JS_IsException(promise)) {
        JS_FreeCString(ctx, ns);
        JS_FreeCString(ctx, method);
        JS_FreeCString(ctx, args);
        return promise;
    }
    pending = (WeftPending *)malloc(sizeof(WeftPending));
    if (pending == NULL) {
        JS_FreeValue(ctx, resolving[0]);
        JS_FreeValue(ctx, resolving[1]);
        JS_FreeValue(ctx, promise);
        JS_FreeCString(ctx, ns);
        JS_FreeCString(ctx, method);
        JS_FreeCString(ctx, args);
        return JS_ThrowInternalError(ctx, "out of memory");
    }
    pending->id = call_id;
    pending->ctx = ctx;
    pending->resolve = resolving[0];
    pending->reject = resolving[1];
    pending->next = wr->pending_head;
    wr->pending_head = pending;

    dbuf_init(&request);
    dbuf_putstr(&request, "{\"call\":");
    {
        char id_buf[24];
        snprintf(id_buf, sizeof(id_buf), "%llu", (unsigned long long)call_id);
        dbuf_putstr(&request, id_buf);
    }
    dbuf_putstr(&request, ",\"ns\":");
    weft_json_escape(&request, ns);
    dbuf_putstr(&request, ",\"method\":");
    weft_json_escape(&request, method);
    dbuf_putstr(&request, ",\"args\":");
    dbuf_putstr(&request, args);
    dbuf_putc(&request, '}');
    dbuf_putc(&request, '\0');

    JS_FreeCString(ctx, ns);
    JS_FreeCString(ctx, method);
    JS_FreeCString(ctx, args);

    wr->notify((const char *)request.buf, wr->notify_user);
    free(request.buf);
    return promise;
}

void weft_register_bridge_function(JSContext *ctx) {
    JSValue global = JS_GetGlobalObject(ctx);
    JSValue fn = JS_NewCFunction(ctx, weft_bridge_cfunc, "__weftBridge", 3);
    JS_SetPropertyStr(ctx, global, "__weftBridge", fn);
    JS_FreeValue(ctx, global);
}

/* Resolves (or rejects) a pending bridge promise. Returns 0 on success and 1
 * when the call id is unknown (for example after a recovery). */
WEFT_EXPORT int weft_resolve(WeftRuntime *wr, uint64_t call_id, const char *result_json,
                             int is_error) {
    WeftPending **link;
    WeftPending *pending = NULL;
    JSValue payload, call_result, fn;
    if (wr == NULL || result_json == NULL) {
        return 1;
    }
    for (link = &wr->pending_head; *link != NULL; link = &(*link)->next) {
        if ((*link)->id == call_id) {
            pending = *link;
            break;
        }
    }
    if (pending == NULL) {
        return 1;
    }
    *link = pending->next;

    payload = JS_ParseJSON(pending->ctx, result_json, strlen(result_json), "<weft>");
    if (JS_IsException(payload)) {
        JSValue dropped = JS_GetException(pending->ctx);
        JS_FreeValue(pending->ctx, dropped);
        payload = JS_UNDEFINED;
    }
    fn = is_error ? pending->reject : pending->resolve;
    call_result = JS_Call(pending->ctx, fn, JS_UNDEFINED, 1, (JSValueConst *)&payload);
    if (JS_IsException(call_result)) {
        JSValue dropped = JS_GetException(pending->ctx);
        JS_FreeValue(pending->ctx, dropped);
    } else {
        JS_FreeValue(pending->ctx, call_result);
    }
    JS_FreeValue(pending->ctx, payload);
    JS_FreeValue(pending->ctx, pending->resolve);
    JS_FreeValue(pending->ctx, pending->reject);
    free(pending);
    return 0;
}

/* --- host events (Dart -> JS) --- */

/* Delivers an event JSON payload to the JS handler `__weftOnEvent`.
 * Returns 0 when delivered, 1 when no handler is installed, 2 when the payload
 * is not valid JSON, 3 when the handler threw (error envelope in *error_out). */
WEFT_EXPORT int weft_send_event(WeftRuntime *wr, const char *event_json,
                                char **error_out) {
    JSValue event, handler_result, global, handler;
    int status = 0;
    if (wr == NULL || event_json == NULL) {
        return 2;
    }
    event = JS_ParseJSON(wr->ctx, event_json, strlen(event_json), "<weft-event>");
    if (JS_IsException(event)) {
        JSValue dropped = JS_GetException(wr->ctx);
        JS_FreeValue(wr->ctx, dropped);
        JS_FreeValue(wr->ctx, event);
        return 2;
    }
    global = JS_GetGlobalObject(wr->ctx);
    handler = JS_GetPropertyStr(wr->ctx, global, "__weftOnEvent");
    if (JS_IsFunction(wr->ctx, handler)) {
        handler_result = JS_Call(wr->ctx, handler, JS_UNDEFINED, 1,
                                 (JSValueConst *)&event);
        if (JS_IsException(handler_result)) {
            if (error_out != NULL) {
                *error_out = weft_exception_envelope(wr->ctx);
            }
            status = 3;
        } else {
            JS_FreeValue(wr->ctx, handler_result);
        }
    } else {
        status = 1;
    }
    JS_FreeValue(wr->ctx, handler);
    JS_FreeValue(wr->ctx, global);
    JS_FreeValue(wr->ctx, event);
    return status;
}

WEFT_EXPORT void weft_free_string(char *ptr) {
    free(ptr);
}

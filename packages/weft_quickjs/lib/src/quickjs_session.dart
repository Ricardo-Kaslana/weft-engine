import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

import 'quickjs_ffi.dart';

typedef _BridgeNotifyNative = Void Function(Pointer<Utf8>, Pointer<Void>);

/// Runtime backend that executes scripts with the vendored QuickJS engine
/// through `dart:ffi`. Each [open] creates an isolated `JSRuntime` with the
/// configured memory and stack limits; wall-clock timeouts and microtask
/// budgets are enforced natively by the interrupt handler in
/// `native/weft_glue.c`.
final class QuickJsFfiBackend implements JsRuntimeBackend {
  /// Creates the backend; [libraryPath] overrides shared-library discovery
  /// in [QuickJsNativeLibrary.load], otherwise the default search applies.
  QuickJsFfiBackend({String? libraryPath}) : _libraryPath = libraryPath;

  final String? _libraryPath;

  @override
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge) async {
    final library = QuickJsNativeLibrary.load(explicitPath: _libraryPath);
    return QuickJsFfiSession.open(library, config, bridge);
  }
}

/// One [JsSession] bound to one native `JSRuntime` handle.
///
/// Everything runs on the owning isolate: while a script is on the stack,
/// QuickJS re-enters Dart synchronously to dispatch capability calls, and
/// after each evaluation, event, or bridge resolution the session pumps the
/// native promise queue so continuations and cascaded bridge calls make
/// progress within their budgets.
final class QuickJsFfiSession implements JsSession {
  QuickJsFfiSession._(
    this._library,
    this._runtime,
    this._bridge,
    RuntimeConfig config,
  ) : id = 'quickjs:${config.documentId}:${_nextSessionId++}' {
    _bridgeCallable = NativeCallable<_BridgeNotifyNative>.isolateLocal(
      _onBridgeRequest,
    );
    _library.installBridge(_runtime, _bridgeCallable.nativeFunction, nullptr);
  }

  static const Duration _continuationTimeout = Duration(seconds: 10);
  static const int _continuationMaxMicrotasks = 4096;
  static const int _maxSettleRounds = 256;

  /// Capability calls issued from JS within a single event-loop turn
  /// (including microtask cascades) beyond this count are rejected without
  /// reaching the gateway. Without the cap a script chaining capability
  /// calls inside promise continuations would starve the event loop.
  static const int _maxBridgeCallsPerTurn = 4096;

  static int _nextSessionId = 1;

  final QuickJsNativeLibrary _library;
  final Pointer<WeftRuntimeFfi> _runtime;
  final BridgeDispatcher _bridge;
  late final NativeCallable<_BridgeNotifyNative> _bridgeCallable;
  bool _disposed = false;
  final Set<Future<void>> _inflightDispatches = <Future<void>>{};
  int _bridgeCallsThisTurn = 0;
  bool _turnResetScheduled = false;
  RuntimeFailure? _stormFailure;

  @override
  final String id;

  /// Allocates the native runtime with [RuntimeConfig.memoryLimitBytes] and
  /// [RuntimeConfig.stackLimitBytes]; throws [StateError] when QuickJS
  /// cannot allocate the engine.
  static Future<JsSession> open(
    QuickJsNativeLibrary library,
    RuntimeConfig config,
    BridgeDispatcher bridge,
  ) {
    final runtime = library.newRuntime(
      config.memoryLimitBytes,
      config.stackLimitBytes,
    );
    if (runtime == nullptr) {
      throw StateError('QuickJS runtime allocation failed.');
    }
    return Future<JsSession>.value(
      QuickJsFfiSession._(library, runtime, bridge, config),
    );
  }

  @override
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget) async {
    if (_disposed) {
      return JsResult.error(
        RuntimeFailure(
          kind: RuntimeFailureKind.disposed,
          message: 'Session $id is disposed.',
          scriptId: script.id,
        ),
      );
    }
    _library.setDeadline(
      _runtime,
      _library.nowMs() + budget.timeout.inMilliseconds,
    );

    final codeBytes = utf8.encode(script.source);
    final codePtr = script.source.toNativeUtf8();
    final namePtr = (script.sourceUrl?.toString() ?? 'weft:$id').toNativeUtf8();
    Pointer<Utf8> envelopePtr;
    try {
      envelopePtr = _library.eval(_runtime, codePtr, codeBytes.length, namePtr);
    } finally {
      malloc.free(codePtr);
      malloc.free(namePtr);
    }
    Map<String, Object?> envelope;
    try {
      envelope = _decodeEnvelope(envelopePtr);
    } finally {
      _library.freeString(envelopePtr);
    }

    if (envelope['ok'] != true) {
      return JsResult.error(_failureFromEnvelope(envelope, script.id));
    }
    final value = envelope['undef'] == 1 ? null : envelope['value'];

    final status = _pumpJobs(budget.maxMicrotasks);
    if (status == kPumpBudgetExceeded) {
      return JsResult.error(
        RuntimeFailure(
          kind: RuntimeFailureKind.microtaskBudget,
          message: 'Microtask budget of ${budget.maxMicrotasks} exceeded while '
              'draining promise jobs.',
          scriptId: script.id,
        ),
      );
    }
    if (status == kPumpJobError) {
      return JsResult.error(
        _failureFromEnvelope(_takeJobError() ?? {}, script.id),
      );
    }
    return JsResult.success(value);
  }

  @override
  Future<void> send(EventEnvelope event) async {
    if (_disposed) {
      throw JsSessionFailure(
        RuntimeFailure(
          kind: RuntimeFailureKind.disposed,
          message: 'Session $id is disposed.',
        ),
      );
    }
    _library.setDeadline(
      _runtime,
      _library.nowMs() + _continuationTimeout.inMilliseconds,
    );
    final payload = jsonEncode(<String, Object?>{
      'name': event.name,
      'sequence': event.sequence,
      'payload': event.payload,
    });
    final payloadPtr = payload.toNativeUtf8();
    final errorOut = malloc<Pointer<Utf8>>();
    int status;
    try {
      status = _library.sendEvent(_runtime, payloadPtr, errorOut);
    } finally {
      malloc.free(payloadPtr);
      malloc.free(errorOut);
    }
    if (status == kSendEventBadPayload) {
      throw JsSessionFailure(
        RuntimeFailure(
          kind: RuntimeFailureKind.bridgeError,
          message: 'Event payload for "${event.name}" is not valid JSON.',
        ),
      );
    }
    if (status == kSendEventHandlerThrew) {
      throw JsSessionFailure(
        RuntimeFailure(
          kind: RuntimeFailureKind.scriptError,
          message: 'JS event handler for "${event.name}" threw: '
              '${_decodeEnvelope(errorOut.value)['message']}',
        ),
      );
    }
    if (_pumpJobs(_continuationMaxMicrotasks) == kPumpBudgetExceeded) {
      throw JsSessionFailure(
        RuntimeFailure(
          kind: RuntimeFailureKind.microtaskBudget,
          message:
              'Microtask budget exceeded while delivering "${event.name}".',
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _library.freeRuntime(_runtime);
    _bridgeCallable.close();
  }

  @override
  Future<void> settle() async {
    var rounds = 0;
    while (rounds++ < _maxSettleRounds) {
      final storm = _stormFailure;
      if (storm != null) {
        throw JsSessionFailure(storm);
      }
      if (_inflightDispatches.isNotEmpty) {
        await Future<void>.delayed(Duration.zero);
        continue;
      }
      if (_disposed) {
        return;
      }
      final status = _pumpJobs(_continuationMaxMicrotasks);
      if (status == kPumpBudgetExceeded) {
        throw JsSessionFailure(
          RuntimeFailure(
            kind: RuntimeFailureKind.microtaskBudget,
            message: 'Microtask budget exceeded while settling session $id.',
          ),
        );
      }
      if (_inflightDispatches.isEmpty) {
        return;
      }
    }
    throw JsSessionFailure(
      RuntimeFailure(
        kind: RuntimeFailureKind.scriptError,
        message: 'Session $id did not settle within $_maxSettleRounds rounds; '
            'the script is issuing capability calls in an unbounded loop.',
      ),
    );
  }

  // --- bridge plumbing ---

  /// Runs on the UI isolate while QuickJS is evaluating (synchronous
  /// re-entrant call). Parses the request, dispatches it through the
  /// capability gateway, and resolves the JS promise when the future lands.
  void _onBridgeRequest(Pointer<Utf8> requestJson, Pointer<Void> user) {
    if (_disposed) {
      return;
    }
    if (!_turnResetScheduled) {
      _turnResetScheduled = true;
      // The reset lands on the event queue, so every microtask cascade of
      // the current turn counts against one cap window.
      Timer.run(() {
        _bridgeCallsThisTurn = 0;
        _turnResetScheduled = false;
      });
    }
    _bridgeCallsThisTurn++;
    if (_bridgeCallsThisTurn > _maxBridgeCallsPerTurn) {
      _stormFailure ??= const RuntimeFailure(
        kind: RuntimeFailureKind.scriptError,
        message: 'Capability call storm: more than $_maxBridgeCallsPerTurn '
            'bridge calls were issued within one event-loop turn.',
      );
      return;
    }
    final request =
        jsonDecode(requestJson.toDartString()) as Map<String, Object?>;
    final call = BridgeCall(
      sessionId: id,
      sequence: request['call'] as int,
      capability: request['ns'] as String,
      method: request['method'] as String,
      arguments: (request['args'] as List<Object?>).toList(),
    );
    final dispatch = _dispatch(call);
    _inflightDispatches.add(dispatch);
    unawaited(
        dispatch.whenComplete(() => _inflightDispatches.remove(dispatch)));
  }

  Future<void> _dispatch(BridgeCall call) async {
    if (_disposed) {
      return;
    }
    Object? result;
    try {
      result = await _bridge.dispatch(call);
    } catch (error) {
      _resolveBridge(
          call.sequence,
          <String, Object?>{
            'message': error.toString(),
          },
          isError: true);
      return;
    }
    try {
      _resolveBridge(call.sequence, result, isError: false);
    } catch (error) {
      _resolveBridge(
          call.sequence,
          <String, Object?>{
            'message': 'Bridge result is not JSON-serializable: $error',
          },
          isError: true);
    }
  }

  void _resolveBridge(int callId, Object? result, {required bool isError}) {
    if (_disposed) {
      return;
    }
    _library.setDeadline(
      _runtime,
      _library.nowMs() + _continuationTimeout.inMilliseconds,
    );
    final json = jsonEncode(result);
    final jsonPtr = json.toNativeUtf8();
    try {
      _library.resolve(_runtime, callId, jsonPtr, isError ? 1 : 0);
    } finally {
      malloc.free(jsonPtr);
    }
    // Run the promise continuations the resolution scheduled; they may issue
    // further capability calls, which continue on later event-loop turns.
    _pumpJobs(_continuationMaxMicrotasks);
  }

  int _pumpJobs(int maxMicrotasks) {
    final executed = malloc<Int32>();
    final errorOut = malloc<Pointer<Utf8>>();
    try {
      return _library.pumpJobs(_runtime, maxMicrotasks, executed, errorOut);
    } finally {
      malloc.free(executed);
      malloc.free(errorOut);
    }
  }

  Map<String, Object?>? _takeJobError() {
    final executed = malloc<Int32>();
    final errorOut = malloc<Pointer<Utf8>>();
    try {
      final status = _library.pumpJobs(_runtime, 1, executed, errorOut);
      if (status != kPumpJobError || errorOut.value == nullptr) {
        return null;
      }
      return _decodeEnvelope(errorOut.value);
    } finally {
      malloc.free(executed);
      malloc.free(errorOut);
    }
  }

  Map<String, Object?> _decodeEnvelope(Pointer<Utf8> pointer) {
    if (pointer == nullptr) {
      return <String, Object?>{
        'ok': false,
        'kind': 'script',
        'message': 'null envelope'
      };
    }
    return jsonDecode(pointer.toDartString()) as Map<String, Object?>;
  }

  RuntimeFailure _failureFromEnvelope(
      Map<String, Object?> envelope, String? scriptId) {
    return RuntimeFailure(
      kind: _kindFromName(envelope['kind'] as String?),
      message: (envelope['message'] as String?) ?? 'Script failure.',
      scriptId: scriptId,
    );
  }

  RuntimeFailureKind _kindFromName(String? name) {
    switch (name) {
      case 'timeout':
        return RuntimeFailureKind.timeout;
      case 'memory':
        return RuntimeFailureKind.memoryLimit;
      case 'stack':
        return RuntimeFailureKind.stackOverflow;
      case 'bridge':
        return RuntimeFailureKind.bridgeError;
      default:
        return RuntimeFailureKind.scriptError;
    }
  }
}

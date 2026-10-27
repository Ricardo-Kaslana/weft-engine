/// The value type crossing the JS/Dart boundary in both directions.
///
/// Values stay JSON-compatible (null, bool, num, String, List, Map) so every
/// backend can move them across the engine boundary without lossy bridging.
typedef JsValue = Object?;

/// One unit of JavaScript source submitted to [JsSession.execute].
final class ScriptUnit {
  /// Creates a script unit; [id] attributes failures and bridge calls.
  const ScriptUnit({required this.id, required this.source, this.sourceUrl});

  /// Stable identifier used to attribute failures to this unit.
  final String id;

  /// The JavaScript source to evaluate.
  final String source;

  /// Optional location used for stack trace and log attribution.
  final Uri? sourceUrl;
}

/// Resource limits the backend must enforce for a single script execution.
///
/// A backend that cannot honor a limit fails the execution with the matching
/// [RuntimeFailureKind] instead of exceeding it.
final class ExecutionBudget {
  /// Creates a budget; the defaults bound one execution to one second and
  /// 1000 microtasks.
  const ExecutionBudget({
    this.timeout = const Duration(seconds: 1),
    this.maxMicrotasks = 1000,
  }) : assert(maxMicrotasks > 0);

  /// Wall-clock deadline for one execution; expiry maps to
  /// [RuntimeFailureKind.timeout].
  final Duration timeout;

  /// Microtask drain ceiling per execution; exceeding it maps to
  /// [RuntimeFailureKind.microtaskBudget].
  final int maxMicrotasks;
}

/// Host-supplied configuration for one runtime session.
///
/// The host owns the resources: a backend must refuse to open a session it
/// cannot run within these limits.
final class RuntimeConfig {
  /// Creates a configuration; both limits must be positive.
  RuntimeConfig({
    required this.documentId,
    required this.memoryLimitBytes,
    required this.stackLimitBytes,
    Iterable<String> enabledCapabilities = const [],
  })  : assert(memoryLimitBytes > 0),

        /// The stack limit must also be positive; no backend can honor less.
        assert(stackLimitBytes > 0),

        /// Captured unmodifiable so the config cannot change after open.
        enabledCapabilities = Set<String>.unmodifiable(enabledCapabilities);

  /// Document this session belongs to; sessions never span documents.
  final String documentId;

  /// Heap ceiling for the engine; allocation past it maps to
  /// [RuntimeFailureKind.memoryLimit].
  final int memoryLimitBytes;

  /// Call-stack ceiling; exhaustion maps to
  /// [RuntimeFailureKind.stackOverflow].
  final int stackLimitBytes;

  /// Capability namespaces this session may call; the gateway rejects the
  /// rest.
  final Set<String> enabledCapabilities;
}

/// Why a runtime operation failed, as classified by the backend.
///
/// Backends map engine-specific faults onto these values so host code can
/// handle failures uniformly.
enum RuntimeFailureKind {
  timeout,
  memoryLimit,
  stackOverflow,
  microtaskBudget,
  scriptError,
  bridgeError,
  disposed,
}

/// Structured description of why a runtime operation did not succeed.
final class RuntimeFailure {
  /// Creates a failure of [kind] with a human-readable [message].
  const RuntimeFailure(
      {required this.kind, required this.message, this.scriptId});

  /// Failure classification; hosts branch on this, not on message text.
  final RuntimeFailureKind kind;

  /// Human-readable description for logs and script-visible errors.
  final String message;

  /// [ScriptUnit.id] that caused the failure, when attributable to one script.
  final String? scriptId;
}

/// Outcome of one [JsSession.execute] call: a [value] or a [failure], never
/// both.
final class JsResult {
  /// Creates a successful result carrying [value].
  const JsResult.success(this.value) : failure = null;

  /// Creates a failed result carrying [failure]; [value] is then null.
  const JsResult.error(this.failure) : value = null;

  /// The script's return value on success; null on failure.
  final JsValue value;

  /// The failure on error; null on success.
  final RuntimeFailure? failure;

  /// Whether the execution produced a value instead of a failure.
  bool get isSuccess => failure == null;
}

/// A named event delivered from the host into a running session.
///
/// Hosts send envelopes through [JsSession.send]; scripts receive them via
/// handlers registered through the bootstrap's `weft.events.on`.
final class EventEnvelope {
  /// Creates an envelope; the payload is captured unmodifiable.
  EventEnvelope({
    required this.name,
    required this.sequence,
    Map<String, JsValue> payload = const {},
  }) : payload = Map<String, JsValue>.unmodifiable(payload);

  /// Event name scripts subscribe to through `weft.events.on`.
  final String name;

  /// Monotonic per-session delivery number used for ordering and journaling.
  final int sequence;

  /// JSON-compatible event data; defaults to empty.
  final Map<String, JsValue> payload;
}

/// One capability invocation a script requested through the bridge.
final class BridgeCall {
  /// Creates a call; the arguments are captured unmodifiable.
  BridgeCall({
    required this.sessionId,
    required this.sequence,
    required this.capability,
    required this.method,
    List<JsValue> arguments = const [],
  }) : arguments = List<JsValue>.unmodifiable(arguments);

  /// Session that issued the call.
  final String sessionId;

  /// Session-scoped monotonic number; together with [sessionId] it identifies
  /// the exchange for idempotent replay.
  final int sequence;

  /// Capability namespace being invoked, for example `weft.net`.
  final String capability;

  /// Method name within the capability's advertised method set.
  final String method;

  /// Positional JSON-compatible arguments from the script; defaults to empty.
  final List<JsValue> arguments;
}

/// Receives capability calls from a session and resolves them to results.
///
/// The engine dispatches each [BridgeCall] once per unique
/// `(sessionId, sequence)` pair; implementations such as the capability
/// gateway enforce the policy and journal settled exchanges.
abstract interface class BridgeDispatcher {
  /// Resolves one [BridgeCall] to its JSON-compatible result, or throws to
  /// reject the call.
  Future<JsValue> dispatch(BridgeCall call);
}

/// Exception carrying a [RuntimeFailure] out of operations the [JsSession]
/// contract types as `Future<void>` (event delivery on a disposed session,
/// budget enforcement during event handling). Backends throw this instead of
/// inventing their own shapes so host code can handle failures uniformly.
final class JsSessionFailure implements Exception {
  /// Creates an exception wrapping [failure].
  const JsSessionFailure(this.failure);

  /// The structured failure the operation produced.
  final RuntimeFailure failure;

  @override
  String toString() => 'JsSessionFailure(${failure.kind}: ${failure.message})';
}

/// One live JavaScript execution context opened by a [JsRuntimeBackend].
///
/// The host executes script units, delivers events, and disposes the session
/// when its document goes away; the backend enforces the configured budgets
/// and surfaces engine faults as [RuntimeFailure]s.
abstract interface class JsSession {
  /// Identifier of this session, stable for its lifetime.
  String get id;

  /// Runs one [ScriptUnit] under [budget] and resolves with its [JsResult].
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget);

  /// Delivers an [EventEnvelope] to script-registered handlers; throws
  /// [JsSessionFailure] if the session is already disposed.
  Future<void> send(EventEnvelope event);

  /// Waits until all in-flight capability exchanges and their promise
  /// continuations have settled, within the continuation budget. Sessions
  /// without asynchronous work resolve immediately.
  Future<void> settle();

  /// Releases the session; later execute or send calls fail with
  /// [RuntimeFailureKind.disposed].
  Future<void> dispose();
}

/// A JS engine adapter that opens [JsSession]s for the host.
///
/// Implementations translate the contract types into engine-specific
/// operations and map engine faults onto [RuntimeFailure] so hosts never see
/// backend-specific error shapes.
abstract interface class JsRuntimeBackend {
  /// Opens a session for [config] with capability calls routed through
  /// [bridge].
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge);
}

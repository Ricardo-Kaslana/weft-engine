import 'dart:async';

import 'package:weft_runtime_api/weft_runtime_api.dart';

/// Thrown by [FakeScriptContext.allocate] once the fake heap exceeds the
/// backend limit; the session maps it to `RuntimeFailureKind.memoryLimit`,
/// mirroring how a real engine surfaces allocation failure.
final class FakeMemoryLimitExceeded implements Exception {
  /// Creates the error from the failing allocation size and the heap ceiling.
  FakeMemoryLimitExceeded(this.requested, this.limitBytes);

  /// Bytes the scripted behavior asked [FakeScriptContext.allocate] to add.
  final int requested;

  /// Session heap ceiling the allocation ran past.
  final int limitBytes;

  @override
  String toString() => 'FakeMemoryLimitExceeded: $requested bytes requested, '
      '$limitBytes byte limit exceeded';
}

/// What a scripted fake "script" does when the session executes its id.
typedef FakeScriptBehavior = FutureOr<JsResult> Function(
    FakeScriptContext context);

/// Handle given to a scripted behavior.
///
/// The context is the fake's equivalent of a JS environment: it can call the
/// capability bridge, allocate fake heap, and produce failure results with
/// the same shapes real backends surface.
final class FakeScriptContext {
  FakeScriptContext._(this._session, this.budget, this.scriptId);

  /// Budget the session passed to `execute`; behaviors should respect it.
  final ExecutionBudget budget;

  /// Id of the executed script unit.
  final String scriptId;

  final _FakeJsSession _session;

  /// Calls the capability bridge the way `__weftBridge` would. Sequence
  /// numbers are session-scoped and monotonic, matching real backends.
  Future<JsValue> bridge(
    String capability,
    String method, [
    List<JsValue> arguments = const [],
  ]) {
    return _session.issueBridge(capability, method, arguments);
  }

  /// Grows the fake heap; throws [FakeMemoryLimitExceeded] past the limit.
  void allocate(int bytes) {
    _session._heapUsed += bytes;
    if (_session._heapUsed > _session._heapLimitBytes) {
      throw FakeMemoryLimitExceeded(bytes, _session._heapLimitBytes);
    }
  }

  /// Builds a successful result carrying [value]; `null` crosses the
  /// boundary as JS `undefined`.
  JsResult success([JsValue value]) => JsResult.success(value);

  /// Builds the [RuntimeFailureKind.timeout] error a session surfaces when
  /// a script runs past its wall-clock deadline; lets tests stage that
  /// shape without real waiting.
  JsResult timeoutFailure([String message = 'Script exceeded its deadline.']) =>

      /// Envelope builder stamps the executing behavior's [scriptId].
      JsResult.error(_failure(RuntimeFailureKind.timeout, message));

  /// Builds the [RuntimeFailureKind.memoryLimit] error a session surfaces
  /// when an allocation blows past the heap limit.
  JsResult memoryFailure([String message = 'Fake heap limit exceeded.']) =>

      /// Envelope builder stamps the executing behavior's [scriptId].
      JsResult.error(_failure(RuntimeFailureKind.memoryLimit, message));

  /// Builds the [RuntimeFailureKind.stackOverflow] error for scripts that
  /// recurse past the engine stack limit.
  JsResult stackFailure([String message = 'stack overflow']) =>

      /// Envelope builder stamps the executing behavior's [scriptId].
      JsResult.error(_failure(RuntimeFailureKind.stackOverflow, message));

  /// Builds the [RuntimeFailureKind.microtaskBudget] error for scripts that
  /// chain more promise continuations than the budget allows.
  JsResult microtaskFailure([String message = 'Microtask budget exceeded.']) =>

      /// Envelope builder stamps the executing behavior's [scriptId].
      JsResult.error(_failure(RuntimeFailureKind.microtaskBudget, message));

  /// Builds a [RuntimeFailureKind.scriptError] error carrying [message] as
  /// the failure text.
  JsResult scriptFailure(String message) =>

      /// Envelope builder stamps the executing behavior's [scriptId].
      JsResult.error(_failure(RuntimeFailureKind.scriptError, message));

  /// Shared envelope builder: every fake failure names the executed script.
  RuntimeFailure _failure(RuntimeFailureKind kind, String message) =>

      /// Results stay error-shaped exactly like real backend failures.
      RuntimeFailure(kind: kind, message: message, scriptId: scriptId);
}

/// Scripted [JsRuntimeBackend]: each `ScriptUnit.id` maps to a Dart behavior.
///
/// The fake exists so that orchestration and contract tests can run without
/// native binaries, and so backend replacement can be demonstrated without
/// touching engine code. Budget enforcement is real for the wall clock (the
/// session cuts off hung behaviors) and simulated for heap/stack/microtask
/// limits through the context helpers; the real enforcement evidence lives in
/// the QuickJS FFI tests.
final class FakeRuntimeBackend implements JsRuntimeBackend {
  /// Creates a backend whose behavior map is fixed at construction; ids
  /// missing from [behaviors] fail as script errors, except the bootstrap
  /// id which defaults to a no-op success.
  FakeRuntimeBackend({
    required Map<String, FakeScriptBehavior> behaviors,
    this.heapLimitBytes = 8 * 1024 * 1024,
  })  : _behaviors = Map<String, FakeScriptBehavior>.unmodifiable(behaviors),
        _events = StreamController<EventEnvelope>.broadcast();

  /// The capability bootstrap runs on every opened session; the fake gives
  /// it a default no-op success unless a behavior overrides the id.
  static const bootstrapScriptId = 'weft/bootstrap';

  final Map<String, FakeScriptBehavior> _behaviors;

  /// Fake heap ceiling [FakeScriptContext.allocate] grows against; it never
  /// shrinks within a session.
  final int heapLimitBytes;
  final StreamController<EventEnvelope> _events;

  /// Events delivered through [JsSession.send], for test inspection.
  Stream<EventEnvelope> get events => _events.stream;

  @override
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge) {
    return Future<JsSession>.value(
      _FakeJsSession._(this, config, bridge),
    );
  }
}

final class _FakeJsSession implements JsSession {
  _FakeJsSession._(this._backend, RuntimeConfig config, this._bridge)
      : id = 'fake:${config.documentId}:${_nextSessionId++}',
        _heapLimitBytes = _backend.heapLimitBytes;

  static int _nextSessionId = 1;

  final FakeRuntimeBackend _backend;
  final BridgeDispatcher _bridge;
  final int _heapLimitBytes;
  int _heapUsed = 0;
  int _nextSequence = 1;
  bool _disposed = false;
  final Set<Future<void>> _inflightBridges = <Future<void>>{};

  @override
  final String id;

  /// Dispatches one capability call with the next session-scoped sequence
  /// number; tracked as in-flight so [settle] waits for it.
  Future<JsValue> issueBridge(
    String capability,
    String method,
    List<JsValue> arguments,
  ) {
    final sequence = _nextSequence++;
    final call = BridgeCall(
      sessionId: id,
      sequence: sequence,
      capability: capability,
      method: method,
      arguments: arguments,
    );
    final dispatch = _bridge.dispatch(call);
    _inflightBridges.add(dispatch);
    // `whenComplete` would rethrow dispatch errors as unhandled async work;
    // route them through onError so failures stay inside the behavior.
    unawaited(dispatch.then(
      (_) => _inflightBridges.remove(dispatch),
      onError: (Object error) => _inflightBridges.remove(dispatch),
    ));
    return dispatch;
  }

  @override
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget) async {
    if (_disposed) {
      return JsResult.error(RuntimeFailure(
        kind: RuntimeFailureKind.disposed,
        message: 'Session $id is disposed.',
        scriptId: script.id,
      ));
    }
    final behavior = _backend._behaviors[script.id] ??
        (script.id == FakeRuntimeBackend.bootstrapScriptId
            ? (FakeScriptContext context) => context.success(null)
            : null);
    if (behavior == null) {
      return JsResult.error(RuntimeFailure(
        kind: RuntimeFailureKind.scriptError,
        message: 'No fake behavior registered for script "${script.id}".',
        scriptId: script.id,
      ));
    }
    final context = FakeScriptContext._(this, budget, script.id);
    // An explicit async function (not Future()): Future() hops through
    // Timer.run, which never fires inside testWidgets' fake-async zone, and
    // the declared Future<JsResult> keeps `.timeout`'s types honest.
    Future<JsResult> run() async => behavior(context);
    try {
      return await run().timeout(
        budget.timeout,
        onTimeout: () => JsResult.error(RuntimeFailure(
          kind: RuntimeFailureKind.timeout,
          message: 'Fake behavior for "${script.id}" exceeded '
              '${budget.timeout.inMilliseconds}ms.',
          scriptId: script.id,
        )),
      );
    } on FakeMemoryLimitExceeded catch (error) {
      return JsResult.error(RuntimeFailure(
        kind: RuntimeFailureKind.memoryLimit,
        message: error.toString(),
        scriptId: script.id,
      ));
    } catch (error) {
      return JsResult.error(RuntimeFailure(
        kind: RuntimeFailureKind.scriptError,
        message: error.toString(),
        scriptId: script.id,
      ));
    }
  }

  @override
  Future<void> send(EventEnvelope event) async {
    if (_disposed) {
      throw JsSessionFailure(RuntimeFailure(
        kind: RuntimeFailureKind.disposed,
        message: 'Session $id is disposed.',
      ));
    }
    _backend._events.add(event);
  }

  @override
  Future<void> settle() async {
    var guard = 0;
    while (_inflightBridges.isNotEmpty && guard++ < 256) {
      await Future<void>.delayed(Duration.zero);
    }
    if (_inflightBridges.isNotEmpty) {
      throw const JsSessionFailure(RuntimeFailure(
        kind: RuntimeFailureKind.scriptError,
        message: 'Fake session did not settle within 256 rounds.',
      ));
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

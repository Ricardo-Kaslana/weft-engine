import 'package:weft_capabilities/weft_capabilities.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

/// Host-provided services wired into the built-in capability modules.
///
/// The runtime never creates storage or network transports itself; hosts
/// inject them here, keeping the engine core free of I/O (architecture doc,
/// section 2).
final class WeftRuntimeServices {
  const WeftRuntimeServices({
    this.stateStore,
    this.networkClient,
    this.onJsEvent,
    this.onRuntimeFailure,
  });

  /// Backing store for `weft.state`; defaults to an in-memory store.
  final WeftStateStore? stateStore;

  /// Required when `weft.net` is enabled; the runtime enforces the network
  /// policy before and after handing requests to this client.
  final WeftNetworkClient? networkClient;

  /// Receives events scripts emit through `weft.events.emit`.
  final void Function(String name, Map<String, JsValue> payload)? onJsEvent;

  /// Receives every non-success [JsResult] the runtime executes.
  final void Function(RuntimeFailure failure)? onRuntimeFailure;
}

/// Report of a [WeftDocumentRuntime.recover] operation.
final class WeftRecoveryReport {
  const WeftRecoveryReport({
    required this.previousSessionId,
    required this.sessionId,
    required this.retainedBridgeEntries,
    required this.retainedNetworkEntries,
  });

  final String previousSessionId;
  final String sessionId;
  final int retainedBridgeEntries;
  final int retainedNetworkEntries;

  bool get replacedSession => previousSessionId != sessionId;
}

/// Raised when a session (fresh or recovered) cannot finish its bootstrap.
final class WeftRuntimeStartupError implements Exception {
  WeftRuntimeStartupError(this.failure);

  final RuntimeFailure failure;

  @override
  String toString() =>
      'WeftRuntimeStartupError(${failure.kind}: ${failure.message})';
}

/// Per-document JavaScript host: one [JsSession], one capability gateway, one
/// set of journals, for the lifetime of a document.
///
/// Guarantees (ADR 0033):
/// - scripts run in a single-document context; different runtimes share
///   nothing;
/// - capability visibility follows [CapabilityPolicy] — the bootstrap only
///   installs enabled namespaces and the gateway rejects the rest;
/// - [recover] replaces the session without replaying network side effects;
///   the bridge journal deduplicates re-delivered `(sessionId, sequence)`
///   pairs so recovery cannot double-spend a request.
final class WeftDocumentRuntime {
  WeftDocumentRuntime._({
    required String documentId,
    required JsRuntimeBackend backend,
    required CapabilityPolicy policy,
    required WeftRuntimeServices services,
    required WeftNetworkPolicy networkPolicy,
    required int memoryLimitBytes,
    required int stackLimitBytes,
    required ExecutionBudget bootstrapBudget,
  })  : _documentId = documentId,
        _backend = backend,
        _policy = policy,
        _services = services,
        _networkPolicy = networkPolicy,
        _bootstrapBudget = bootstrapBudget {
    final journal = WeftNetworkJournal();
    final modules = <String, CapabilityModule>{};
    if (policy.isEnabled(WeftCapabilityIds.state)) {
      modules[WeftCapabilityIds.state] = StateCapabilityModule(
        store: services.stateStore ?? MemoryWeftStateStore(),
      );
    }
    if (policy.isEnabled(WeftCapabilityIds.events)) {
      final onJsEvent = services.onJsEvent;
      modules[WeftCapabilityIds.events] = EventsCapabilityModule(
        onEmit: (name, payload) => onJsEvent?.call(name, payload),
      );
    }
    if (policy.isEnabled(WeftCapabilityIds.network)) {
      final client = services.networkClient;
      if (client == null) {
        throw ArgumentError(
          'weft.net is enabled but WeftRuntimeServices.networkClient is null; '
          'the engine never performs network I/O itself.',
        );
      }
      modules[WeftCapabilityIds.network] = NetworkCapabilityModule(
        client: client,
        policy: _networkPolicy,
        journal: journal,
      );
    }
    _networkJournal = journal;
    _gateway = CapabilityGateway(policy: policy, modules: modules);
    _config = RuntimeConfig(
      documentId: documentId,
      memoryLimitBytes: memoryLimitBytes,
      stackLimitBytes: stackLimitBytes,
      enabledCapabilities: policy.enabledNamespaces,
    );
  }

  /// Opens a runtime and runs the capability bootstrap.
  static Future<WeftDocumentRuntime> open({
    required JsRuntimeBackend backend,
    required String documentId,
    required CapabilityPolicy policy,
    WeftRuntimeServices? services,
    WeftNetworkPolicy? networkPolicy,
    int memoryLimitBytes = 16 * 1024 * 1024,
    int stackLimitBytes = 1024 * 1024,
    ExecutionBudget bootstrapBudget =
        const ExecutionBudget(timeout: Duration(seconds: 5)),
  }) async {
    final runtime = WeftDocumentRuntime._(
      documentId: documentId,
      backend: backend,
      policy: policy,
      services: services ?? const WeftRuntimeServices(),
      networkPolicy: networkPolicy ?? WeftNetworkPolicy(),
      memoryLimitBytes: memoryLimitBytes,
      stackLimitBytes: stackLimitBytes,
      bootstrapBudget: bootstrapBudget,
    );
    await runtime._openSession();
    return runtime;
  }

  final JsRuntimeBackend _backend;
  final CapabilityPolicy _policy;
  final WeftRuntimeServices _services;
  final WeftNetworkPolicy _networkPolicy;
  final ExecutionBudget _bootstrapBudget;
  final String _documentId;

  late final WeftNetworkJournal _networkJournal;
  late final CapabilityGateway _gateway;
  late final RuntimeConfig _config;

  JsSession _session = _NoSession();
  int _outboundSequence = 1;

  CapabilityGateway get gateway => _gateway;

  WeftNetworkJournal get networkJournal => _networkJournal;

  CapabilityPolicy get policy => _policy;

  String get documentId => _documentId;

  String get sessionId => _session.id;

  Future<void> _openSession() async {
    final session = await _backend.open(_config, _gateway);
    final bootstrap = weftCapabilityBootstrap(_policy.enabledNamespaces);
    final result = await session.execute(bootstrap, _bootstrapBudget);
    if (!result.isSuccess) {
      await session.dispose();
      throw WeftRuntimeStartupError(
        result.failure ??
            const RuntimeFailure(
              kind: RuntimeFailureKind.scriptError,
              message: 'Capability bootstrap failed.',
            ),
      );
    }
    await _settleQuietly(session);
    _session = session;
  }

  /// Executes a document script under [budget] and settles its asynchronous
  /// capability continuations before returning.
  Future<JsResult> execute(
    ScriptUnit script, {
    ExecutionBudget budget =
        const ExecutionBudget(timeout: Duration(seconds: 5)),
  }) async {
    final result = await _session.execute(script, budget);
    if (!result.isSuccess) {
      _services.onRuntimeFailure?.call(result.failure!);
    }
    final settleFailure = await _settleQuietly(_session);
    if (result.isSuccess && settleFailure != null) {
      return JsResult.error(settleFailure);
    }
    return result;
  }

  /// Sends a host event into the session's JS handlers.
  Future<void> sendEvent(String name, Map<String, JsValue> payload) {
    return _session.send(EventEnvelope(
      name: name,
      sequence: _outboundSequence++,
      payload: payload,
    ));
  }

  /// Replaces the underlying session after a failure or host request.
  ///
  /// Recovery re-runs only the capability bootstrap. It never re-executes
  /// document scripts and never re-issues journaled network requests; hosts
  /// that replay queued bridge calls after recovery hit the gateway's
  /// sequence dedup instead of a second network side effect.
  Future<WeftRecoveryReport> recover() async {
    final previous = _session;
    await previous.dispose();
    await _openSession();
    return WeftRecoveryReport(
      previousSessionId: previous.id,
      sessionId: _session.id,
      retainedBridgeEntries: _gateway.journal.length,
      retainedNetworkEntries: _networkJournal.entries.length,
    );
  }

  Future<void> dispose() async {
    await _session.dispose();
  }

  Future<RuntimeFailure?> _settleQuietly(JsSession session) async {
    try {
      await session.settle();
    } on JsSessionFailure catch (failure) {
      _services.onRuntimeFailure?.call(failure.failure);
      return failure.failure;
    }
    return null;
  }
}

/// Placeholder used before [open] finishes; every real operation throws.
final class _NoSession implements JsSession {
  @override
  String get id => 'weft:no-session';

  @override
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget) async {
    throw StateError('WeftDocumentRuntime is not open yet.');
  }

  @override
  Future<void> send(EventEnvelope event) async {
    throw StateError('WeftDocumentRuntime is not open yet.');
  }

  @override
  Future<void> settle() async {
    throw StateError('WeftDocumentRuntime is not open yet.');
  }

  @override
  Future<void> dispose() async {}
}

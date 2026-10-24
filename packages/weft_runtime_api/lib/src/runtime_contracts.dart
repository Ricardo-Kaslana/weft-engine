typedef JsValue = Object?;

final class ScriptUnit {
  const ScriptUnit({required this.id, required this.source, this.sourceUrl});

  final String id;
  final String source;
  final Uri? sourceUrl;
}

final class ExecutionBudget {
  const ExecutionBudget({
    this.timeout = const Duration(seconds: 1),
    this.maxMicrotasks = 1000,
  }) : assert(maxMicrotasks > 0);

  final Duration timeout;
  final int maxMicrotasks;
}

final class RuntimeConfig {
  RuntimeConfig({
    required this.documentId,
    required this.memoryLimitBytes,
    required this.stackLimitBytes,
    Iterable<String> enabledCapabilities = const [],
  })  : assert(memoryLimitBytes > 0),
        assert(stackLimitBytes > 0),
        enabledCapabilities = Set<String>.unmodifiable(enabledCapabilities);

  final String documentId;
  final int memoryLimitBytes;
  final int stackLimitBytes;
  final Set<String> enabledCapabilities;
}

enum RuntimeFailureKind {
  timeout,
  memoryLimit,
  stackOverflow,
  scriptError,
  bridgeError,
  disposed,
}

final class RuntimeFailure {
  const RuntimeFailure(
      {required this.kind, required this.message, this.scriptId});

  final RuntimeFailureKind kind;
  final String message;
  final String? scriptId;
}

final class JsResult {
  const JsResult.success(this.value) : failure = null;

  const JsResult.error(this.failure) : value = null;

  final JsValue value;
  final RuntimeFailure? failure;

  bool get isSuccess => failure == null;
}

final class EventEnvelope {
  EventEnvelope({
    required this.name,
    required this.sequence,
    Map<String, JsValue> payload = const {},
  }) : payload = Map<String, JsValue>.unmodifiable(payload);

  final String name;
  final int sequence;
  final Map<String, JsValue> payload;
}

final class BridgeCall {
  BridgeCall({
    required this.sessionId,
    required this.sequence,
    required this.capability,
    required this.method,
    List<JsValue> arguments = const [],
  }) : arguments = List<JsValue>.unmodifiable(arguments);

  final String sessionId;
  final int sequence;
  final String capability;
  final String method;
  final List<JsValue> arguments;
}

abstract interface class BridgeDispatcher {
  Future<JsValue> dispatch(BridgeCall call);
}

abstract interface class JsSession {
  String get id;

  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget);

  Future<void> send(EventEnvelope event);

  Future<void> dispose();
}

abstract interface class JsRuntimeBackend {
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge);
}

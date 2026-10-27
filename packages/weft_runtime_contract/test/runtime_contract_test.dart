import 'package:weft_runtime_api/weft_runtime_api.dart';
import 'package:weft_runtime_contract/runtime_contract.dart';

/// The simplest backend that can satisfy the contract: it maps the well-known
/// script ids straight to compliant results. Keeping it in this package
/// dogfoods the suite — a contract test that a trivial session cannot pass is
/// a contract test that real backends cannot pass either.
final class _TrivialSession implements JsSession {
  _TrivialSession(this._bridge);

  final BridgeDispatcher _bridge;
  bool _disposed = false;
  int _sequence = 1;

  @override
  String get id => 'trivial';

  @override
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget) async {
    if (_disposed) {
      return JsResult.error(RuntimeFailure(
        kind: RuntimeFailureKind.disposed,
        message: 'disposed',
        scriptId: script.id,
      ));
    }
    switch (script.id) {
      case ContractScriptIds.returnsValue:
        return const JsResult.success(42);
      case ContractScriptIds.throwsScriptError:
        return JsResult.error(_failure(
          RuntimeFailureKind.scriptError,
          'boom',
          script.id,
        ));
      case ContractScriptIds.infiniteLoop:
        return JsResult.error(_failure(
          RuntimeFailureKind.timeout,
          'interrupted',
          script.id,
        ));
      case ContractScriptIds.memoryBomb:
        return JsResult.error(_failure(
          RuntimeFailureKind.memoryLimit,
          'out of memory',
          script.id,
        ));
      case ContractScriptIds.deepRecursion:
        return JsResult.error(_failure(
          RuntimeFailureKind.stackOverflow,
          'stack overflow',
          script.id,
        ));
      case ContractScriptIds.microtaskChain:
        return JsResult.error(_failure(
          RuntimeFailureKind.microtaskBudget,
          'microtask budget exceeded',
          script.id,
        ));
      case ContractScriptIds.bridgeEcho:
        await _bridge.dispatch(BridgeCall(
          sessionId: id,
          sequence: _sequence++,
          capability: ContractBridge.capability,
          method: ContractBridge.method,
          arguments: ContractBridge.arguments,
        ));
        return const JsResult.success(null);
      default:
        return JsResult.error(_failure(
          RuntimeFailureKind.scriptError,
          'unknown script',
          script.id,
        ));
    }
  }

  RuntimeFailure _failure(
    RuntimeFailureKind kind,
    String message,
    String? scriptId,
  ) {
    return RuntimeFailure(kind: kind, message: message, scriptId: scriptId);
  }

  @override
  Future<void> send(EventEnvelope event) async {
    if (_disposed) {
      throw const JsSessionFailure(RuntimeFailure(
        kind: RuntimeFailureKind.disposed,
        message: 'disposed',
      ));
    }
  }

  @override
  Future<void> settle() async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

void main() {
  registerJsSessionContractTests(
    backendName: 'trivial inline',
    openSession: (bridge) async => _TrivialSession(bridge),
  );
}

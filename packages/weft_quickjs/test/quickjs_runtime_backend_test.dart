import 'package:test/test.dart';
import 'package:weft_quickjs/weft_quickjs.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

final class _FakeSession implements JsSession {
  @override
  String get id => 'fake-session';

  @override
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget) async {
    return const JsResult.success(null);
  }

  @override
  Future<void> send(EventEnvelope event) async {}

  @override
  Future<void> settle() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeBridge implements BridgeDispatcher {
  @override
  Future<JsValue> dispatch(BridgeCall call) async => null;
}

final class _FakeNativeAdapter implements QuickJsNativeAdapter {
  RuntimeConfig? lastConfig;

  @override
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge) async {
    lastConfig = config;
    return _FakeSession();
  }
}

void main() {
  test('backend delegates session creation to the native boundary', () async {
    final adapter = _FakeNativeAdapter();
    final backend = QuickJsRuntimeBackend(adapter);
    final config = RuntimeConfig(
      documentId: 'doc-1',
      memoryLimitBytes: 16 * 1024 * 1024,
      stackLimitBytes: 1024 * 1024,
    );

    final session = await backend.open(config, _FakeBridge());

    expect(session.id, 'fake-session');
    expect(identical(adapter.lastConfig, config), isTrue);
  });
}

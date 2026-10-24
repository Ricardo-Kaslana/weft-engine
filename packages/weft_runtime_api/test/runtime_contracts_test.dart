import 'package:test/test.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

void main() {
  test('runtime config freezes enabled capabilities', () {
    final config = RuntimeConfig(
      documentId: 'doc-1',
      memoryLimitBytes: 16 * 1024 * 1024,
      stackLimitBytes: 1024 * 1024,
      enabledCapabilities: const {'weft.state'},
    );

    expect(config.enabledCapabilities, contains('weft.state'));
    expect(
      () => config.enabledCapabilities.add('weft.net'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('runtime failure produces an unsuccessful result', () {
    const result = JsResult.error(
      RuntimeFailure(
          kind: RuntimeFailureKind.timeout, message: 'Deadline exceeded.'),
    );

    expect(result.isSuccess, isFalse);
    expect(result.failure?.kind, RuntimeFailureKind.timeout);
  });
}

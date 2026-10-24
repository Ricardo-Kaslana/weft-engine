import 'package:test/test.dart';
import 'package:weft_capabilities/weft_capabilities.dart';

void main() {
  test('policy exposes only explicitly enabled capabilities', () {
    final policy = CapabilityPolicy(enabled: const {WeftCapabilityIds.state});

    expect(policy.isEnabled(WeftCapabilityIds.state), isTrue);
    expect(policy.isEnabled(WeftCapabilityIds.network), isFalse);
    expect(
      () => policy.enabledNamespaces.add(WeftCapabilityIds.network),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('custom capability namespaces are allowed', () {
    final policy = CapabilityPolicy(enabled: const {'example.catalog'});

    expect(policy.isEnabled('example.catalog'), isTrue);
  });
}

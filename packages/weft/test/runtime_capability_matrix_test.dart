import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_runtime_fake/weft_runtime_fake.dart';

/// Capability policy matrix (ADR 0034): every subset of the built-in
/// capabilities must work independently — an enabled capability passes its
/// probe, a disabled one is rejected by the gateway without side effects,
/// and the bootstrap only installs the enabled namespaces.
///
/// Together with the QuickJS visibility test (`typeof weft.state ===
/// 'undefined'` when disabled) this is the evidence for the phase 5
/// acceptance item "JS 和单能力可独立关闭": the whole runtime is already
/// optional at the engine level — [WeftView] never touches it — so turning
/// JS off is simply not opening a [WeftDocumentRuntime].
void main() {
  final subsets = <Set<String>>[
    const <String>{},
    const {WeftCapabilityIds.state},
    const {WeftCapabilityIds.events},
    const {WeftCapabilityIds.network},
    const {WeftCapabilityIds.state, WeftCapabilityIds.events},
    const {WeftCapabilityIds.state, WeftCapabilityIds.network},
    const {WeftCapabilityIds.events, WeftCapabilityIds.network},
    WeftCapabilityIds.builtIn,
  ];

  Map<String, FakeScriptBehavior> probeBehaviors() =>
      <String, FakeScriptBehavior>{
        for (final namespace in WeftCapabilityIds.builtIn)
          'probe:$namespace': (context) async {
            switch (namespace) {
              case WeftCapabilityIds.state:
                await context.bridge(
                    WeftCapabilityIds.state, 'set', <JsValue>['k', 'v']);
                return context.success(await context
                    .bridge(WeftCapabilityIds.state, 'get', <JsValue>['k']));
              case WeftCapabilityIds.events:
                await context.bridge(WeftCapabilityIds.events, 'emit',
                    <JsValue>['probe', <String, JsValue>{}]);
                return context.success(null);
              case WeftCapabilityIds.network:
                return context.success(await context.bridge(
                  WeftCapabilityIds.network,
                  'fetch',
                  <JsValue>['https://cdn.example.com/probe'],
                ));
            }
            return context.success(null);
          },
      };

  String probeLabel(Set<String> enabled) =>
      enabled.isEmpty ? '{} (JS fully closed)' : enabled.join(' + ');

  for (final enabled in subsets) {
    group('capability policy ${probeLabel(enabled)}', () {
      test('enabled capabilities pass; disabled ones are invisible', () async {
        final client = _CountingNetworkClient();
        final runtime = await WeftDocumentRuntime.open(
          backend: FakeRuntimeBackend(behaviors: probeBehaviors()),
          documentId: 'matrix',
          policy: CapabilityPolicy(enabled: enabled),
          services: WeftRuntimeServices(
            stateStore: MemoryWeftStateStore(),
            networkClient: client,
          ),
          networkPolicy: WeftNetworkPolicy(
            allowedHosts: {'cdn.example.com'},
          ),
        );
        addTearDown(runtime.dispose);

        for (final namespace in WeftCapabilityIds.builtIn) {
          final result = await runtime.execute(
            ScriptUnit(id: 'probe:$namespace', source: ''),
          );
          if (enabled.contains(namespace)) {
            expect(
              result.isSuccess,
              isTrue,
              reason: '$namespace is enabled and must pass its probe '
                  '(${result.failure?.message})',
            );
          } else {
            expect(
              result.isSuccess,
              isFalse,
              reason: '$namespace is disabled and must be rejected',
            );
            expect(result.failure?.message, contains('not enabled'));
          }
        }

        // A disabled network capability must never reach the host client.
        expect(
          client.requestCount,
          enabled.contains(WeftCapabilityIds.network) ? 1 : 0,
          reason: 'network side effects follow the policy exactly',
        );
      });
    });
  }

  test('bootstrap installs only the enabled namespaces', () {
    // Release contract anchor (docs/release-runbook.md §2): the bootstrap
    // script id and the bridge protocol version are compatibility anchors;
    // changing them must update the runbook in the same commit.
    final bootstrap = weftCapabilityBootstrap(const {WeftCapabilityIds.state});
    expect(bootstrap.id, 'weft/bootstrap');
    expect(bootstrap.source, contains('bridgeVersion: 1'));
    final script = bootstrap.source;
    expect(script, contains("enabled.indexOf('weft.state')"));
    for (final disabled in const [
      WeftCapabilityIds.events,
      WeftCapabilityIds.network
    ]) {
      expect(
        script,
        isNot(contains("enabled.indexOf('$disabled')")),
        reason: 'disabled $disabled must not even be referenced by the gates',
      );
    }
  });
}

final class _CountingNetworkClient implements WeftNetworkClient {
  int requestCount = 0;

  @override
  Future<WeftNetworkResponse> request(WeftNetworkRequest request) async {
    requestCount += 1;
    return const WeftNetworkResponse(status: 200, body: '{}');
  }
}

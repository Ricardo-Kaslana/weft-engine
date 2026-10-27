import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_quickjs/weft_quickjs.dart';

final class _RecordingNetworkClient implements WeftNetworkClient {
  final List<WeftNetworkRequest> requests = <WeftNetworkRequest>[];

  @override
  Future<WeftNetworkResponse> request(WeftNetworkRequest request) async {
    requests.add(request);
    return const WeftNetworkResponse(status: 200, body: 'ok');
  }
}

void main() {
  final nativeReady = QuickJsNativeLibrary.isLoadable;

  group('WeftDocumentRuntime on QuickJS', () {
    test('bootstrap installs only enabled capability namespaces', () async {
      final runtime = await WeftDocumentRuntime.open(
        backend: QuickJsFfiBackend(),
        documentId: 'doc-visibility',
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.state}),
      );
      addTearDown(runtime.dispose);

      final net = await runtime.execute(
        const ScriptUnit(id: 'probe-net', source: 'typeof weft.net'),
      );
      final state = await runtime.execute(
        const ScriptUnit(id: 'probe-state', source: 'typeof weft.state'),
      );
      final events = await runtime.execute(
        const ScriptUnit(id: 'probe-events', source: 'typeof weft.events'),
      );

      expect(net.value, 'undefined');
      expect(state.value, 'object');
      expect(events.value, 'undefined');
    });

    test('state round-trips through the real JS bridge', () async {
      final runtime = await WeftDocumentRuntime.open(
        backend: QuickJsFfiBackend(),
        documentId: 'doc-state',
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.state}),
      );
      addTearDown(runtime.dispose);

      await runtime.execute(
        const ScriptUnit(
          id: 'main',
          source: 'weft.state.set("n", 5)'
              '.then(function () { return weft.state.get("n"); })'
              '.then(function (value) { globalThis.__n = value; });',
        ),
      );
      final probe = await runtime.execute(
        const ScriptUnit(id: 'probe', source: 'globalThis.__n'),
      );

      expect(probe.value, 5);
    });

    test('host events reach JS handlers registered via weft.events.on',
        () async {
      final runtime = await WeftDocumentRuntime.open(
        backend: QuickJsFfiBackend(),
        documentId: 'doc-events',
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.events}),
      );
      addTearDown(runtime.dispose);

      await runtime.execute(
        const ScriptUnit(
          id: 'install',
          source: 'weft.events.on("tick", function (payload) '
              '{ globalThis.__tick = payload; });',
        ),
      );
      await runtime.sendEvent('tick', const {'i': 7});

      final probe = await runtime.execute(
        const ScriptUnit(id: 'probe', source: 'globalThis.__tick'),
      );
      expect(probe.value, <Object?, Object?>{'i': 7});
    });

    test('illegal protocols are intercepted before the host client', () async {
      final client = _RecordingNetworkClient();
      final runtime = await WeftDocumentRuntime.open(
        backend: QuickJsFfiBackend(),
        documentId: 'doc-net-policy',
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.network}),
        services: WeftRuntimeServices(networkClient: client),
        networkPolicy: WeftNetworkPolicy(
          allowedHosts: const {'cdn.example.com'},
        ),
      );
      addTearDown(runtime.dispose);

      await runtime.execute(
        const ScriptUnit(
          id: 'fetch-illegal',
          source: 'weft.net.fetch("file:///etc/passwd")'
              '.catch(function (error) '
              '{ globalThis.__err = String(error.message); });',
        ),
      );

      final probe = await runtime.execute(
        const ScriptUnit(id: 'probe', source: 'globalThis.__err'),
      );
      expect(
        probe.value as String,
        contains('not allowed'),
      );
      expect(client.requests, isEmpty);
    });

    test('rejected scripts still leave the surface frame intact', () async {
      final runtime = await WeftDocumentRuntime.open(
        backend: QuickJsFfiBackend(),
        documentId: 'doc-frame',
        policy: CapabilityPolicy(enabled: const <String>{}),
      );
      addTearDown(runtime.dispose);

      final result = await runtime.execute(
        const ScriptUnit(
          id: 'spin',
          source: 'while (true) {}',
        ),
        budget: const ExecutionBudget(timeout: Duration(milliseconds: 80)),
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.timeout);
    });
  },
      skip: nativeReady
          ? null
          : 'QuickJS native library is not built; run '
              'packages/weft_quickjs/tool/build_native.sh');
}

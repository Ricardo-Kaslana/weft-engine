import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_runtime_fake/weft_runtime_fake.dart';

final class _RecordingNetworkClient implements WeftNetworkClient {
  final List<WeftNetworkRequest> requests = <WeftNetworkRequest>[];

  @override
  Future<WeftNetworkResponse> request(WeftNetworkRequest request) async {
    requests.add(request);
    return WeftNetworkResponse(
        status: 200, body: 'payload-from-${request.url.host}');
  }
}

void main() {
  group('WeftDocumentRuntime', () {
    test('routes state and events for document scripts', () async {
      final store = MemoryWeftStateStore();
      final emitted = <MapEntry<String, Map<String, JsValue>>>[];
      final backend = FakeRuntimeBackend(behaviors: {
        'set-and-get': (context) async {
          await context.bridge(
              WeftCapabilityIds.state, 'set', <JsValue>['greeting', 'hi']);
          return context.success(
            await context
                .bridge(WeftCapabilityIds.state, 'get', <JsValue>['greeting']),
          );
        },
        'emit-hello': (context) async {
          await context.bridge(WeftCapabilityIds.events, 'emit', <JsValue>[
            'hello',
            <String, JsValue>{'n': 1}
          ]);
          return context.success(null);
        },
      });

      final runtime = await WeftDocumentRuntime.open(
        backend: backend,
        documentId: 'doc-runtime',
        policy: CapabilityPolicy(enabled: const {
          WeftCapabilityIds.state,
          WeftCapabilityIds.events,
        }),
        services: WeftRuntimeServices(
          stateStore: store,
          onJsEvent: (name, payload) => emitted.add(MapEntry(name, payload)),
        ),
      );
      addTearDown(runtime.dispose);

      final result = await runtime.execute(
        const ScriptUnit(id: 'set-and-get', source: ''),
      );
      expect(result.isSuccess, isTrue);
      expect(result.value, 'hi');
      expect(store.get('greeting'), 'hi');

      await runtime.execute(const ScriptUnit(id: 'emit-hello', source: ''));
      expect(emitted.single.key, 'hello');
      expect(emitted.single.value, <String, JsValue>{'n': 1});
    });

    test('recovers without replaying network side effects', () async {
      final client = _RecordingNetworkClient();
      final backend = FakeRuntimeBackend(behaviors: {
        'fetch-once': (context) async {
          return context.success(await context.bridge(
            WeftCapabilityIds.network,
            'fetch',
            <JsValue>['https://cdn.example.com/data.json'],
          ));
        },
      });

      final runtime = await WeftDocumentRuntime.open(
        backend: backend,
        documentId: 'doc-recovery',
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.network}),
        services: WeftRuntimeServices(networkClient: client),
        networkPolicy: WeftNetworkPolicy(
          allowedHosts: const {'cdn.example.com'},
        ),
      );
      addTearDown(runtime.dispose);

      final first = await runtime.execute(
        const ScriptUnit(id: 'fetch-once', source: ''),
      );
      expect(first.isSuccess, isTrue);
      expect(first.value, <String, JsValue>{
        'status': 200,
        'body': 'payload-from-cdn.example.com',
        'url': 'https://cdn.example.com/data.json',
      });
      expect(client.requests, hasLength(1));

      final settledCall = runtime.gateway.journal.last.call;
      final sessionIdBefore = runtime.sessionId;

      final report = await runtime.recover();

      expect(report.replacedSession, isTrue);
      expect(report.previousSessionId, sessionIdBefore);
      expect(report.sessionId, runtime.sessionId);
      expect(report.retainedBridgeEntries, greaterThanOrEqualTo(1));
      expect(report.retainedNetworkEntries, greaterThanOrEqualTo(1));
      // Recovery itself performs no I/O.
      expect(client.requests, hasLength(1));

      // A queued command from the crashed session gets re-delivered after
      // recovery: the gateway deduplicates it by (sessionId, sequence) and
      // the network client runs exactly once across both rounds.
      final replayed = await runtime.gateway.dispatch(settledCall);
      expect(replayed, first.value);
      expect(client.requests, hasLength(1));

      // The new session can still make fresh requests.
      final second = await runtime.execute(
        const ScriptUnit(id: 'fetch-once', source: ''),
      );
      expect(second.isSuccess, isTrue);
      expect(client.requests, hasLength(2));
    });

    test('denies capabilities the policy did not enable', () async {
      final backend = FakeRuntimeBackend(behaviors: {
        'touch-network': (context) async {
          await context.bridge(WeftCapabilityIds.network, 'fetch',
              <JsValue>['https://cdn.example.com/x']);
          return context.success(null);
        },
      });

      final runtime = await WeftDocumentRuntime.open(
        backend: backend,
        documentId: 'doc-denied',
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.state}),
      );
      addTearDown(runtime.dispose);

      final result = await runtime.execute(
        const ScriptUnit(id: 'touch-network', source: ''),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.message, contains('not enabled'));
    });

    test('surfaces runtime failures to the host callback', () async {
      final failures = <RuntimeFailure>[];
      const scriptId = 'spin-forever';
      final backend = FakeRuntimeBackend(behaviors: {
        scriptId: (context) => Completer<JsResult>().future,
      });

      final runtime = await WeftDocumentRuntime.open(
        backend: backend,
        documentId: 'doc-failure',
        policy: CapabilityPolicy(enabled: const <String>{}),
        services: WeftRuntimeServices(onRuntimeFailure: failures.add),
      );
      addTearDown(runtime.dispose);

      final result = await runtime.execute(
        const ScriptUnit(id: scriptId, source: ''),
        budget: const ExecutionBudget(timeout: Duration(milliseconds: 80)),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.timeout);
      expect(failures.single.kind, RuntimeFailureKind.timeout);
    });
  });
}

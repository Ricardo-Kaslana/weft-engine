import 'package:test/test.dart';
import 'package:weft_capabilities/weft_capabilities.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

BridgeCall _call({
  String sessionId = 'session-1',
  int sequence = 1,
  required String capability,
  required String method,
  List<JsValue> arguments = const [],
}) {
  return BridgeCall(
    sessionId: sessionId,
    sequence: sequence,
    capability: capability,
    method: method,
    arguments: arguments,
  );
}

final class _StubModule implements CapabilityModule {
  _StubModule(this.namespace);

  final String namespace;
  int invocations = 0;

  @override
  CapabilityDescriptor get descriptor => CapabilityDescriptor(
        namespace: namespace,
        apiVersion: 1,
        methods: const {'ping'},
      );

  @override
  Future<JsValue> invoke(BridgeCall call) async {
    invocations++;
    return 'pong';
  }
}

void main() {
  group('CapabilityGateway', () {
    test('rejects modules that the policy does not enable', () {
      expect(
        () => CapabilityGateway(
          policy: CapabilityPolicy(enabled: const {'example.a'}),
          modules: {'example.b': _StubModule('example.b')},
        ),
        throwsArgumentError,
      );
    });

    test('denies disabled capabilities without invoking any module', () async {
      final state = StateCapabilityModule(store: MemoryWeftStateStore());
      final gateway = CapabilityGateway(
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.state}),
        modules: {WeftCapabilityIds.state: state},
      );

      await expectLater(
        gateway.dispatch(
          _call(capability: WeftCapabilityIds.network, method: 'fetch'),
        ),
        throwsA(isA<WeftCapabilityDenied>()),
      );
    });

    test('denies methods outside the module descriptor', () async {
      final gateway = CapabilityGateway(
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.state}),
        modules: {
          WeftCapabilityIds.state:
              StateCapabilityModule(store: MemoryWeftStateStore()),
        },
      );

      await expectLater(
        gateway.dispatch(
          _call(capability: WeftCapabilityIds.state, method: 'delete'),
        ),
        throwsA(isA<WeftCapabilityDenied>()),
      );
    });

    test('routes enabled calls to their module', () async {
      final state = StateCapabilityModule(store: MemoryWeftStateStore());
      final gateway = CapabilityGateway(
        policy: CapabilityPolicy(enabled: const {WeftCapabilityIds.state}),
        modules: {WeftCapabilityIds.state: state},
      );

      await gateway.dispatch(_call(
        capability: WeftCapabilityIds.state,
        method: 'set',
        arguments: const ['greeting', 'hi'],
      ));
      final value = await gateway.dispatch(_call(
        sequence: 2,
        capability: WeftCapabilityIds.state,
        method: 'get',
        arguments: const ['greeting'],
      ));

      expect(value, 'hi');
    });

    test('deduplicates re-delivered (sessionId, sequence) pairs', () async {
      final module = _StubModule('example.a');
      final gateway = CapabilityGateway(
        policy: CapabilityPolicy(enabled: const {'example.a'}),
        modules: {'example.a': module},
      );

      final first = await gateway.dispatch(
        _call(
            sessionId: 's1',
            sequence: 7,
            capability: 'example.a',
            method: 'ping'),
      );
      final replay = await gateway.dispatch(
        _call(
            sessionId: 's1',
            sequence: 7,
            capability: 'example.a',
            method: 'ping'),
      );

      expect(first, 'pong');
      expect(replay, 'pong');
      expect(module.invocations, 1);
      expect(gateway.hasSeen('s1', 7), isTrue);
      expect(gateway.hasSeen('s1', 8), isFalse);
    });

    test('keeps the journal bounded', () async {
      final gateway = CapabilityGateway(
        policy: CapabilityPolicy(enabled: const {'example.a'}),
        modules: {'example.a': _StubModule('example.a')},
        journalCapacity: 8,
      );

      for (var sequence = 1; sequence <= 20; sequence++) {
        await gateway.dispatch(
          _call(sequence: sequence, capability: 'example.a', method: 'ping'),
        );
      }

      expect(gateway.journal, hasLength(8));
      expect(gateway.hasSeen('session-1', 1), isFalse);
      expect(gateway.hasSeen('session-1', 20), isTrue);
    });
  });

  group('NetworkCapabilityModule', () {
    late _RecordingClient client;
    late NetworkCapabilityModule module;

    setUp(() {
      client = _RecordingClient();
      module = NetworkCapabilityModule(
        client: client,
        policy: WeftNetworkPolicy(
          allowedSchemes: const {'https'},
          allowedHosts: const {'cdn.example.com'},
        ),
      );
    });

    test('blocks illegal protocols before the client runs', () async {
      for (final url in <String>[
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/html,hi',
      ]) {
        await expectLater(
          module.invoke(_call(
              capability: WeftCapabilityIds.network,
              method: 'fetch',
              arguments: [url])),
          throwsA(isA<WeftNetworkPolicyError>()),
          reason: url,
        );
      }
      expect(client.requests, isEmpty);
      expect(
        module.journal.entries.map((entry) => entry.outcome),
        everyElement(WeftNetworkOutcome.blocked),
      );
    });

    test('blocks hosts outside the whitelist', () async {
      await expectLater(
        module.invoke(_call(
          capability: WeftCapabilityIds.network,
          method: 'fetch',
          arguments: ['https://evil.example.net/payload'],
        )),
        throwsA(isA<WeftNetworkPolicyError>()),
      );
      expect(client.requests, isEmpty);
    });

    test('completes whitelisted fetches and journals them', () async {
      client.nextResponse = const WeftNetworkResponse(
        status: 200,
        body: 'payload',
      );

      final result = await module.invoke(_call(
        capability: WeftCapabilityIds.network,
        method: 'fetch',
        arguments: ['https://cdn.example.com/data.json'],
      ));

      expect(result, <String, JsValue>{
        'status': 200,
        'body': 'payload',
        'url': 'https://cdn.example.com/data.json',
      });
      expect(client.requests.single.url.toString(),
          'https://cdn.example.com/data.json');
      expect(module.journal.entries.last.outcome, WeftNetworkOutcome.completed);
    });

    test('intercepts redirects that leave the whitelist', () async {
      client.nextResponse = WeftNetworkResponse(
        status: 200,
        body: 'stolen',
        redirectChain: <Uri>[
          Uri.parse('https://cdn.example.com/a'),
          Uri.parse('https://evil.example.net/b'),
        ],
      );

      await expectLater(
        module.invoke(_call(
          capability: WeftCapabilityIds.network,
          method: 'fetch',
          arguments: ['https://cdn.example.com/a'],
        )),
        throwsA(isA<WeftNetworkPolicyError>()),
      );
      final entry = module.journal.entries.last;
      expect(entry.outcome, WeftNetworkOutcome.requested);
      expect(entry.detail, isNull);
    });

    test('enforces the redirect hop limit', () async {
      client.nextResponse = WeftNetworkResponse(
        status: 200,
        body: 'looped',
        redirectChain: List<Uri>.generate(
          7,
          (index) => Uri.parse('https://cdn.example.com/hop$index'),
        ),
      );

      await expectLater(
        module.invoke(_call(
          capability: WeftCapabilityIds.network,
          method: 'fetch',
          arguments: ['https://cdn.example.com/hop0'],
        )),
        throwsA(isA<WeftNetworkPolicyError>()),
      );
    });
  });

  group('weftCapabilityBootstrap', () {
    test('only mentions enabled namespaces', () {
      final source =
          weftCapabilityBootstrap(const {WeftCapabilityIds.state}).source;
      expect(source, contains("enabled.indexOf('weft.state')"));
      expect(source, isNot(contains('weft.net')));
      expect(source, isNot(contains('weft.events')));
    });

    test('installs every namespace that is enabled', () {
      final source = weftCapabilityBootstrap(WeftCapabilityIds.builtIn).source;
      for (final namespace in WeftCapabilityIds.builtIn) {
        expect(source, contains("enabled.indexOf('$namespace')"));
      }
      expect(source, contains('__weftOnEvent'));
    });
  });
}

final class _RecordingClient implements WeftNetworkClient {
  final List<WeftNetworkRequest> requests = <WeftNetworkRequest>[];
  WeftNetworkResponse nextResponse =
      const WeftNetworkResponse(status: 200, body: '');

  @override
  Future<WeftNetworkResponse> request(WeftNetworkRequest request) async {
    requests.add(request);
    return nextResponse;
  }
}

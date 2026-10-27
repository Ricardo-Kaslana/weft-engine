import 'dart:async';

import 'package:test/test.dart';
import 'package:weft_runtime_contract/runtime_contract.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';
import 'package:weft_runtime_fake/weft_runtime_fake.dart';

void main() {
  final backend = FakeRuntimeBackend(behaviors: <String, FakeScriptBehavior>{
    ContractScriptIds.returnsValue: (context) => context.success(42),
    ContractScriptIds.throwsScriptError: (context) =>
        context.scriptFailure('boom'),
    ContractScriptIds.infiniteLoop: (context) =>
        Completer<JsResult>().future, // never completes; session cuts it off
    ContractScriptIds.memoryBomb: (context) async {
      while (true) {
        context.allocate(1 << 20);
      }
    },
    ContractScriptIds.deepRecursion: (context) => context.stackFailure(),
    ContractScriptIds.microtaskChain: (context) => context.microtaskFailure(),
    ContractScriptIds.bridgeEcho: (context) async {
      await context.bridge(
        ContractBridge.capability,
        ContractBridge.method,
        ContractBridge.arguments,
      );
      return context.success(null);
    },
  });

  registerJsSessionContractTests(
    backendName: 'FakeRuntime',
    openSession: (bridge) => backend.open(
      RuntimeConfig(
        documentId: 'contract',
        memoryLimitBytes: 8 * 1024 * 1024,
        stackLimitBytes: 256 * 1024,
      ),
      bridge,
    ),
  );

  group('FakeRuntime specifics', () {
    test('delivers host events on the backend stream', () async {
      final session = await backend.open(
        RuntimeConfig(
          documentId: 'events',
          memoryLimitBytes: 1024,
          stackLimitBytes: 1024,
        ),
        _NoBridge(),
      );
      addTearDown(session.dispose);

      final received = <EventEnvelope>[];
      final subscription = backend.events.listen(received.add);
      addTearDown(subscription.cancel);

      await session.send(EventEnvelope(name: 'tick', sequence: 4));

      expect(received.single.name, 'tick');
      expect(received.single.sequence, 4);
    });

    test('reports unknown script ids as script errors', () async {
      final session = await backend.open(
        RuntimeConfig(
          documentId: 'unknown',
          memoryLimitBytes: 1024,
          stackLimitBytes: 1024,
        ),
        _NoBridge(),
      );
      addTearDown(session.dispose);

      final result = await session.execute(
        const ScriptUnit(id: 'nope', source: ''),
        const ExecutionBudget(),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.scriptError);
      expect(result.failure?.message, contains('nope'));
    });

    test('exposes monotonic bridge sequence numbers', () async {
      final fakeBackend = FakeRuntimeBackend(behaviors: {
        'seq-test': (context) async {
          await context.bridge('a', 'one');
          await context.bridge('a', 'two');
          return context.success(null);
        },
      });
      final recorder = _RecordingBridge();
      final seqSession = await fakeBackend.open(
        RuntimeConfig(
          documentId: 'seq2',
          memoryLimitBytes: 1024,
          stackLimitBytes: 1024,
        ),
        recorder,
      );
      addTearDown(seqSession.dispose);

      await seqSession.execute(
        const ScriptUnit(id: 'seq-test', source: ''),
        const ExecutionBudget(),
      );
      await seqSession.settle();

      expect(recorder.calls.map((call) => call.sequence).toList(),
          unorderedEquals(<int>[1, 2]));
    });
  });
}

final class _NoBridge implements BridgeDispatcher {
  @override
  Future<JsValue> dispatch(BridgeCall call) async => null;
}

final class _RecordingBridge implements BridgeDispatcher {
  final List<BridgeCall> calls = <BridgeCall>[];

  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    calls.add(call);
    return null;
  }
}

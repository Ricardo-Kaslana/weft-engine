import 'dart:async';

import 'package:test/test.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

/// Well-known script ids the contract suite executes. Backends map these ids
/// to whatever their execution model needs (JS sources for QuickJS, Dart
/// behaviors for the fake).
abstract final class ContractScriptIds {
  static const returnsValue = 'contract/returns-value';
  static const throwsScriptError = 'contract/throws-script-error';
  static const infiniteLoop = 'contract/infinite-loop';
  static const memoryBomb = 'contract/memory-bomb';
  static const deepRecursion = 'contract/deep-recursion';
  static const microtaskChain = 'contract/microtask-chain';
  static const bridgeEcho = 'contract/bridge-echo';
}

/// The capability/method pair the bridge contract test uses.
abstract final class ContractBridge {
  static const capability = 'contract.cap';
  static const method = 'echo';
  static const arguments = <JsValue>['hello'];
}

final class _RecordingBridge implements BridgeDispatcher {
  final List<BridgeCall> calls = <BridgeCall>[];

  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    calls.add(call);
    if (call.capability == ContractBridge.capability &&
        call.method == ContractBridge.method) {
      return ContractBridge.arguments.first;
    }
    return null;
  }
}

const _contractBudget = ExecutionBudget(
  timeout: Duration(seconds: 3),
  maxMicrotasks: 64,
);

/// Registers the backend-neutral [JsSession] contract tests.
///
/// Every [JsRuntimeBackend] implementation must pass this suite unchanged:
/// that is what makes backend replacement a contract guarantee rather than a
/// hope (development plan, phase 4). [openSession] receives a fresh recording
/// bridge per test. [sourceFor] is only meaningful for backends that execute
/// real sources; scripted backends key off the script id instead.
void registerJsSessionContractTests({
  required String backendName,
  required Future<JsSession> Function(BridgeDispatcher bridge) openSession,
  String sourceFor(String id)?,
}) {
  String sourceOf(String id) => sourceFor?.call(id) ?? id;

  group('JsSession contract [$backendName]', () {
    late JsSession session;
    late _RecordingBridge bridge;

    setUp(() async {
      bridge = _RecordingBridge();
      session = await openSession(bridge);
      addTearDown(session.dispose);
    });

    test('executes a value-returning unit', () async {
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.returnsValue,
          source: sourceOf(ContractScriptIds.returnsValue),
        ),
        _contractBudget,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, 42);
    });

    test('surfaces script errors with their message', () async {
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.throwsScriptError,
          source: sourceOf(ContractScriptIds.throwsScriptError),
        ),
        _contractBudget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.scriptError);
      expect(result.failure?.message, contains('boom'));
    });

    test('interrupts infinite loops at the wall-clock budget', () async {
      final watch = Stopwatch()..start();
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.infiniteLoop,
          source: sourceOf(ContractScriptIds.infiniteLoop),
        ),
        const ExecutionBudget(timeout: Duration(milliseconds: 150)),
      );
      watch.stop();

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.timeout);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('interrupts memory bombs at the heap limit', () async {
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.memoryBomb,
          source: sourceOf(ContractScriptIds.memoryBomb),
        ),
        _contractBudget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.memoryLimit);
    });

    test('reports stack overflow as its own kind', () async {
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.deepRecursion,
          source: sourceOf(ContractScriptIds.deepRecursion),
        ),
        _contractBudget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.stackOverflow);
    });

    test('stops microtask bombs at the microtask budget', () async {
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.microtaskChain,
          source: sourceOf(ContractScriptIds.microtaskChain),
        ),
        _contractBudget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.microtaskBudget);
    });

    test('routes capability calls through the bridge', () async {
      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.bridgeEcho,
          source: sourceOf(ContractScriptIds.bridgeEcho),
        ),
        _contractBudget,
      );
      await session.settle();

      expect(result.isSuccess, isTrue);
      expect(bridge.calls, hasLength(1));
      final call = bridge.calls.single;
      expect(call.sessionId, session.id);
      expect(call.capability, ContractBridge.capability);
      expect(call.method, ContractBridge.method);
      expect(call.arguments, ContractBridge.arguments);
      expect(call.sequence, greaterThanOrEqualTo(1));
    });

    test('delivers host events and settles cleanly', () async {
      await session.send(
        EventEnvelope(name: 'contract-event', sequence: 1),
      );
      await session.settle();
    });

    test('rejects work after disposal', () async {
      await session.dispose();

      final result = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.returnsValue,
          source: sourceOf(ContractScriptIds.returnsValue),
        ),
        _contractBudget,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.disposed);
      await expectLater(
        session.send(EventEnvelope(name: 'late', sequence: 1)),
        throwsA(isA<JsSessionFailure>()),
      );
    });
  });
}

import 'dart:async';

import 'package:test/test.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

/// Well-known script ids the contract suite executes. Backends map these ids
/// to whatever their execution model needs (JS sources for QuickJS, Dart
/// behaviors for the fake).
abstract final class ContractScriptIds {
  /// Id of the unit that must evaluate to `42`: the plain
  /// execute-and-return-value path.
  static const returnsValue = 'contract/returns-value';

  /// Id of the unit that throws with `boom` in its message, proving script
  /// errors surface as [RuntimeFailureKind.scriptError].
  static const throwsScriptError = 'contract/throws-script-error';

  /// Id of the unit that loops forever, proving the wall-clock budget cuts
  /// execution off with [RuntimeFailureKind.timeout].
  static const infiniteLoop = 'contract/infinite-loop';

  /// Id of the unit that allocates without bound, proving the heap limit
  /// answers with [RuntimeFailureKind.memoryLimit].
  static const memoryBomb = 'contract/memory-bomb';

  /// Id of the unit that recurses without bound, proving the engine reports
  /// [RuntimeFailureKind.stackOverflow] as its own kind.
  static const deepRecursion = 'contract/deep-recursion';

  /// Id of the unit that schedules microtasks without end, proving the
  /// [RuntimeFailureKind.microtaskBudget] ceiling applies.
  static const microtaskChain = 'contract/microtask-chain';

  /// Id of the unit that calls the [ContractBridge] echo method and returns
  /// the argument it receives, exercising the full bridge round trip.
  static const bridgeEcho = 'contract/bridge-echo';
}

/// The capability/method pair the bridge contract test uses.
abstract final class ContractBridge {
  /// Capability namespace the bridge round trip must target.
  static const capability = 'contract.cap';

  /// Method invoked on [capability]; the recording dispatcher resolves it.
  static const method = 'echo';

  /// Payload carried by the call; the contract bridge echoes the first
  /// element back to the script.
  static const arguments = <JsValue>['hello'];
}

/// Well-known script ids for the bridge security contract suite (ADR 0055).
abstract final class ContractSecurityScriptIds {
  /// Id of the unit that issues one bridge call with oversized arguments.
  static const oversizeArgs = 'contract/security-oversize-args';

  /// Id of the unit that issues one bridge call with deeply nested arguments.
  static const deepArgs = 'contract/security-deep-args';

  /// Id of the unit that issues one bridge call whose dispatcher answer is
  /// oversized.
  static const oversizeResult = 'contract/security-oversize-result';

  /// Id of the unit that issues one more concurrent call than the in-flight
  /// cap allows.
  static const inflightCap = 'contract/security-inflight-cap';

  /// Id of the unit that issues one call left pending across dispose.
  static const disposeInflight = 'contract/security-dispose-inflight';
}

/// Deliberately small limits the security suite configures so tests exercise
/// the rejection paths instead of allocating megabytes.
const contractSecurityLimits = BridgeLimits(
  maxMessageBytes: 1024,
  maxDepth: 4,
  maxInflightCalls: 2,
);

const _securityBudget = ExecutionBudget(timeout: Duration(seconds: 3));

/// Dispatcher for the security suite: records every call and answers through
/// a test-provided handler.
final class ContractSecurityBridge implements BridgeDispatcher {
  /// Creates a dispatcher; [_answer] resolves each recorded call.
  ContractSecurityBridge(Future<JsValue> Function(BridgeCall call) answer)
      : _answer = answer;

  final Future<JsValue> Function(BridgeCall call) _answer;

  /// Every call that reached this dispatcher, in arrival order.
  final List<BridgeCall> calls = <BridgeCall>[];

  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    calls.add(call);
    return _answer(call);
  }
}

/// Registers the backend-neutral bridge security contract tests (ADR 0055).
///
/// Every backend that implements real JS/Dart marshalling must pass this
/// suite unchanged: it pins the [BridgeLimits] enforcement points — oversized
/// or deeply nested calls never reach the dispatcher, oversized dispatcher
/// answers never reach the script, concurrent in-flight dispatches are
/// capped, and dispatches that settle after disposal are dropped safely.
/// The suite does not pin the script-visible failure shape for the
/// result/deep-args paths because that depends on how a backend surfaces
/// rejected marshalled promises; it pins "never dispatched" and "session
/// stays usable" instead.
void registerJsSessionBridgeSecurityTests({
  required String backendName,
  required Future<JsSession> Function(
          BridgeDispatcher bridge, BridgeLimits limits)
      openSession,
  String sourceFor(String id)?,
}) {
  String sourceOf(String id) => sourceFor?.call(id) ?? id;

  group('JsSession bridge security [$backendName]', () {
    test('rejects oversized arguments without dispatching', () async {
      final bridge = ContractSecurityBridge((_) async => null);
      final session = await openSession(bridge, contractSecurityLimits);
      addTearDown(session.dispose);

      final result = await session.execute(
        ScriptUnit(
          id: ContractSecurityScriptIds.oversizeArgs,
          source: sourceOf(ContractSecurityScriptIds.oversizeArgs),
        ),
        _securityBudget,
      );

      expect(bridge.calls, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.bridgeLimit);
    });

    test('rejects deeply nested arguments without dispatching', () async {
      final bridge = ContractSecurityBridge((_) async => null);
      final session = await openSession(bridge, contractSecurityLimits);
      addTearDown(session.dispose);

      await session.execute(
        ScriptUnit(
          id: ContractSecurityScriptIds.deepArgs,
          source: sourceOf(ContractSecurityScriptIds.deepArgs),
        ),
        _securityBudget,
      );

      expect(bridge.calls, isEmpty);
      // The rejection must not wedge the session for later work.
      final followUp = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.returnsValue,
          source: sourceOf(ContractScriptIds.returnsValue),
        ),
        _securityBudget,
      );
      expect(followUp.isSuccess, isTrue);
      expect(followUp.value, 42);
    });

    test('rejects oversized dispatcher answers back to the script', () async {
      final bridge = ContractSecurityBridge((_) async => 'y' * 4096);
      final session = await openSession(bridge, contractSecurityLimits);
      addTearDown(session.dispose);

      await session.execute(
        ScriptUnit(
          id: ContractSecurityScriptIds.oversizeResult,
          source: sourceOf(ContractSecurityScriptIds.oversizeResult),
        ),
        _securityBudget,
      );

      expect(bridge.calls, hasLength(1));
      final followUp = await session.execute(
        ScriptUnit(
          id: ContractScriptIds.returnsValue,
          source: sourceOf(ContractScriptIds.returnsValue),
        ),
        _securityBudget,
      );
      expect(followUp.isSuccess, isTrue);
      expect(followUp.value, 42);
    });

    test('caps concurrent in-flight dispatches', () async {
      final held = <Completer<JsValue>>[];
      final bridge = ContractSecurityBridge((_) {
        final completer = Completer<JsValue>();
        held.add(completer);
        return completer.future;
      });
      final session = await openSession(bridge, contractSecurityLimits);
      addTearDown(session.dispose);

      final result = await session.execute(
        ScriptUnit(
          id: ContractSecurityScriptIds.inflightCap,
          source: sourceOf(ContractSecurityScriptIds.inflightCap),
        ),
        _securityBudget,
      );
      // cap = 2; the script issued 3 calls, the third must be rejected
      // before reaching the dispatcher.
      expect(bridge.calls, hasLength(2));
      expect(held, hasLength(2));

      for (final completer in held) {
        completer.complete(null);
      }
      await session.settle();
      expect(result.isSuccess || result.failure != null, isTrue);
    });

    test('drops in-flight dispatches that settle after disposal', () async {
      final held = <Completer<JsValue>>[];
      final bridge = ContractSecurityBridge((_) {
        final completer = Completer<JsValue>();
        held.add(completer);
        return completer.future;
      });
      final session = await openSession(bridge, contractSecurityLimits);

      await session.execute(
        ScriptUnit(
          id: ContractSecurityScriptIds.disposeInflight,
          source: sourceOf(ContractSecurityScriptIds.disposeInflight),
        ),
        _securityBudget,
      );
      expect(bridge.calls, hasLength(1));

      await session.dispose();
      held.single.complete('late-resolution');
      await Future<void>.delayed(Duration.zero);
      // Reaching this point is the assertion: the late resolution was
      // dropped without touching the disposed engine or throwing.
    });
  });
}

final class _RecordingBridge implements BridgeDispatcher {
  /// Every [BridgeCall] the session dispatched, in arrival order, for the
  /// contract assertions.
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

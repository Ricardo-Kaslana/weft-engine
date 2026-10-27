import 'dart:async';

import 'package:test/test.dart';
import 'package:weft_quickjs/weft_quickjs.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

final class _RecordingBridge implements BridgeDispatcher {
  final List<BridgeCall> calls = <BridgeCall>[];

  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    calls.add(call);
    if (call.capability == 'test.cap' && call.method == 'echo') {
      return call.arguments.isEmpty ? null : call.arguments.first;
    }
    throw StateError('unexpected call ${call.capability}.${call.method}');
  }
}

const _budget = ExecutionBudget(
  timeout: Duration(seconds: 5),
  maxMicrotasks: 1024,
);

void main() {
  final nativeReady = QuickJsNativeLibrary.isLoadable;

  group('QuickJS FFI session', () {
    late _RecordingBridge bridge;
    late JsSession session;

    setUp(() async {
      bridge = _RecordingBridge();
      final backend = QuickJsFfiBackend();
      session = await backend.open(
        RuntimeConfig(
          documentId: 'doc-test',
          memoryLimitBytes: 8 * 1024 * 1024,
          stackLimitBytes: 256 * 1024,
          enabledCapabilities: const {'test.cap'},
        ),
        bridge,
      );
      addTearDown(session.dispose);
    });

    test('evaluates JSON-compatible results', () async {
      final result = await session.execute(
        const ScriptUnit(
          id: 'values',
          source: '({ a: 1, b: "x", c: [true, null] })',
        ),
        _budget,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, <Object?, Object?>{
        'a': 1,
        'b': 'x',
        'c': <Object?>[true, null],
      });
    });

    test('collapses undefined and non-JSON results to null', () async {
      final undefined = await session.execute(
        const ScriptUnit(id: 'undef', source: 'undefined'),
        _budget,
      );
      final function = await session.execute(
        const ScriptUnit(id: 'fn', source: 'function f() { return 1; } f'),
        _budget,
      );

      expect(undefined.isSuccess, isTrue);
      expect(undefined.value, isNull);
      expect(function.isSuccess, isTrue);
      expect(function.value, isNull);
    });

    test('surfaces script errors as scriptError failures', () async {
      final result = await session.execute(
        const ScriptUnit(id: 'throw', source: 'throw new Error("boom");'),
        _budget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.scriptError);
      expect(result.failure?.message, contains('boom'));
      expect(result.failure?.scriptId, 'throw');
    });

    test('interrupts infinite loops at the wall-clock budget', () async {
      final watch = Stopwatch()..start();
      final result = await session.execute(
        const ScriptUnit(id: 'spin', source: 'while (true) {}'),
        const ExecutionBudget(timeout: Duration(milliseconds: 120)),
      );
      watch.stop();

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.timeout);
      expect(watch.elapsed.inMilliseconds, greaterThanOrEqualTo(100));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('interrupts memory bombs at the configured heap limit', () async {
      final result = await session.execute(
        const ScriptUnit(
          id: 'bomb',
          source:
              'var a = []; while (true) { a.push(new Array(10000).fill(1.1)); }',
        ),
        _budget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.memoryLimit);
    });

    test('reports stack overflow as its own failure kind', () async {
      final result = await session.execute(
        const ScriptUnit(
            id: 'recurse', source: 'function f() { return f(); } f();'),
        _budget,
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.stackOverflow);
    });

    test('stops runaway microtask chains at the microtask budget', () async {
      final result = await session.execute(
        const ScriptUnit(
          id: 'microtask-bomb',
          source: 'var p = Promise.resolve();'
              'for (var i = 0; i < 5000; i++) { p = p.then(function () {}); }',
        ),
        const ExecutionBudget(
          timeout: Duration(seconds: 5),
          maxMicrotasks: 64,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.microtaskBudget);
    });

    test('routes capability calls through the bridge and back', () async {
      await session.execute(
        const ScriptUnit(
          id: 'bridge-call',
          source: '__weftBridge("test.cap", "echo", \'["hello"]\')'
              '.then(function (value) { globalThis.__got = value; });',
        ),
        _budget,
      );
      await session.settle();

      expect(bridge.calls, hasLength(1));
      expect(bridge.calls.single.sessionId, session.id);
      expect(bridge.calls.single.capability, 'test.cap');
      expect(bridge.calls.single.method, 'echo');
      expect(bridge.calls.single.sequence, greaterThanOrEqualTo(1));

      final probe = await session.execute(
        const ScriptUnit(id: 'probe', source: 'globalThis.__got'),
        _budget,
      );
      expect(probe.value, 'hello');
    });

    test('resolves bridge results asynchronously within settle', () async {
      await session.execute(
        const ScriptUnit(
          id: 'async-bridge',
          source: 'var p = __weftBridge("test.cap", "echo", \'[7]\');'
              'globalThis.__done = false;'
              'p.then(function (v) { globalThis.__done = (v === 7); });',
        ),
        _budget,
      );
      await session.settle();

      final probe = await session.execute(
        const ScriptUnit(id: 'probe', source: 'globalThis.__done'),
        _budget,
      );
      expect(probe.value, isTrue);
    });

    test('fails settle when capability calls chain unboundedly', () async {
      await session.execute(
        const ScriptUnit(
          id: 'chain-forever',
          source: 'function loop() {'
              '__weftBridge("test.cap", "echo", "[1]").then(loop); } loop();',
        ),
        _budget,
      );

      await expectLater(session.settle(), throwsA(isA<JsSessionFailure>()));
    });

    test('delivers host events to the JS handler', () async {
      await session.execute(
        const ScriptUnit(
          id: 'install-handler',
          source: 'globalThis.__weftOnEvent = function (event) '
              '{ globalThis.__last = event; };',
        ),
        _budget,
      );
      await session.send(
        EventEnvelope(name: 'ping', sequence: 1, payload: const {'k': 'v'}),
      );

      final probe = await session.execute(
        const ScriptUnit(id: 'probe', source: 'globalThis.__last'),
        _budget,
      );
      expect(probe.value, <Object?, Object?>{
        'name': 'ping',
        'sequence': 1,
        'payload': <Object?, Object?>{'k': 'v'},
      });
    });

    test('rejects execution and events after disposal', () async {
      await session.dispose();

      final result = await session.execute(
        const ScriptUnit(id: 'late', source: '1 + 1'),
        _budget,
      );
      expect(result.isSuccess, isFalse);
      expect(result.failure?.kind, RuntimeFailureKind.disposed);
      await expectLater(
        session.send(EventEnvelope(name: 'ping', sequence: 1)),
        throwsA(isA<JsSessionFailure>()),
      );
    });
  },
      skip: nativeReady
          ? null
          : 'QuickJS native library is not built; run '
              'packages/weft_quickjs/tool/build_native.sh');
}

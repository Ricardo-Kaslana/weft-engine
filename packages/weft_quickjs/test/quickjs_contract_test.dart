import 'package:test/test.dart';
import 'package:weft_quickjs/weft_quickjs.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';
import 'package:weft_runtime_contract/weft_runtime_contract.dart';

void main() {
  final nativeReady = QuickJsNativeLibrary.isLoadable;

  group('QuickJS contract scripts', () {
    final backend = QuickJsFfiBackend();

    registerJsSessionContractTests(
      backendName: 'QuickJS FFI',
      openSession: (bridge) => backend.open(
        RuntimeConfig(
          documentId: 'contract',
          memoryLimitBytes: 8 * 1024 * 1024,
          stackLimitBytes: 256 * 1024,
        ),
        bridge,
      ),
      sourceFor: (id) => switch (id) {
        ContractScriptIds.returnsValue => '42',
        ContractScriptIds.throwsScriptError => 'throw new Error("boom");',
        ContractScriptIds.infiniteLoop => 'while (true) {}',
        ContractScriptIds.memoryBomb =>
          'var a = []; while (true) { a.push(new Array(10000).fill(1.1)); }',
        ContractScriptIds.deepRecursion => 'function f() { return f(); } f();',
        ContractScriptIds.microtaskChain => 'var p = Promise.resolve();'
            'for (var i = 0; i < 5000; i++) { p = p.then(function () {}); }',
        ContractScriptIds.bridgeEcho =>
          '__weftBridge("contract.cap", "echo", \'["hello"]\')'
              '.then(function (value) { globalThis.__echoed = value; });',
        _ => '',
      },
    );

    registerJsSessionBridgeSecurityTests(
      backendName: 'QuickJS FFI',
      openSession: (bridge, limits) => backend.open(
        RuntimeConfig(
          documentId: 'contract-security',
          memoryLimitBytes: 8 * 1024 * 1024,
          stackLimitBytes: 256 * 1024,
          bridgeLimits: limits,
        ),
        bridge,
      ),
      sourceFor: (id) => switch (id) {
        ContractSecurityScriptIds.oversizeArgs =>
          '__weftBridge("contract.cap", "echo", '
              'JSON.stringify(["x".repeat(4096)]));',
        ContractSecurityScriptIds.deepArgs =>
          '__weftBridge("contract.cap", "echo", '
              'JSON.stringify([[[[["deep"]]]]]))'
              '.catch(function () {});',
        ContractSecurityScriptIds.oversizeResult =>
          '__weftBridge("contract.cap", "echo", \'["hello"]\')'
              '.catch(function () {});',
        ContractSecurityScriptIds.inflightCap =>
          '__weftBridge("contract.cap", "echo", \'["a"]\');'
              '__weftBridge("contract.cap", "echo", \'["b"]\');'
              '__weftBridge("contract.cap", "echo", \'["c"]\');',
        ContractSecurityScriptIds.disposeInflight =>
          '__weftBridge("contract.cap", "echo", \'["late"]\');',
        ContractScriptIds.returnsValue => '42',
        _ => '',
      },
    );
  },
      skip: nativeReady
          ? null
          : 'QuickJS native library is not built; run '
              'packages/weft_quickjs/tool/build_native.sh');
}

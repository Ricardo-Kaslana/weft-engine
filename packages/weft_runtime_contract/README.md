# weft_runtime_contract

Reusable contract test suite for [Weft](https://github.com/Ricardo-Kaslana/weft-engine) `JsRuntimeBackend`
implementations.

Any backend — QuickJS, a fake, or a future Wasm runtime — should satisfy the
same observable behavior: value results, script errors, wall-clock interrupts,
heap limits, stack overflow, microtask budgets, event delivery and disposal.
This package encodes that suite once so every backend is judged the same way.

## Usage

In the backend's own test file:

```dart
import 'package:test/test.dart';
import 'package:weft_runtime_contract/runtime_contract.dart';

void main() {
  registerJsSessionContractTests(
    backendName: 'my-runtime',
    openSession: (bridge) => MyBackend().open(config, bridge),
    sourceFor: (id) => switch (id) {
      ContractScriptIds.returnsValue => '42',
      ContractScriptIds.infiniteLoop => 'while (true) {}',
      _ => null,
    },
  );
}
```

`ContractScriptIds` lists the well-known unit ids the suite executes, so a
backend only has to supply sources for the ones it can express.

## Boundaries

- This package is test support, but it is a library: `test` is a regular
  dependency, so it is published as a normal package.
- The suite asserts observable behavior only; it does not prescribe an
  execution model, threading or memory layout.

## License

MIT.

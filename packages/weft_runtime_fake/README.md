# weft_runtime_fake

Scripted fake `JsRuntimeBackend` for [Weft](https://github.com/Ricardo-Kaslana/weft-engine) contract tests and
examples.

It behaves like a runtime without executing JavaScript: each script id maps to a
Dart behavior that can return a value, call the capability bridge, allocate fake
heap or produce a failure with the same shape real backends use.

## Usage

```dart
import 'package:weft_runtime_fake/weft_runtime_fake.dart';

final backend = FakeRuntimeBackend(
  behaviors: {
    'contract/returns-value': (context) => const JsResult.success(42),
    'contract/infinite-loop': (context) =>
        JsResult.error(RuntimeFailure.timeout('interrupted')),
  },
);
```

`FakeScriptContext` exposes the execution budget, the capability bridge and a
fake heap, so a test can assert that a script respects limits without paying for
a native engine.

## Where it is used

- The `weft` package's widget tests (interaction flows without native code).
- `example/weft_lab`, so the sample runs on any desktop target.
- Contract tests for the gateway, which need deterministic capability traffic.

## License

MIT.

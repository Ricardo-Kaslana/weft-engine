# weft_runtime_api

Runtime-neutral contracts for [Weft](https://github.com/Ricardo-Kaslana/weft-engine) JavaScript execution: script
units, execution budgets, failure kinds, the session/backend interfaces and the
capability bridge.

Backends such as `weft_quickjs` implement these types, so the engine and the
capability gateway never depend on a specific JS engine.

## Usage

Implement a bridge to answer capability calls:

```dart
import 'package:weft_runtime_api/weft_runtime_api.dart';

final class HostBridge implements BridgeDispatcher {
  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    if (call.capability == 'state' && call.method == 'get') {
      return <String, Object?>{'theme': 'dark'};
    }
    throw StateError('capability ${call.capability} is not enabled');
  }
}
```

Then open a session through any backend and run a unit under a budget:

```dart
final session = await backend.open(
  RuntimeConfig(
    documentId: 'article',
    memoryLimitBytes: 16 * 1024 * 1024,
    stackLimitBytes: 512 * 1024,
    enabledCapabilities: const {'state'},
  ),
  bridge,
);

final result = await session.execute(
  const ScriptUnit(id: 'first', source: '1 + 1'),
  const ExecutionBudget(timeout: Duration(seconds: 1)),
);
```

## Design notes

- Budgets are per execution, and failures are classified (`timeout`,
  `memoryLimit`, `stackOverflow`, `microtaskBudget`, `scriptError`, `disposed`)
  so hosts can react uniformly.
- Bridge values are limited to JSON-compatible data plus bounded binaries; no
  host objects or render nodes cross the boundary.
- The package has no Flutter dependency.

## License

MIT.

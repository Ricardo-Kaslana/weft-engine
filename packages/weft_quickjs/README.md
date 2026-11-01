# weft_quickjs

QuickJS backend for [Weft](https://github.com/Ricardo-Kaslana/weft-engine), driven through `dart:ffi`.

The vendored QuickJS engine (2024-01-13) is compiled into the host app by the
Flutter plugin: CMake on Android, a CocoaPods static framework on iOS, and
`tool/build_native.sh` on desktop. The C shim exposes a flat ABI where only
pointers and integers cross the boundary and JSON is the only marshalling
format.

## Usage

```dart
import 'package:weft_quickjs/weft_quickjs.dart';

final backend = QuickJsFfiBackend();
final session = await backend.open(config, bridge);
try {
  final result = await session.execute(
    const ScriptUnit(id: 'sum', source: '1 + 2 * 3'),
    const ExecutionBudget(timeout: Duration(seconds: 1)),
  );
  print(result.value); // 7
} finally {
  await session.dispose();
}
```

`QuickJsNativeLibrary.isLoadable` reports whether the native entry points
resolve on the current platform, and `QuickJsNativeLibrary.load()` throws a
`StateError` that names the fix when they do not.

## Enforcement

- Wall-clock timeouts and microtask budgets are enforced natively by the
  interrupt handler, so an infinite loop cannot hang the isolate.
- Heap and stack limits are set on the `JSRuntime`; exceeding them maps to
  `RuntimeFailureKind.memoryLimit` / `RuntimeFailureKind.stackOverflow`.
- A failed session is disposed, never reused; recovery opens a fresh runtime and
  replays host state without repeating side effects.

## Platform support

Android (arm64), iOS (device and simulator), and desktop for development.
Flutter Web is not supported by this backend.

## License

MIT for this package; the vendored QuickJS engine is MIT.

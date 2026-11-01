# weft_document

Immutable document model, support reporting, and logical text contracts for
[Weft](https://github.com/Ricardo-Kaslana/weft-engine), a controlled HTML/CSS
rendering engine for Flutter.

This package is the normalization layer. It turns a defined HTML/CSS subset into
an immutable snapshot that the layout engine, the selection model and the JS
runtime all read from. It has no Flutter dependency, so the same code can run on
a server to pre-normalize content.

## Usage

```dart
import 'package:weft_document/weft_document.dart';

final snapshot = const WeftNormalizer().normalize(
  '<h1>Hello</h1><p>Controlled <strong>content</strong>.</p>',
  id: 'article',
);

print(snapshot.revision);                 // content revision for cache keys
print(snapshot.normalizedHtml);           // what the engine will render
print(snapshot.supportReport.requiresWebView); // false for this input
```

Content outside the supported subset is reported instead of silently dropped:

```dart
final canvas = const WeftNormalizer().normalize(
  '<p>before</p><canvas></canvas>',
  id: 'fallback',
);

if (canvas.supportReport.requiresWebView) {
  // route the raw markup to a WebView or a dedicated widget
}
```

Snapshots can cross an isolate or a server boundary:

```dart
final json = WeftDocumentJson.encodeToString(snapshot);
final restored = WeftDocumentJson.decodeFromString(json);
```

## Boundaries

- Normalization makes rendering predictable; it is **not** an XSS sanitizer.
  Untrusted scripts are never executed by Weft.
- The supported subset is documented in
  [docs/supported-subset.md](https://github.com/Ricardo-Kaslana/weft-engine/blob/main/docs/supported-subset.md).
- The snapshot JSON format carries a format + version gate; see
  [docs/release-runbook.md](https://github.com/Ricardo-Kaslana/weft-engine/blob/main/docs/release-runbook.md).

## Related packages

| Package | Role |
|---|---|
| `weft` | Public Flutter API (`WeftView`, `WeftController`) |
| `weft_engine` | Layout, painting, selection, semantics |
| `weft_runtime_api` | JS runtime and capability contracts |
| `weft_quickjs` | QuickJS backend over `dart:ffi` |

## License

MIT. Bundled test fonts (Roboto, Roboto Mono) are Apache-2.0; the vendored
QuickJS engine is MIT.

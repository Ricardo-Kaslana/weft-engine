# weft

Public Flutter API for [Weft](https://github.com/Ricardo-Kaslana/weft-engine), a controlled HTML/CSS rendering engine.
It renders content-type pages — CMS articles, product descriptions, help
documents, streaming AI output — without the cost of a WebView, and executes
only your own scripts through a sandboxed runtime.

## Usage

```dart
import 'package:weft/weft.dart';

final controller = WeftController()
  ..loadDocument(
    const WeftNormalizer().normalize('<h1>Hello</h1><p>Controlled.</p>', id: 'a'),
  );

Widget build(BuildContext context) => WeftView(
      controller: controller,
      onLinkTap: (link) => openInApp(link.href),
    );
```

Content outside the supported subset must be routed explicitly. `WeftView`
calls `fallbackBuilder` with the `SupportReport`, and throws if the content
needs a fallback and no builder is supplied:

```dart
WeftView(
  controller: controller,
  fallbackBuilder: (context, report) => WebView(initialHtml: originalHtml),
);
```

## What it is not

Not a browser. There is no full DOM, no pseudo-classes, no `position: fixed`, no
media queries, no Canvas/WebGL and no rich-text editing. Unsupported content is
reported through `SupportReport` instead of being silently rendered wrong.

## Related packages

`weft_document` (normalization), `weft_engine` (layout/paint/selection),
`weft_runtime_api` (JS contracts), `weft_quickjs` (QuickJS backend),
`weft_capabilities` (state/events/network capabilities).

## License

MIT. Bundled test fonts are Apache-2.0; the vendored QuickJS engine is MIT.

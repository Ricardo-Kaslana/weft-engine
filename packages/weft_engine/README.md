# weft_engine

Layout, painting, selection and semantics for [Weft](https://github.com/Ricardo-Kaslana/weft-engine). This is the
renderer core: it turns a normalized document into text lines, boxes and paint
commands, and exposes hit testing and selection.

Most applications use the `weft` package; depend on this one directly only when
you need the layout result or the surface without the public view.

## Usage

```dart
import 'package:weft_engine/weft_engine.dart';

final layout = const WeftLayoutEngine().layout(snapshot, width: 360);
try {
  final link = layout.linkAt(const Offset(12, 40));
  print(layout.size.height);
} finally {
  layout.dispose(); // owns its TextPainters
}
```

For interactive rendering, mount the surface inside a width-constrained parent:

```dart
SizedBox(
  height: 600,
  child: WeftSurface(document: snapshot, onLinkTap: (link) => open(link.href)),
)
```

Custom tags are trusted Dart extensions: register a `WeftTagRenderer` per tag
on `WeftLayoutEngine` and keep it aligned with `WeftNormalizer.customTags`.

## Boundaries

- The engine never fetches resources itself: images arrive through
  `WeftImageResolver`, and the host owns caching and eviction.
- Layout is viewport-aware (`WeftView.enableLazyLayout`); the raw
  `WeftLayoutEngine.layout` call measures the whole document.
- Fonts, glyph rasterization and pixel appearance are platform-dependent by
  design; the project pins them only in its own golden tests.

## License

MIT. Bundled test fonts are Apache-2.0; the vendored QuickJS engine is MIT.

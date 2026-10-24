# Conformance fonts

The pixel baseline uses fonts copied from the locally installed Flutter SDK artifact cache:

- Roboto Regular, Bold, Italic, Bold Italic.
- Roboto Mono Regular, Bold.

Both families are distributed by Google under the Apache License 2.0; the license text is in `LICENSE-Roboto.txt`.

These files are test fixtures only. They are not bundled into the public Weft packages. The font family aliases used by the browser and Flutter capture are `WeftRoboto` and `WeftRobotoMono`.

CJK pixel baselines are intentionally not enabled yet because the repository does not currently distribute a CJK font with deterministic glyph coverage. CJK cases remain covered by structural layout tests.

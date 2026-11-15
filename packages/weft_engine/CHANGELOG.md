# Changelog

Per-package history for `weft_engine`. The full project history, including the
reasoning behind each change, lives in the repository
[CHANGELOG](https://github.com/Ricardo-Kaslana/weft-engine/blob/main/CHANGELOG.md).

## 0.7.0-dev.4

- Font fallback (ADR 0053): `font-family` parses as the ordered candidate list CSS defines — the first named family is primary, the rest become fallbacks, and generic keywords only map when they lead the list (fixing `Georgia, serif` to keep Georgia). `WeftComputedStyle.toTextStyle()` emits `fontFamilyFallback`, and `WeftLayoutEngine.layout()`/`layoutViewport()` plus `WeftSurface` accept a host-level fallback list appended after author-declared families; a changed list drops `previous` and runs a cold layout. Tests 587 -> 596; the three pixel goldens are unchanged.

## 0.7.0-dev.3

- First published version. The runtime code matches the `0.7.0-dev.2` workspace state; publication metadata (README, LICENSE, repository, version constraints) is what this release adds.

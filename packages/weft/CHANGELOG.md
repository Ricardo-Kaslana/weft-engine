# Changelog

Per-package history for `weft`. The full project history, including the
reasoning behind each change, lives in the repository
[CHANGELOG](https://github.com/Ricardo-Kaslana/weft-engine/blob/main/CHANGELOG.md).

## 0.7.0-dev.4

- Font fallback (ADR 0053): `WeftView.fontFamilyFallback` lets the host declare extra families (typically a CJK face) that the engine appends after the families the author already named; the list is inherited down the tree. Version aligned to the workspace release.

## 0.7.0-dev.3

- First published version. The runtime code matches the `0.7.0-dev.2` workspace state; publication metadata (README, LICENSE, repository, version constraints) is what this release adds.

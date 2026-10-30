# Changelog

## Unreleased

- B1 backend A/B on JNY-AL10 (12 Impeller + 12 Skia ABBA rounds, profile, reconstructed 901-element probe): no reproducible raster advantage for either backend — SCROLL total p95 median 25.70 vs 24.49 ms (p=0.33), PAINT_ONLY stable raster p95 8.77 vs 9.75 ms (p=0.42); the only significant delta is SCROLL build p95 (0.38 ms lower on Skia), which does not affect the frame budget. Do not disable Impeller on this Mali class; strict 60fps remains unmet. Evidence under `build/adr0036-evidence/b1/`.
- Lazy layout now materializes measured windows from a conservative paint-bounds index (ADR 0036): admission, block-flow margins/lists and suffix estimates are cached per snapshot, while only entering/leaving blocks rebuild or release commands. Formatting whitespace between body blocks no longer disables virtualization; body text, NBSP and `white-space: pre` keep the full-layout path.
- Float exclusions are restored from the measured prefix when a block rematerializes, body chrome still follows the current estimated extent, and `correctBy` extent corrections now sync the surface to the real scroll offset instead of replaying corrections.
- Windows host profile (300/1000 paragraphs): warm `layoutViewport` p95 dropped from 1.37/85.35ms to 0.67/0.49ms for compact/newline documents; first viewport for the 1000-paragraph newline document went from 78.67ms (full) to 10.08ms (lazy). These are API timings, not device frame times.
- Verified on Huawei JNY-AL10 (Android 10, profile, 901-element formatted article): 635ms median cold start, 25.5–26.0ms combined scroll p95 with no frame above 50ms, 37.12ms max deep jump, +9.4–10.0MB memory. Strict 60fps (p95 ≤16.7ms) is not met; raster p95 ≈17.2ms dominates.
- 15 new regressions cover formatted-window budgets, negative-margin upward overflow, body chrome, invalidation, ownership transfer, async-anchor cancellation and correction convergence.
- Added `example/weft_live`, a web-target live editorial demo rendered in one Weft surface: auto-refreshed metrics and pulse chart, streaming updates, topic filters, light/dark themes, deep links, poll/clap custom tags, and end-to-end tests that tap tags through the semantics tree.

## 0.6.0-dev.1 (2026-10-28)

- All packages move to `0.6.0-dev.1`, the first version that ships the mobile builds; hosts pinning `0.5.0-dev.1` keep the previous behaviour.

- QuickJS now has build paths for Android and iOS (ADR 0035): `weft_quickjs` declares `ffiPlugin` for both platforms without depending on Flutter, so the package keeps its pure-Dart test path.
- Android: the `android/` module compiles the vendored engine in place through `externalNativeBuild` into `libweft_quickjs.so` — hidden internal symbols, 16 KB page alignment for Play's Android 15+ requirement, `compileSdk 36` / NDK 27 aligned with Flutter 3.35. Verified with a real `flutter build apk`: three ABIs packaged, exactly ten `weft_*` exports.
- iOS: `ios/weft_quickjs.podspec` compiles the shim into the app image and `DynamicLibrary.process()` resolves the entry points; a `+load` anchor class plus `__attribute__((used))` on `WEFT_EXPORT` stop `-dead_strip` from dropping the `dlsym` targets. Not yet built on macOS/Xcode.
- `QuickJsNativeLibrary.load` dispatches by platform (`librarySourceFor` / `describeLoadFailure`): explicit path or `WEFT_QUICKJS_LIBRARY` still wins, iOS resolves from the process, Android opens the packaged library, desktop keeps the file search, and failures name the platform-specific remedy.
- Tests: six new `library_loader_test.dart` cases (weft_quickjs 22 → 28).
- Verified on a real device (Huawei JNY-AL10, Android 10, arm64-v8a): the library loads, JSON and string evaluation work, and both the heap limit and the wall-clock deadline interrupt runaway scripts (`memoryLimit` / `timeout`).

## Unreleased (Stage 5)

- Document snapshot JSON wire format (`WeftDocumentJson`): canonical deterministic encoding, strict decode with format/version gates — a server may normalize once and clients consume the snapshot directly (ADR 0034).
- Normalization consistency vectors: 21 pinned vectors under `conformance/normalization/` (conformance corpus + synthetic cases incl. custom tags, nested-table fallback, CJK, entities); CI re-normalizes every input byte-for-byte, regeneration requires reviewed diffs.
- Seed-based fuzzing: CI suite (400+ iterations x 2 seeds) plus `tool/fuzz.dart` release sweep CLI; hardened two real defects it found — uncapped diagnostic paths bypassing `maxIssues`, and `package:html`'s `ParseError.toString()` crashing on hostile input (diagnostics now degrade to the runtime type).
- Capability policy matrix tests: all 8 subsets of the built-in capabilities — enabled probes pass, disabled namespaces are gateway-rejected with zero network side effects; JS is closed entirely by not opening a `WeftDocumentRuntime`.
- WebView fallback example (`example/weft_fallback`): `decideWeftFallback` render/webview/error-card decision, `WeftFallbackCoordinator` with injectable platform WebView; `webview_flutter` stays an example-only dependency.
- Release runbook (`docs/release-runbook.md`): unified version policy, compatibility anchor table (`WeftDocumentJson.version=1`, `bridgeVersion: 1`, `weft/bootstrap`), release checklist, rollback levels — with an automated rollback rehearsal test (`release_compat_test.dart`).
- API doc coverage gate (`tool/doc_coverage.dart`, wired into `tool/check.sh`): every exported public declaration must carry dartdoc; the public API surface is now fully documented.
- Device matrix plan (`docs/device-matrix.md`) with device tiers, runbook and pass criteria; `weft_lab` gained a performance-overlay toggle for device runs.

## Unreleased (Stage 3 & 4)

- Added stable logical text index with 100k-character cross-paragraph selection, copy, and remapping on streaming updates; selection chrome with drag handles, caret, and copy button (ADR 0013/0015/0019).
- Added chunked painting with visible-window culling, single-surface semantics (headings, tables, lists, links, images, selection actions), and anchor navigation with async frame-budgeted measurement (ADR 0017/0020/0024/0026/0028/0030/0027/0029/0031).
- Added progressive lazy layout for long documents, deep-jump framing, identical-snapshot reuse, and corpus structural gates (lossless, non-overlapping, in-bounds) with hostile-input diagnostics (ADR 0025/0031/0032).
- Added the vendored QuickJS 2024-01-13 engine behind a flat C shim (`native/weft_glue.c`) with native wall-clock, heap, stack, and microtask budget enforcement (ADR 0033).
- Added the per-document JS host `WeftDocumentRuntime` with `weft.state`/`weft.events`/`weft.net` capability modules, policy-gated visibility, redirect whitelist enforcement, network journaling, recovery without replay, and `(sessionId, sequence)` dedup.
- Added `WeftTagRenderer` custom tags: normalizer allowlist, attribute-driven leaf elements, engine-clamped paint ops, hit regions, tap callbacks, and semantics labels.
- Added the backend-neutral `weft_runtime_contract` suite and the scripted `weft_runtime_fake` backend; the QuickJS FFI and fake backends pass the same contract tests.
- Added a stage-4 Weft Lab demo (badge renderer plus FakeRuntime state/events) and the QuickJS native build script with a CI build step.

## Unreleased (Stage 1 & 2)

- Added controlled HTML normalization with tag/attribute filtering, URL checks, node limits, structured support diagnostics, and explicit fallback for complex content.
- Added structured CSS selector parsing, declaration filtering, specificity-aware cascade, inline styles, inheritance, and shorthand expansion for margins and padding.
- Added basic static layout and painting for headings, paragraphs, inline emphasis, links, lists, blockquotes, preformatted code, horizontal rules, and line breaks.
- Added single-surface scrolling integration, text scaling, long-document smoke tests, CJK layout tests, and the Stage 1A Weft Lab article.
- Added per-line link hit regions, hit testing across wrapped links, and the public `WeftView.onLinkTap` callback.
- Added block-level width, min/max width, box-sizing, and solid border support with content-box/border-box layout tests.
- Added six representative conformance fixtures, a structural corpus test, and a diagnostic Chrome/Edge browser screenshot generator.
- Added bundled Roboto/Roboto Mono fixtures, two Flutter pixel baselines, a Windows CI golden job, and a Pillow-based cross-engine difference report.
- Added CSS 2.1 adjacent, parent-child, and collapse-through block margin collapsing, including negative margins and padding/border blockers.
- Matched CSS half-leading with `TextLeadingDistribution.even`; block geometry now aligns with Chromium within 0.5px for the pixel fixtures.
- Added controlled `<img>` normalization with `src/alt/width/height`, protocol filtering, dimension diagnostics, and `alt` fallback.
- Added host-provided image resolution, async decode invalidation, `ImageInfo` lifecycle management, and `WeftImagePaintCommand`.
- Added block image layout with intrinsic ratio, width constraints, borders, and padding.
- Added left/right image floats, per-line text wrapping across paragraphs, `clear`, same-side stacking, opposite-side pairing, and float-aware link regions.
- Table elements currently trigger fallback rather than silent content removal.

## 0.1.0-dev.1

- Initialized the Dart Pub workspace and six-package dependency boundary.
- Added immutable document, support report, logical selection, runtime, and capability contracts.
- Added the Weft Lab bootstrap application and initial unit/widget tests.
- Added architecture, delivery, quality, security, and project-management documentation.

This is a project scaffold. HTML parsing, layout, painting, and native JavaScript execution are not implemented yet.

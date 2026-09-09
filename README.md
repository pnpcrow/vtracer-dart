# vtracer-dart

A Pure Dart / Flutter port of [visioncortex/vtracer](https://github.com/visioncortex/vtracer) —
a raster-to-vector (SVG) conversion framework.

| Upstream (Rust) | This repository (Dart) |
|---|---|
| `crates/vtracer` (core library) | `packages/vtracer` |
| `crates/vtracer-cli` (CLI) | `packages/vtracer_cli` |
| visioncortex primitives + flo_curves curve fitting | `packages/visioncortex` |
| `webapp` (wasm web app) | `apps/vtracer_app` (Flutter, **desktop + web from one codebase**) |

The Node.js WebAssembly package is intentionally **not** ported: its feature
set is identical to the core library, and the Pure Dart core runs on the web
via Flutter Web, giving the web app the same interface as the desktop app.

## Repository layout

```
pubspec.yaml                 # Dart workspace
packages/
  visioncortex/              # Pure Dart port of the visioncortex primitives
                             #   (BinaryImage/ColorImage, connected components,
                             #    hierarchical color clustering, path tracing,
                             #    smoothing/spline fitting, Schneider fit from flo_curves)
  vtracer/                   # Pure Dart port of the vtracer framework
                             #   (frontends, IR, color fitting, compositing,
                             #    mosaic/cutout mode, simplify pass, optimizers, SVG writer,
                             #    pipeline, interactive session)
  vtracer_cli/               # CLI front-end (image decoding via package:image)
apps/
  vtracer_app/               # Flutter app (webapp interface) — Windows/macOS/Linux + Web
```

## The pipeline

Direct port of the upstream pipeline:

```
image ──▶ Frontend ──▶ ColorFitter ──▶ Compositing ──▶ Optimizer ──▶ SvgWriter ──▶ SVG
```

- **Frontends**: hierarchical color clustering (classic VTracer), binary
  (fixed / Bradley–Roth adaptive threshold), and hierarchical watershed with
  volume persistence.
- **Color fitters**: identity, fixed palette (OKLab nearest), area-weighted
  median-cut auto-quantize, merge-adjacent.
- **Compositing**: *stacked* (painter's algorithm) or *cutout* — a seam-free
  mosaic where each shared boundary is fitted once and referenced by both
  adjacent faces.
- **Curve fitting**: pixel lattice, polygon (staircase-removing
  Douglas–Peucker), and spline (corner detection + 4-point subdivision +
  least-squares cubics), plus a paper.js-style `simplify` pass.
- **Optimizers**: coordinate quantization, zero-length/collinear cleanup,
  relative/shorthand SVG encoding with `<g fill>` grouping.

## CLI usage

```bash
dart pub get
dart run packages/vtracer_cli/bin/vtracer.dart --help

# convert
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg --preset poster --simplify 2
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg --clustering watershed
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg --clustering binary --adaptive
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg --hierarchical cutout
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg --palette '#112233,#445566'
dart run packages/vtracer_cli/bin/vtracer.dart input.png output.svg --max-colors 8
```

Compile a standalone executable:

```bash
dart compile exe packages/vtracer_cli/bin/vtracer.dart -o bin/vtracer
./bin/vtracer input.png output.svg
```

## Library usage

```dart
import 'package:vtracer/vtracer.dart';
import 'package:visioncortex/visioncortex.dart';

final img = ColorImage(rgbaBytes, width, height);

// One-shot
final svg = VtracerConfig.defaultConfig().build().toSvg(img);

// Preset + tweak
final cfg = VtracerConfig.fromPreset(Preset.poster)..simplify = 2.0;
final svg2 = cfg.build().toSvg(img);

// Interactive tuning: expensive segmentation is cached across renders;
// only clustering-relevant changes re-segment.
final session = Session(img);
final a = session.renderSvg(VtracerConfig.defaultConfig());
final b = session.renderSvg(VtracerConfig.defaultConfig()..cornerThreshold = 90);

// Cooperative (event-loop yielding) variant for UIs without isolates
// (works on Flutter Web): real progress + cancellation.
final svg3 = await session.renderSvgAsync(cfg,
    onProgress: (p) => print('${p.phase} ${(p.fraction * 100).toInt()}%'));

// Background-isolate worker (package:vtracer/worker.dart): the session and
// its cached segmentation live on a worker isolate, so conversions never
// touch the caller's event loop. Falls back to the cooperative pipeline on
// the web, where isolates don't exist.
final worker = await startVtracerWorker(img);
final svg4 = await worker.renderSvg(cfg, onProgress: (p) => print(p.fraction));
worker.cancel();          // abort the in-flight render
await worker.dispose();
```

## Flutter app (desktop + web, same interface)

A port of the vtracer webapp interface: drag-and-drop / file picker, the
familiar options panel (B/W vs Color, Cutout vs Stacked, Filter Speckle,
Color Precision, Gradient Step, Pixel/Polygon/Spline, Corner Threshold,
Segment Length, Splice Threshold), progress reporting, and SVG export.

Conversion is too heavy to re-run live on every slider drag, so parameter
changes mark the state dirty and are applied explicitly with the **Apply**
button (the canvas shows a hint banner until applied). Opening a file
auto-applies once, preserving the open-and-trace flow.

```bash
cd apps/vtracer_app

flutter run -d windows     # (or macos/linux)
flutter run -d chrome

flutter build windows
flutter build web          # serve build/web with any static server
```

On desktop the conversion runs on a dedicated background isolate (see
`package:vtracer/worker.dart`), leaving the UI isolate free; the cached
segmentation stays on the worker across renders. On the web — where Dart
isolates don't exist — the same worker interface runs the cooperative
pipeline on the UI isolate, yielding between clustering batches so progress
updates render and the UI stays responsive.

The canvas shows a **rasterized preview**, not the live vector picture:
extremely complex traces dragged the rasterizer down (and crashed it at
fullscreen), so the preview is baked once into a bitmap capped at half the
monitor's resolution — resizing the window just re-scales the bitmap. The
button in the canvas corner opens the trace full-detail in a **separate
window** (its own Flutter engine via `desktop_multi_window`, re-rasterizing
to that window's size), so inspecting a heavy trace never touches the main
UI. On the web the button opens the SVG in a new browser tab, rendered
natively by the browser.

A strip below the canvas summarizes the conversion: the input image's
format, resolution, color space and encoded size; the output's dimensions,
shape and layer counts, SVG size and render time; and the preview's current
display scale (recomputed as the window is resized).

### Chromeless window, theming and localization

The desktop app runs **chromeless**: the native title bar is replaced by a
custom in-app bar (`window_manager`) — drag anywhere on it to move the
window, double-click to maximize/restore, and Windows-style
minimize/maximize/close caption buttons on the right. macOS keeps its
native traffic lights over the custom bar; the web build shows the bar
without window controls.

The gear button in the title bar opens the **settings**:

- **Theme** — Light / Dark / **System (default)**. Both modes are complete
  Material 3 themes (indigo seed); the canvas paper becomes a
  theme-tinted transparency checkerboard, and every hardcoded color was
  moved to `ColorScheme`/a `CanvasColors` theme extension. With *System*
  selected the app follows the OS light/dark setting live.
- **Language** — English / 한국어 / **System (default)**, via Flutter `gen-l10n`
  ARB catalogs (`lib/l10n/`). Switching is instant; the system default
  follows the OS locale.
- Choices persist across restarts (`shared_preferences`); the full-detail
  sub-window loads the same preferences, so all windows share one
  theme/language.

Every option in the tuning panel carries a short **helper description**
under its label (what the slider controls, what a mode does) in addition
to the hover tooltips, localized like the rest of the UI.

### Known issue: crash on maximize with a UI Automation client attached

The Flutter Windows engine's accessibility bridge has a bug (access
violation in `AccessibilityBridge::CreateRemoveReparentedNodesUpdate`)
that can crash the process when a UI Automation client — a screen reader,
or inspection/automation tooling — is attached while the window is
maximized. Confirmed via crash-dump analysis (`C000041D`,
`flutter_windows.dll+0x3c18a`). Without a UIA client the bridge never
activates and the app is stable (verified by maximizing via
`WM_SYSCOMMAND` with no client attached). The app already wraps its UI in
`ExcludeSemantics` to remove the other known triggers; screen-reader
support is sacrificed until the engine fix ships.

## Performance

Rough single-thread timings on a desktop CPU (JIT, after warm-up):

| Input | Mode | Time |
|---|---|---|
| 320×240 | default (color-cluster/spline/stacked) | ~30 ms |
| 320×240 | cutout (mosaic) | ~80 ms |
| 320×240 | watershed | ~250 ms |
| 1600×1200 | default | ~3.3 s |
| 1600×1200 | watershed | ~4 s |
| 1600×1200 | binary | ~70 ms |

Noisy photographs are the worst case for color clustering (hundreds of
thousands of provisional clusters); flat art converts in milliseconds.

The stage-2 merge loop keeps its area buckets in a sorted map: every merge
can register a bucket for the grown target's new area, and the previous
sorted-list implementation shifted ~6.5 hundred million elements per
1600×1200 conversion (a hidden quadratic). Re-renders through a `Session`
share the cached masks instead of deep-copying them.

A stage-level benchmark ships with the CLI:

```bash
dart run packages/vtracer_cli/bin/bench.dart [image ...]
```

## Development

```bash
dart pub get
dart analyze    # all packages clean
dart test       # run inside each package, or:
(cd packages/visioncortex && dart test)   # 9 tests
(cd packages/vtracer && dart test)        # 19 tests (pipeline + worker)
(cd apps/vtracer_app && flutter test)     # app end-to-end tests
```

## Differences from upstream

- Value types are plain Dart classes; images use `Uint8List` storage
  (one byte per pixel for binary masks) instead of bit vectors.
- The color-cluster builder's stage 2 iterates per-area buckets instead of
  re-scanning every cluster per bucket (same output, less work), and keeps
  the bucket directory in a sorted map rather than a sorted list.
- Number formatting and float rounding may differ from Rust in the last
  serialized digit in rare cases.
- The webapp's sample-image gallery is replaced by a built-in synthetic
  sample (the original sample images are third-party assets).
- The webapp re-traces live on every slider change; this port applies
  parameter changes explicitly (an **Apply** button), because real-time
  conversion is too heavy for large images.

## License

Upstream vtracer is MIT OR Apache-2.0. This port follows the same
dual-license terms.

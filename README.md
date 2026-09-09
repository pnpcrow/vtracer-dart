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
```

## Flutter app (desktop + web, same interface)

A port of the vtracer webapp interface: drag-and-drop / file picker, the
familiar options panel (B/W vs Color, Cutout vs Stacked, Filter Speckle,
Color Precision, Gradient Step, Pixel/Polygon/Spline, Corner Threshold,
Segment Length, Splice Threshold), live re-conversion with a cached
segmentation, progress reporting, and SVG export.

```bash
cd apps/vtracer_app

flutter run -d windows     # (or macos/linux)
flutter run -d chrome

flutter build windows
flutter build web          # serve build/web with any static server
```

The conversion runs on the UI isolate in cooperative batches (yielding
between clustering batches), so progress updates render and the UI stays
responsive on every platform — including Flutter Web, without isolates.

## Performance

Rough single-thread timings on a desktop CPU (JIT, after warm-up):

| Input | Mode | Time |
|---|---|---|
| 320×240 | default (color-cluster/spline/stacked) | ~35 ms |
| 320×240 | cutout (mosaic) | ~80 ms |
| 320×240 | watershed | ~250 ms |
| 1600×1200 | default | ~7.5 s |
| 1600×1200 | watershed | ~4 s |
| 1600×1200 | binary | ~70 ms |

Noisy photographs are the worst case for color clustering (hundreds of
thousands of provisional clusters); flat art converts in milliseconds.

## Development

```bash
dart pub get
dart analyze    # all packages clean
dart test       # run inside each package, or:
(cd packages/visioncortex && dart test)   # 9 tests
(cd packages/vtracer && dart test)        # 12 tests
(cd apps/vtracer_app && flutter test)     # app end-to-end tests
```

## Differences from upstream

- Value types are plain Dart classes; images use `Uint8List` storage
  (one byte per pixel for binary masks) instead of bit vectors.
- The color-cluster builder's stage 2 iterates per-area buckets instead of
  re-scanning every cluster per bucket (same output, less work).
- Number formatting and float rounding may differ from Rust in the last
  serialized digit in rare cases.
- The webapp's sample-image gallery is replaced by a built-in synthetic
  sample (the original sample images are third-party assets).

## License

Upstream vtracer is MIT OR Apache-2.0. This port follows the same
dual-license terms.

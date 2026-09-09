/// # vtracer (Pure Dart)
///
/// Convert raster images into vector graphics (SVG). A direct Dart port of
/// the Rust vtracer framework: the conversion runs as a pipeline of small,
/// swappable stages, so you can reach for a one-line convenience call or
/// rebuild the pipeline stage by stage.
///
/// ## The pipeline
///
/// ```text
/// image ──▶ Frontend ──▶ ColorFitter ──▶ Compositing ──▶ Optimizer ──▶ SvgWriter ──▶ SVG
/// ```
///
/// ## Quick start
///
/// ```dart
/// import 'package:vtracer/vtracer.dart';
/// import 'package:visioncortex/visioncortex.dart';
///
/// final img = ColorImage(pixels, width, height); // decoded RGBA
/// final svg = VtracerConfig.defaultConfig().build().toSvg(img);
/// ```
///
/// ## Interactive tuning
///
/// Segmentation is the expensive stage. A [Session] caches it and re-renders
/// only the cheap downstream stages when a non-clustering parameter changes.
library vtracer;


export 'package:visioncortex/visioncortex.dart'
    show Color, ColorImage, PointF64, PointI32;

export 'src/colorfit.dart';
export 'src/compose.dart';
export 'src/config.dart';
export 'src/error.dart';
export 'src/fitter.dart';
export 'src/frontend/binary.dart';
export 'src/frontend/color_cluster.dart';
export 'src/frontend/frontend.dart';
export 'src/frontend/keying.dart';
export 'src/frontend/watershed.dart';
export 'src/ir.dart';
export 'src/mosaic/mosaic.dart';
export 'src/optimize.dart';
export 'src/pipeline.dart';
export 'src/progress.dart';
export 'src/session.dart';
export 'src/simplify.dart';
export 'src/svg.dart';

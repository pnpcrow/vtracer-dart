import 'package:visioncortex/visioncortex.dart';

import 'colorfit.dart';
import 'compose.dart';
import 'error.dart';
import 'frontend/frontend.dart';
import 'ir.dart';
import 'optimize.dart';
import 'progress.dart';
import 'simplify.dart';
import 'svg.dart';

/// A fully-assembled vectorization pipeline. Build one with
/// [VtracerConfig.build], or construct it directly for full control.
class Pipeline {
  final Frontend frontend;
  final List<ColorFitter> colorFitters;
  final Compositing compositing;

  /// Geometry passes over fitted contours (e.g. curve simplification), run
  /// inside compositing — after curve fitting, before paths are assembled.
  final List<CurvePass> curvePasses;
  final List<OptimizerPass> optimizers;
  final SvgWriter writer;

  Pipeline({
    required this.frontend,
    required this.colorFitters,
    required this.compositing,
    required this.curvePasses,
    required this.optimizers,
    required this.writer,
  });

  /// Run the pipeline to the output document IR (before serialization).
  VectorDoc run(ColorImage img) {
    return runWithProgress(img, CancelToken(), (_) {});
  }

  /// Run the pipeline, publishing [Progress] updates and honoring the
  /// [CancelToken]. Throws [CancelledError] if the token is tripped.
  VectorDoc runWithProgress(
      ColorImage img, CancelToken cancel, void Function(Progress) onProgress) {
    final ctx = Ctx(cancel, onProgress);
    final seg = frontend.segmentWith(img, ctx);
    return _finishCtx(seg, ctx);
  }

  /// Cooperative variant of [runWithProgress]: yields between work batches so
  /// a UI stays responsive without worker threads (Flutter-web friendly).
  Future<VectorDoc> runWithProgressAsync(
      ColorImage img, CancelToken cancel, void Function(Progress) onProgress) async {
    final ctx = Ctx(cancel, onProgress);
    final seg = await frontend.segmentWithAsync(img, ctx);
    return _finishCtx(seg, ctx);
  }

  /// Run the pipeline and serialize the result to an SVG string.
  Future<String> toSvgAsync(ColorImage img,
      {CancelToken? cancel, void Function(Progress)? onProgress}) async {
    final doc = await runWithProgressAsync(
        img, cancel ?? CancelToken(), onProgress ?? (_) {});
    return writer.write(doc);
  }

  /// Phase 1 of 2 — run only the frontend (the expensive clustering step)
  /// and return a reusable [Segmentation].
  Segmentation segment(ColorImage img) {
    return segmentWithProgress(img, CancelToken(), (_) {});
  }

  /// [segment] with progress reporting and cancellation.
  Segmentation segmentWithProgress(
      ColorImage img, CancelToken cancel, void Function(Progress) onProgress) {
    final ctx = Ctx(cancel, onProgress);
    return frontend.segmentWith(img, ctx);
  }

  /// Phase 2 of 2 — color fitting → compositing → optimization, reusing a
  /// [Segmentation] produced by [segment].
  ///
  /// The segmentation is cloned internally (color fitting mutates it), so the
  /// cached copy stays pristine.
  VectorDoc finish(Segmentation seg) {
    return finishWithProgress(seg, CancelToken(), (_) {});
  }

  /// [finish] with progress reporting and cancellation.
  VectorDoc finishWithProgress(
      Segmentation seg, CancelToken cancel, void Function(Progress) onProgress) {
    final ctx = Ctx(cancel, onProgress);
    return _finishCtx(Segmentation.clone(seg), ctx);
  }

  /// Downstream stages (color fit → compose → optimize) over an owned
  /// segmentation.
  VectorDoc _finishCtx(Segmentation seg, Ctx ctx) {
    for (final fitter in colorFitters) {
      fitter.fit(seg);
      ctx.check();
    }

    final doc = compositing.composeWith(seg, curvePasses, ctx);

    final total = optimizers.length > 1 ? optimizers.length : 1;
    for (var i = 0; i < optimizers.length; i++) {
      ctx.check();
      optimizers[i].run(doc);
      ctx.report(Phase.optimize, (i + 1) / total);
    }
    // Always emit a terminal 100% so a UI can settle even with no passes.
    ctx.report(Phase.optimize, 1.0);

    return doc;
  }

  /// Run the pipeline and serialize the result to an SVG string.
  String toSvg(ColorImage img) => writer.write(run(img));
}


import 'fitter.dart';
import 'ir.dart';
import 'mosaic/mosaic.dart';
import 'progress.dart';
import 'simplify.dart';

/// Which compositing strategy the pipeline uses.
sealed class Compositing {}

/// Independent per-region closed outlines, stacked bottom-to-top.
class StackedCompositing extends Compositing {
  final CurveFitter fitter;
  StackedCompositing(this.fitter);
}

/// Seam-free gapless tessellation via a shared boundary graph.
class MosaicCompositing extends Compositing {
  final SegmentFitter fitter;

  /// Merge flattened neighbours whose colors are within this diff; 0 still
  /// merges identical-color neighbours, negative disables merging entirely.
  final int mergeDiff;

  MosaicCompositing(this.fitter, this.mergeDiff);
}

/// Fit one region's outlines and run the curve passes over each contour.
MultiPath _fitRegion(
    CurveFitter fitter, RegionMask mask, List<CurvePass> passes) {
  final path = MultiPath();
  for (var geom in fitter.fitRegion(mask)) {
    for (final pass in passes) {
      geom = pass.ring(geom);
    }
    path.push(geom.intoClosedSubpath());
  }
  return path;
}

/// Progress-aware stacked composition: reports after each layer.
VectorDoc composeStackedWith(
    Segmentation seg, CurveFitter fitter, List<CurvePass> passes, Ctx ctx) {
  final doc = VectorDoc(seg.width, seg.height);
  final total = seg.layers.length;
  for (var i = 0; i < seg.layers.length; i++) {
    ctx.check();
    final path = _fitRegion(fitter, seg.layers[i].mask, passes);
    if (!path.isEmpty) {
      doc.shapes.add(Shape(seg.layers[i].paint, path));
    }
    ctx.report(Phase.compose, total == 0 ? 1.0 : (i + 1) / total);
  }
  return doc;
}

/// Trace every layer's closed outline and stack the shapes in paint order.
VectorDoc composeStacked(Segmentation seg, CurveFitter fitter, List<CurvePass> passes) {
  final doc = VectorDoc(seg.width, seg.height);
  for (final layer in seg.layers) {
    final path = _fitRegion(fitter, layer.mask, passes);
    if (!path.isEmpty) {
      doc.shapes.add(Shape(layer.paint, path));
    }
  }
  return doc;
}

extension CompositingRun on Compositing {
  /// Run the selected compositor over a segmentation, applying `passes` to
  /// every fitted contour before paths are assembled.
  VectorDoc compose(Segmentation seg, List<CurvePass> passes) {
    switch (this) {
      case StackedCompositing(:final fitter):
        return composeStacked(seg, fitter, passes);
      case MosaicCompositing(:final fitter, :final mergeDiff):
        return composeMosaic(seg, fitter, mergeDiff, passes);
    }
  }

  /// Progress- and cancellation-aware compositing.
  VectorDoc composeWith(Segmentation seg, List<CurvePass> passes, Ctx ctx) {
    switch (this) {
      case StackedCompositing(:final fitter):
        return composeStackedWith(seg, fitter, passes, ctx);
      case MosaicCompositing(:final fitter, :final mergeDiff):
        ctx.check();
        ctx.report(Phase.compose, 0.0);
        final doc = composeMosaic(seg, fitter, mergeDiff, passes);
        ctx.check();
        ctx.report(Phase.compose, 1.0);
        return doc;
    }
  }
}

part of '../colorfit.dart';

/// Union consecutive layers that share a paint into a single layer. Run this
/// after palette snapping (which is what creates runs of identical paints).
class MergeAdjacent implements ColorFitter {
  const MergeAdjacent();

  @override
  void fit(Segmentation seg) {
    if (seg.layers.length < 2) {
      return;
    }
    final merged = <Layer>[];
    var run = <Layer>[];
    for (final layer in seg.layers) {
      if (run.isNotEmpty && run.first.paint != layer.paint) {
        _flush(run, merged);
        run = [];
      }
      run.add(layer);
    }
    _flush(run, merged);
    seg.layers = merged;
  }

  /// Collapse one run of same-paint layers in a single pass.
  static void _flush(List<Layer> run, List<Layer> out) {
    switch (run.length) {
      case 0:
        break;
      case 1:
        out.add(run.removeLast());
      default:
        final paint = run[0].paint;
        final mask = RegionMask.unionAll(run.map((l) => l.mask).toList());
        out.add(Layer(paint, mask));
        run.clear();
    }
  }
}

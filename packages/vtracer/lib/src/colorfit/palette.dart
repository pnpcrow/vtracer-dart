part of '../colorfit.dart';

/// Snap every layer paint to the nearest color in a fixed palette, measured
/// in OKLab. An empty palette leaves paints untouched.
class FixedPalette implements ColorFitter {
  final List<Color> colors;

  const FixedPalette(this.colors);

  @override
  void fit(Segmentation seg) {
    if (colors.isEmpty) {
      return;
    }
    final lab = colors.map(Oklab.fromColor).toList();
    for (final layer in seg.layers) {
      layer.paint = Paint.solid(_nearest(layer.paint.color, lab));
    }
  }

  Color _nearest(Color color, List<Oklab> lab) {
    final target = Oklab.fromColor(color);
    var best = colors[0];
    var bestDist = double.infinity;
    for (var i = 0; i < colors.length; i++) {
      final dist = target.distanceSquared(lab[i]);
      if (dist < bestDist) {
        bestDist = dist;
        best = colors[i];
      }
    }
    return best;
  }
}

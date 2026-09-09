import 'package:visioncortex/visioncortex.dart';

import '../error.dart';
import '../ir.dart';
import 'frontend.dart';

/// Grayscale intensity (0..=255) used by every thresholding method.
int _intensityOf(int r, int g, int b) => (r + g + b) ~/ 3;

int intensity(Color c) => _intensityOf(c.r, c.g, c.b);

/// How the binary frontend separates foreground (dark) from background pixels.
sealed class Threshold {
  const Threshold();
}

/// Global cutoff: a pixel is foreground when its intensity is below this
/// value (0..=255).
class FixedThreshold extends Threshold {
  final int value;
  const FixedThreshold(this.value);
}

/// Bradley–Roth adaptive threshold: a pixel is foreground when its intensity
/// is more than `t` percent below the mean of the surrounding
/// `window`×`window` block. Computed in one pass with a summed-area table.
class AdaptiveThreshold extends Threshold {
  /// Window side length in pixels; 0 auto-derives ~1/8 of the shorter image
  /// dimension.
  final int window;

  /// Sensitivity, as a percentage below the local mean (paper default 15).
  final double t;

  const AdaptiveThreshold(this.window, this.t);

  const AdaptiveThreshold.defaults()
      : window = 0,
        t = 15.0;
}

/// Binary (black/white) frontend: threshold the image then cluster the
/// foreground. Every region is painted black.
class BinaryFrontend extends Frontend {
  /// How foreground pixels are selected.
  final Threshold threshold;

  /// Whether to connect clusters diagonally.
  final bool diagonal;

  /// Discard clusters smaller than this many pixels (0 = keep all).
  final int minArea;

  BinaryFrontend({
    this.threshold = const FixedThreshold(128),
    this.diagonal = false,
    this.minArea = 0,
  });

  BinaryImage _binarize(ColorImage img) {
    switch (threshold) {
      case FixedThreshold(:final value):
        final out = BinaryImage.newWH(img.width, img.height);
        final px = img.pixels;
        for (var i = 0, p = 0; i < out.pixels.length; i++, p += 4) {
          out.pixels[i] = _intensityOf(px[p], px[p + 1], px[p + 2]) < value ? 1 : 0;
        }
        return out;
      case AdaptiveThreshold(:final window, :final t):
        return _adaptiveBradleyRoth(img, window, t);
    }
  }

  @override
  Segmentation segment(ColorImage img) {
    if (img.width == 0 || img.height == 0) {
      throw const EmptyImageError();
    }

    final binary = _binarize(img);
    final clusters = binary.toClusters(diagonal);

    final seg = Segmentation(img.width, img.height);
    const black = Color(0, 0, 0);
    for (var i = 0; i < clusters.length; i++) {
      final cluster = clusters.getCluster(i);
      if (cluster.size < minArea) {
        continue;
      }
      seg.layers.add(Layer(
        Paint.solid(black),
        RegionMask(cluster.toBinaryImage(), PointI32(cluster.rect.left, cluster.rect.top)),
      ));
    }

    return seg;
  }
}

/// Bradley–Roth adaptive thresholding via a summed-area table: a pixel is
/// foreground when `value <= mean * (1 - t/100)`.
BinaryImage _adaptiveBradleyRoth(ColorImage img, int window, double t) {
  final w = img.width;
  final h = img.height;
  final sat = SummedAreaTable.fromColorImage(img);

  final side = window == 0 ? (minOf(w, h) ~/ 8).clamp(1, 1 << 30) : window;
  final half = side ~/ 2;
  final factor = 1.0 - t.clamp(0.0, 100.0) / 100.0;

  final out = BinaryImage.newWH(w, h);
  final px = img.pixels;
  for (var y = 0; y < h; y++) {
    final y0 = (y - half).clamp(0, y);
    final y1 = (y + half) < (h - 1) ? (y + half) : (h - 1);
    for (var x = 0; x < w; x++) {
      final x0 = (x - half).clamp(0, x);
      final x1 = (x + half) < (w - 1) ? (x + half) : (w - 1);

      final count = ((x1 - x0 + 1) * (y1 - y0 + 1)).toDouble();
      final sum = sat.getRegionSumXYWH(x0, y0, x1 - x0 + 1, y1 - y0 + 1).toDouble();
      final p = (y * w + x) * 4;
      final value = _intensityOf(px[p], px[p + 1], px[p + 2]).toDouble();

      out.setPixel(x, y, value * count <= sum * factor);
    }
  }
  return out;
}

int minOf(int a, int b) => a < b ? a : b;

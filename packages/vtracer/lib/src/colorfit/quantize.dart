part of '../colorfit.dart';

/// Reduce the layer palette to at most `maxColors` representative colors via
/// area-weighted median cut, then snap each layer to the nearest
/// representative (in OKLab).
class AutoQuantize implements ColorFitter {
  final int maxColors;

  const AutoQuantize({this.maxColors = 16});

  @override
  void fit(Segmentation seg) {
    if (maxColors == 0 || seg.layers.isEmpty) {
      return;
    }

    final samples = seg.layers
        .map((l) => (l.paint.color, l.mask.area() + 1))
        .toList(growable: false);

    var buckets = <_Bucket>[_Bucket(samples)];
    while (buckets.length < maxColors) {
      // Split the bucket with the widest single-channel range.
      _Bucket? target;
      var targetIdx = -1;
      var bestRange = -1;
      for (var i = 0; i < buckets.length; i++) {
        final b = buckets[i];
        if (b.samples.length <= 1) continue;
        final r = b.channelRange(b.widestChannel());
        if (r > bestRange) {
          bestRange = r;
          target = b;
          targetIdx = i;
        }
      }
      if (target == null) break;
      buckets.removeAt(targetIdx);
      final (a, b) = target.split();
      buckets.add(a);
      buckets.add(b);
    }

    final palette = buckets.map((b) => b.representative()).toList();
    final lab = palette.map(Oklab.fromColor).toList();

    for (final layer in seg.layers) {
      final target = Oklab.fromColor(layer.paint.color);
      var best = palette[0];
      var bestDist = double.infinity;
      for (var i = 0; i < palette.length; i++) {
        final d = target.distanceSquared(lab[i]);
        if (d < bestDist) {
          bestDist = d;
          best = palette[i];
        }
      }
      layer.paint = Paint.solid(best);
    }
  }
}

class _Bucket {
  final List<(Color, int)> samples;

  _Bucket(this.samples);

  int channelRange(int channel) {
    var lo = 255;
    var hi = 0;
    for (final (c, _) in samples) {
      final v = c.rgbU8[channel];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    return (hi - lo).clamp(0, 255);
  }

  int widestChannel() {
    var best = 0;
    var bestRange = 0;
    for (var c = 0; c < 3; c++) {
      final r = channelRange(c);
      if (r > bestRange) {
        bestRange = r;
        best = c;
      }
    }
    return best;
  }

  int totalWeight() {
    var w = 0;
    for (final (_, weight) in samples) {
      w += weight;
    }
    return w;
  }

  Color representative() {
    var r = 0, g = 0, b = 0, w = 0;
    for (final (c, weight) in samples) {
      final rgb = c.rgbU8;
      r += rgb[0] * weight;
      g += rgb[1] * weight;
      b += rgb[2] * weight;
      w += weight;
    }
    if (w == 0) return const Color(0, 0, 0);
    return Color(r ~/ w, g ~/ w, b ~/ w);
  }

  (_Bucket, _Bucket) split() {
    final channel = widestChannel();
    final sorted = List<(Color, int)>.from(samples)
      ..sort((a, b) => a.$1.rgbU8[channel].compareTo(b.$1.rgbU8[channel]));
    final half = totalWeight() ~/ 2;
    var acc = 0;
    var cut = 1;
    for (var i = 0; i < sorted.length; i++) {
      acc += sorted[i].$2;
      if (acc >= half) {
        final maxCut = (sorted.length - 1).clamp(1, sorted.length);
        cut = (i + 1).clamp(1, maxCut);
        break;
      }
    }
    return (
      _Bucket(sorted.sublist(0, cut)),
      _Bucket(sorted.sublist(cut)),
    );
  }
}

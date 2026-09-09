import 'dart:collection';
import 'dart:typed_data';

import 'package:visioncortex/visioncortex.dart';

import '../fitter.dart';
import '../ir.dart';
import '../simplify.dart';

part 'graph.dart';
part 'face.dart';
part 'fit.dart';
part 'compose.dart';

/// A dense region id. [outsideRegion] marks keyed/transparent/out-of-bounds
/// pixels.
typedef RegionId = int;

/// Sentinel label for pixels outside any region.
const int outsideRegion = 0xFFFFFFFF;

/// A flat partition of the canvas: one region id per pixel, plus the paint
/// for each region.
class LabelMap {
  final int width;
  final int height;

  /// One label per pixel in row-major order; [outsideRegion] for uncovered
  /// pixels.
  Uint32List labels;

  /// Paint per region, indexed by label.
  List<Paint> paints;

  LabelMap(this.width, this.height, this.labels, this.paints);

  /// Flatten a layered [Segmentation] top-down into a flat partition: each
  /// pixel takes the paint of the topmost layer covering it.
  static LabelMap fromSegmentation(Segmentation seg) {
    final w = seg.width;
    final h = seg.height;
    final labels = Uint32List(w * h)..fillRange(0, w * h, outsideRegion);
    final paints = seg.layers.map((l) => l.paint).toList();

    for (var i = 0; i < seg.layers.length; i++) {
      final mask = seg.layers[i].mask;
      for (var ly = 0; ly < mask.image.height; ly++) {
        for (var lx = 0; lx < mask.image.width; lx++) {
          if (mask.image.getPixel(lx, ly)) {
            final gx = mask.offset.x + lx;
            final gy = mask.offset.y + ly;
            if (gx >= 0 && gy >= 0 && gx < w && gy < h) {
              labels[gy * w + gx] = i;
            }
          }
        }
      }
    }

    return LabelMap(seg.width, seg.height, labels, paints);
  }

  /// Label at pixel `(x, y)`, or [outsideRegion] for out-of-bounds
  /// coordinates. Treating outside as a real label removes all image-border
  /// special cases.
  int label(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return outsideRegion;
    }
    return labels[y * width + x];
  }

  /// Merge neighbouring regions whose colors are within `maxDiff` of each
  /// other (sum of per-channel absolute differences), with merged colors
  /// re-derived as area-weighted running means.
  ///
  /// `maxDiff == 0` still merges identical-color neighbours; a negative value
  /// disables merging entirely.
  void mergeSimilar(int maxDiff) {
    final n = paints.length;
    if (maxDiff < 0 || n < 2) {
      return;
    }

    // Area and summed color per region, for weighted mean colors.
    final area = List<int>.filled(n, 0);
    for (final l in labels) {
      if (l != outsideRegion) {
        area[l]++;
      }
    }
    final sum = List<Int64List>.generate(
        n,
        (i) {
          final c = paints[i].color;
          return Int64List.fromList([c.r * area[i], c.g * area[i], c.b * area[i]]);
        },
      );

    // Adjacency pairs (right/down scan covers 4-connectivity once).
    final w = width;
    final h = height;
    final pairs = <(int, int)>[];
    final seen = <(int, int)>{};
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = label(x, y);
        if (a == outsideRegion) {
          continue;
        }
        for (final (nx, ny) in [(x + 1, y), (x, y + 1)]) {
          final b = label(nx, ny);
          if (b == outsideRegion || b == a) {
            continue;
          }
          final key = a < b ? (a, b) : (b, a);
          if (seen.add(key)) {
            pairs.add(key);
          }
        }
      }
    }

    int diff(Int64List sa, int aa, Int64List sb, int ab) {
      var d = 0;
      for (var k = 0; k < 3; k++) {
        final ma = sa[k] ~/ (aa > 0 ? aa : 1);
        final mb = sb[k] ~/ (ab > 0 ? ab : 1);
        d += (ma - mb).abs();
      }
      return d;
    }

    // Most-similar pairs first; ties break on ids for determinism.
    final sortedPairs = List<(int, int)>.from(pairs)
      ..sort((p, q) {
        final dp = diff(sum[p.$1], area[p.$1], sum[p.$2], area[p.$2]);
        final dq = diff(sum[q.$1], area[q.$1], sum[q.$2], area[q.$2]);
        if (dp != dq) return dp.compareTo(dq);
        if (p.$1 != q.$1) return p.$1.compareTo(q.$1);
        return p.$2.compareTo(q.$2);
      });

    final parent = Uint32List(n);
    for (var i = 0; i < n; i++) {
      parent[i] = i;
    }

    int find(Uint32List parent, int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    // Colors move as regions absorb one another, so re-sweep the candidate
    // pairs until nothing merges.
    while (true) {
      var changed = false;
      for (final (a, b) in sortedPairs) {
        final ra = find(parent, a);
        final rb = find(parent, b);
        if (ra == rb) {
          continue;
        }
        if (diff(sum[ra], area[ra], sum[rb], area[rb]) <= maxDiff) {
          parent[rb] = ra;
          for (var k = 0; k < 3; k++) {
            sum[ra][k] += sum[rb][k];
          }
          area[ra] += area[rb];
          changed = true;
        }
      }
      if (!changed) {
        break;
      }
    }

    // Compact surviving roots into dense ids and rewrite labels + paints.
    final remap = Uint32List(n)..fillRange(0, n, outsideRegion);
    final newPaints = <Paint>[];
    for (var i = 0; i < labels.length; i++) {
      final l = labels[i];
      if (l == outsideRegion) {
        continue;
      }
      final root = find(parent, l);
      if (remap[root] == outsideRegion) {
        remap[root] = newPaints.length;
        final s = sum[root];
        final a = area[root] > 0 ? area[root] : 1;
        newPaints.add(Paint.solid(Color(s[0] ~/ a, s[1] ~/ a, s[2] ~/ a)));
      }
      labels[i] = remap[root];
    }
    paints = newPaints;
  }
}

import 'dart:collection';
import 'dart:typed_data';

import '../color.dart';
import '../image/color_image.dart';
import 'cluster.dart';
import 'container.dart';

/// Describes what to do with pixels that match the key color.
enum KeyingAction { keep, discard }

class NeighbourInfo {
  final int index;
  final int diff;
  const NeighbourInfo(this.index, this.diff);
}

/// the 0th cluster is reserved for internal use.
const int zeroCluster = 0;
const int hierarchicalMax = 0xFFFFFFFF;

class BuilderConfig {
  bool diagonal;
  int hierarchical;
  int batchSize;
  Color key;
  KeyingAction keyingAction;

  BuilderConfig({
    this.diagonal = true,
    this.hierarchical = hierarchicalMax,
    this.batchSize = 10000,
    Color? key,
    this.keyingAction = KeyingAction.keep,
  }) : key = key ?? Color.zero();
}

/// Builds [ColorClusters] from a [ColorImage] over user-supplied predicates.
///
/// The `same` predicate works on raw channel bytes so the per-pixel stage
/// never allocates [Color] values.
class ColorClustersBuilder {
  final BuilderConfig conf;
  final ColorImage image;
  final bool Function(int ar, int ag, int ab, int br, int bg, int bb) same;
  final int Function(Color, Color) diff;
  final bool Function(ClustersView, ColorCluster, List<NeighbourInfo>) deepen;
  final bool Function(ClustersView, ColorCluster, List<NeighbourInfo>) hollow;

  ColorClustersBuilder({
    required this.image,
    required this.same,
    required this.diff,
    required this.deepen,
    required this.hollow,
    BuilderConfig? config,
  }) : conf = config ?? BuilderConfig();

  ColorClusters run() {
    final impl = _BuilderImpl(this);
    while (!impl.tick()) {}
    return impl.result();
  }

  IncrementalColorClustersBuilder start() =>
      IncrementalColorClustersBuilder(_BuilderImpl(this));
}

class IncrementalColorClustersBuilder {
  _BuilderImpl? _impl;

  IncrementalColorClustersBuilder(_BuilderImpl impl) : _impl = impl;

  bool tick() => _impl!.tick();

  int progress() => _impl?.progress() ?? 0;

  ColorClusters result() {
    final impl = _impl!;
    _impl = null;
    return impl.result();
  }
}

class _Area {
  int area;
  int count;
  List<int> clusterList;
  _Area(this.area, this.count, this.clusterList);
}

class _BuilderImpl {
  final bool diagonal;
  final int hierarchical;
  final int batchSize;
  final Color key;
  final KeyingAction keyingAction;
  final bool Function(int, int, int, int, int, int) same;
  final int Function(Color, Color) diff;
  final bool Function(ClustersView, ColorCluster, List<NeighbourInfo>) deepen;
  final bool Function(ClustersView, ColorCluster, List<NeighbourInfo>) hollow;

  final int width;
  final int height;
  final Uint8List pixels; // RGBA bytes
  List<ColorCluster> clusters;
  Uint32List clusterIndices;

  /// Stage-2 bucket directory: area → the clusters currently at that area,
  /// ordered by area. A sorted map (not a sorted list) keeps the mid-run
  /// bucket inserts at O(log n) — the list-based variant shifted hundreds of
  /// millions of elements on photo-sized inputs because every merge can
  /// insert a bucket for the grown target's new area.
  SplayTreeMap<int, _Area> clusterAreas = SplayTreeMap();

  List<int> clustersOutput = [];
  int stage = 1;
  int iteration = 0;
  int nextIndex = 1;

  _BuilderImpl(ColorClustersBuilder b)
      : diagonal = b.conf.diagonal,
        hierarchical = b.conf.hierarchical,
        batchSize = b.conf.batchSize,
        key = b.conf.key,
        keyingAction = b.conf.keyingAction,
        same = b.same,
        diff = b.diff,
        deepen = b.deepen,
        hollow = b.hollow,
        width = b.image.width,
        height = b.image.height,
        pixels = b.image.pixels,
        clusters = [ColorCluster()],
        clusterIndices = Uint32List(b.image.width * b.image.height);

  bool tick() {
    switch (stage) {
      case 1:
        if (_stage1()) {
          if (hierarchical != 0) {
            stage += 1;
            iteration = 0;
          } else {
            _stage1Output();
            stage += 2;
          }
        }
        return false;
      case 2:
        for (var i = 0; i < (iteration ~/ 16).clamp(1, 1 << 30); i++) {
          if (_stage2()) {
            stage += 1;
            iteration = 0;
            break;
          }
        }
        return false;
      default:
        return true;
    }
  }

  ColorCluster getCluster(int index) => clusters[index];

  ColorClusters result() {
    final output =
        clustersOutput.where((i) => clusters[i].sum.counter > 0).toList();
    return ColorClusters(
      width: width,
      height: height,
      pixels: pixels,
      clusters: clusters,
      clusterIndices: clusterIndices,
      clustersOutput: output,
    );
  }

  ClustersView view() => ClustersView(
        width: width,
        height: height,
        pixels: pixels,
        clusters: clusters,
        clusterIndices: clusterIndices,
        clustersOutput: clustersOutput,
      );

  /// Stage 2 repeatedly needs a view; all fields reference the same mutable
  /// objects, so one shared instance is semantically identical.
  ClustersView? _stage2View;

  ClustersView stage2View() => _stage2View ??= view();

  int progress() {
    switch (stage) {
      case 1:
        return 50 * iteration ~/ clusterIndices.length;
      case 2:
        // `iteration` counts processed buckets; new buckets keep appearing
        // while merges run, so the denominator is the live pending count.
        final total = iteration + clusterAreas.length;
        return total == 0 ? 100 : 50 + 50 * iteration ~/ total;
      default:
        return 100;
    }
  }

  bool _stage1() {
    final hasKey = key != Color.zero();
    final kr = key.r, kg = key.g, kb = key.b, ka = key.a;
    final len = clusterIndices.length;
    final w = width;
    final px = pixels;
    final diag = diagonal;

    final end = (iteration + batchSize) > len ? len : (iteration + batchSize);

    // `same` on raw channels; out-of-range never matches. Declared at batch
    // scope so the pixel loop doesn't allocate a closure per pixel.
    bool sameAt(int a, int b) => a >= 0 && b >= 0 && same(px[a], px[a + 1],
        px[a + 2], px[b], px[b + 1], px[b + 2]);

    for (var i = iteration; i < end; i++) {
      final x = i % w;
      final y = i ~/ w;

      final p = i * 4;
      final cr = px[p], cg = px[p + 1], cb = px[p + 2], ca = px[p + 3];

      // Neighbour pixel byte offsets; -1 marks out-of-range.
      final upIdx = y > 0 ? p - w * 4 : -1;
      final leftIdx = x > 0 ? p - 4 : -1;
      final upLeftIdx = (x > 0 && y > 0) ? p - w * 4 - 4 : -1;

      var clusterUp = y > 0 ? clusterIndices[i - w] : zeroCluster;
      var clusterLeft = x > 0 ? clusterIndices[i - 1] : zeroCluster;
      final clusterUpleft =
          (x > 0 && y > 0) ? clusterIndices[i - w - 1] : zeroCluster;

      if (clusterLeft != clusterUp &&
          sameAt(leftIdx, upIdx) &&
          (diag || (sameAt(p, leftIdx) && sameAt(p, upIdx)))) {
        if (getCluster(clusterLeft).area <= getCluster(clusterUp).area) {
          _combineClusters(clusterLeft, clusterUp);
          if (clusterLeft == nextIndex - 1 && nextIndex == clusters.length) {
            nextIndex--;
          }
          clusterLeft = clusterUp;
        } else {
          _combineClusters(clusterUp, clusterLeft);
          clusterUp = clusterLeft;
        }
      }

      if (hasKey && cr == kr && cg == kg && cb == kb && ca == ka) {
        switch (keyingAction) {
          case KeyingAction.keep:
            clusters[zeroCluster].add(i, cr, cg, cb, x, y);
            break;
          case KeyingAction.discard:
            break;
        }
      } else if (sameAt(p, upIdx) && sameAt(p, upLeftIdx)) {
        clusterIndices[i] = clusterUp;
        clusters[clusterUp].add(i, cr, cg, cb, x, y);
      } else if (sameAt(p, leftIdx) && sameAt(p, upLeftIdx)) {
        clusterIndices[i] = clusterLeft;
        clusters[clusterLeft].add(i, cr, cg, cb, x, y);
      } else if (diag && sameAt(p, upLeftIdx)) {
        clusterIndices[i] = clusterUpleft;
        clusters[clusterUpleft].add(i, cr, cg, cb, x, y);
      } else {
        final newCluster = ColorCluster();
        newCluster.add(i, cr, cg, cb, x, y);
        if (nextIndex < clusters.length) {
          clusters[nextIndex] = newCluster;
        } else {
          clusters.add(newCluster);
        }
        clusterIndices[i] = nextIndex;
        nextIndex++;
      }
    }

    iteration += batchSize;
    if (iteration >= clusterIndices.length) {
      _prepareStage2();
      return true;
    }
    return false;
  }

  void _stage1Output() {
    final output = <(int, int)>[];
    for (var index = 0; index < clusters.length; index++) {
      final area = clusters[index].area;
      if (area > 0) {
        output.add((index, area));
      }
    }
    output.sort((a, b) => (a.$2 * 65535 + a.$1).compareTo(b.$2 * 65535 + b.$1));
    clustersOutput = output.map((c) => c.$1).toList();
  }

  void _prepareStage2() {
    for (final c in clusters) {
      c.residueSum = c.sum.clone();
    }

    // Group by area in a hash map first: inserting only the distinct areas
    // into the ordered map is much cheaper than one ordered insert per
    // cluster (photo-sized inputs carry hundreds of thousands of them).
    final counts = <int, List<int>>{};
    for (var index = 0; index < clusters.length; index++) {
      final area = clusters[index].area;
      if (area > 0) {
        counts.putIfAbsent(area, () => []).add(index);
      }
    }
    for (final e in counts.entries) {
      clusterAreas[e.key] = _Area(e.key, e.value.length, e.value);
    }
  }

  /// The stage-2 work unit: process the smallest unprocessed bucket. Merges
  /// only ever append grown targets to strictly later buckets, so the
  /// current bucket can be removed from the directory once processed and the
  /// next-smallest key picked afresh on the following call.
  bool _stage2() {
    if (clusterAreas.isEmpty) {
      return true;
    }
    final key = clusterAreas.firstKey()!;
    final bucket = clusterAreas[key]!;
    if (bucket.count == 0) {
      clusterAreas.remove(key);
      iteration++;
      return clusterAreas.isEmpty;
    }

    final curArea = key;
    final canDiscardPixels =
        keyingAction == KeyingAction.discard && key != Color.zero();

    // Process this bucket's clusters in index order (merges may have appended
    // grown clusters to the list; sorting restores the scan order the
    // reference implementation uses). Appends triggered by the loop only
    // touch strictly later buckets, so iterating by index is safe.
    final ordered = bucket.clusterList;
    if (!ordered.isEmpty) {
      if (!_isSorted(ordered)) {
        ordered.sort();
      }
      for (var bi = 0; bi < ordered.length; bi++) {
        final index = ordered[bi];
        final mycluster = clusters[index];

        if (mycluster.area != curArea) {
          continue;
        }

        if (curArea > hierarchical) {
          clustersOutput.add(index);
          continue;
        }

        final mycolor = mycluster.color();
        final infos = <NeighbourInfo>[];
        for (final other in mycluster.neighbours(stage2View())) {
          // Merged-away clusters have no sum left to rank.
          if (clusters[other].sum.counter > 0) {
            infos.add(NeighbourInfo(other, diff(mycolor, clusters[other].color())));
          }
        }

        if (infos.isEmpty) {
          // `firstKeyAfter(curArea) == null` ⟺ this is the last bucket right
          // now (later buckets may still appear while merges run).
          if (clusterAreas.lastKey() == curArea || canDiscardPixels) {
            // the final background, or an isolated cluster surrounded by keyed,
            // discarded pixels
            clustersOutput.add(index);
          }
          continue;
        }

        infos.sort((a, b) =>
            (a.diff * 65535 + a.index).compareTo(b.diff * 65535 + b.index));

        final target = infos[0].index;

        final isDeepen = hierarchical == hierarchicalMax
            ? deepen(stage2View(), mycluster, infos)
            : false;
        final isHollow = hollow(stage2View(), mycluster, infos);

        if (isDeepen) {
          clustersOutput.add(index);
        }

        // The target's old bucket may already be past (processed buckets are
        // removed); its count is only read before that point.
        final oldBucket = clusterAreas[clusters[target].area];
        if (oldBucket != null) {
          oldBucket.count -= 1;
        }

        _mergeClusterInto(index, target, isDeepen, isHollow);
        final updatedArea = clusters[target].area;

        // The grown target joins the (strictly later) bucket for its new area.
        final grown =
            clusterAreas.putIfAbsent(updatedArea, () => _Area(updatedArea, 0, []));
        grown.count += 1;
        grown.clusterList.add(target);
      }
      ordered.clear();
    }

    clusterAreas.remove(key);
    iteration++;
    return clusterAreas.isEmpty;
  }

  static bool _isSorted(List<int> list) {
    for (var i = 1; i < list.length; i++) {
      if (list[i - 1] > list[i]) return false;
    }
    return true;
  }

  void _mergeClusterInto(int from, int to, bool isDeepen, bool isHollow) {
    if (!isDeepen) {
      final residueSum = clusters[from].residueSum;
      clusters[to].residueSum.merge(residueSum);
      _combineClusters(from, to);
    } else {
      _combineClustersClone(from, to);

      if (isHollow) {
        final holes = List<int>.from(clusters[from].indices);
        clusters[to].holes.addAll(holes);
        clusters[to].numHoles += 1;
      }

      clusters[from].mergedInto = to;
      clusters[to].depth += 1;
    }
  }

  void _combineClustersClone(int from, int to) {
    final sum = clusters[from].sum.clone();
    final rect = clusters[from].rect.clone();
    final indices = List<int>.from(clusters[from].indices);

    _combineClusters(from, to);

    clusters[from].sum = sum;
    clusters[from].rect = rect;
    clusters[from].indices.clear();
    clusters[from].indices.addAll(indices);
  }

  void _combineClusters(int from, int to) {
    for (final i in clusters[from].indices) {
      clusterIndices[i] = to;
    }

    clusters[to].indices.addAll(clusters[from].indices);
    clusters[from].indices.clear();
    clusters[to].sum.merge(clusters[from].sum);
    clusters[to].rect.merge(clusters[from].rect);
    clusters[from].sum.clear();
    clusters[from].rect.clear();
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:visioncortex/visioncortex.dart';

import '../error.dart';
import '../ir.dart';
import 'frontend.dart';

/// Cap on the total painted area of ancestor layers, as a multiple of the
/// canvas.
const int _ancestorAreaBudget = 3;

/// Watershed frontend: hierarchical watershed by volume, cut at `detail`.
class WatershedFrontend extends Frontend {
  /// Detail level: where to cut the hierarchy. The normal range is 0..=255 —
  /// each +25.5 roughly doubles the region count.
  final int detail;

  /// Absorb regions smaller than this many pixels into their most
  /// color-similar neighbour after the cut (0 = keep all).
  final int minArea;

  WatershedFrontend({this.detail = 128, this.minArea = 16});

  @override
  Segmentation segment(ColorImage img) =>
      WatershedHierarchy.build(img).cut(img, detail, minArea);
}

/// Flat union-find over u32 ids with path halving.
class _Uf {
  final Uint32List parent;

  _Uf(int n) : parent = Uint32List.fromList(List.generate(n, (i) => i));

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  /// Union by attaching b's root under a's. Caller passes roots.
  void link(int a, int b) {
    parent[b] = a;
  }
}

/// Edge weight: max per-channel absolute difference (L∞), 0..=255.
int _edgeWeightChannels(int ar, int ag, int ab, int br, int bg, int bb) {
  final dr = (ar - br).abs();
  final dg = (ag - bg).abs();
  final db = (ab - bb).abs();
  var m = dr;
  if (dg > m) m = dg;
  if (db > m) m = db;
  return m;
}

/// The image's watershed hierarchy: the minimum spanning tree of the pixel
/// graph with a persistence (volume extinction) per edge. Building it is the
/// expensive step and depends only on the image; [cut] derives a
/// [Segmentation] for any detail level in near-linear time.
class WatershedHierarchy {
  final int width;
  final int height;

  /// MST edges as pixel pairs, in Kruskal creation order.
  final List<(int, int)> mst;

  /// Persistence (volume of the smaller merged basin) per MST edge.
  final Uint64List pers;

  /// MST edge indices by ascending (persistence, index) — the cut order.
  final Uint32List order;

  WatershedHierarchy._(this.width, this.height, this.mst, this.pers, this.order);

  /// Build the hierarchy: counting-sorted Kruskal → binary partition tree →
  /// volume persistence per MST edge.
  static WatershedHierarchy build(ColorImage img) {
    final w = img.width;
    final h = img.height;
    if (w == 0 || h == 0) {
      throw const EmptyImageError();
    }
    final n = w * h;
    if (n == 1) {
      return WatershedHierarchy._(w, h, const [], Uint64List(0), Uint32List(0));
    }

    final px = img.pixels;

    // --- 4-adjacency edges, counting-sorted by weight -------------------
    // Edge id encodes (pixel, direction): 2*p = right, 2*p+1 = down.
    final counts = Uint32List(256);
    final weightOf = Uint8List(2 * n);
    for (var i = 0; i < n; i++) {
      final p = i * 4;
      if (i % w + 1 < w) {
        final q = (i + 1) * 4;
        final wgt =
            _edgeWeightChannels(px[p], px[p + 1], px[p + 2], px[q], px[q + 1], px[q + 2]);
        weightOf[2 * i] = wgt;
        counts[wgt]++;
      }
      if (i ~/ w + 1 < h) {
        final q = (i + w) * 4;
        final wgt =
            _edgeWeightChannels(px[p], px[p + 1], px[p + 2], px[q], px[q + 1], px[q + 2]);
        weightOf[2 * i + 1] = wgt;
        counts[wgt]++;
      }
    }
    var nEdges = 0;
    for (final c in counts) {
      nEdges += c;
    }
    final start = List<int>.filled(256, 0);
    var acc = 0;
    for (var b = 0; b < 256; b++) {
      start[b] = acc;
      acc += counts[b];
    }
    final sorted = Uint32List(nEdges);
    final fill = List<int>.from(start);
    for (var i = 0; i < n; i++) {
      if (i % w + 1 < w) {
        final e = 2 * i;
        final b = weightOf[e];
        sorted[fill[b]] = e;
        fill[b]++;
      }
      if (i ~/ w + 1 < h) {
        final e = 2 * i + 1;
        final b = weightOf[e];
        sorted[fill[b]] = e;
        fill[b]++;
      }
    }

    // --- Kruskal → binary partition tree by altitude ---------------------
    final nNodes = 2 * n - 1;
    const u32max = 0xFFFFFFFF;
    final parent = Uint32List(nNodes)..fillRange(0, nNodes, u32max);
    final alt = Uint8List(nNodes); // leaves at 0
    final child = List<(int, int)>.filled(n - 1, (0, 0));
    final mst = List<(int, int)>.filled(n - 1, (0, 0));
    final uf = _Uf(n);
    final compNode = Uint32List(n);
    for (var i = 0; i < n; i++) {
      compNode[i] = i;
    }
    var next = n;
    for (final e in sorted) {
      final p = e ~/ 2;
      final q = e % 2 == 0 ? p + 1 : p + w;
      final rp = uf.find(p);
      final rq = uf.find(q);
      if (rp == rq) {
        continue;
      }
      final k = next - n;
      alt[next] = weightOf[e];
      child[k] = (compNode[rp], compNode[rq]);
      mst[k] = (p, q);
      parent[compNode[rp]] = next;
      parent[compNode[rq]] = next;
      uf.link(rp, rq);
      compNode[rp] = next;
      next++;
    }
    assert(next == nNodes);

    // --- Volume attribute, leaves → root --------------------------------
    final root = nNodes - 1;
    final area = Uint64List(nNodes);
    for (var i = 0; i < n; i++) {
      area[i] = 1;
    }
    final volume = Uint64List(nNodes);
    for (var i = 0; i < root; i++) {
      final pa = parent[i];
      area[pa] += area[i];
      final rise = alt[pa] - alt[i]; // parent is never lower
      volume[i] += area[i] * rise;
      volume[pa] += volume[i];
    }

    // --- Persistence per MST edge ----------------------------------------
    final corrected = Uint64List.fromList(volume);
    for (var i = n; i < nNodes; i++) {
      final k = i - n;
      if (i != root && alt[i] == alt[parent[i]]) {
        final (c0, c1) = child[k];
        corrected[i] = corrected[c0] > corrected[c1] ? corrected[c0] : corrected[c1];
      }
    }
    final pers = Uint64List(n - 1);
    for (var k = 0; k < n - 1; k++) {
      final (c0, c1) = child[k];
      pers[k] = corrected[c0] < corrected[c1] ? corrected[c0] : corrected[c1];
    }

    final order = Uint32List(n - 1);
    for (var k = 0; k < n - 1; k++) {
      order[k] = k;
    }
    final orderList = order.toList()
      ..sort((a, b) {
        final pa = pers[a];
        final pb = pers[b];
        if (pa != pb) return pa.compareTo(pb);
        return a.compareTo(b);
      });
    final sortedOrder = Uint32List.fromList(orderList);

    return WatershedHierarchy._(w, h, mst, pers, sortedOrder);
  }

  /// Cut the hierarchy at `detail` and emit the stacked [Segmentation].
  Segmentation cut(ColorImage img, int detail, int minArea) {
    final w = width;
    final h = height;
    final n = w * h;
    final m = mst.length;
    final px = img.pixels;

    // --- Region formation: merge every MST edge with persistence ≤ λ ----
    final uf = _Uf(n);
    if (m > 0) {
      final target = math.pow(2.0, detail / 25.5).round().clamp(1, m);
      final lambda = pers[order[m - target]];
      for (final k in order) {
        if (pers[k] > lambda) {
          break;
        }
        final (p, q) = mst[k];
        final rp = uf.find(p);
        final rq = uf.find(q);
        if (rp != rq) {
          uf.link(rp, rq);
        }
      }
    }

    // --- Compact to region ids and region stats --------------------------
    const u32max = 0xFFFFFFFF;
    final preOfRoot = Uint32List(n)..fillRange(0, n, u32max);
    final pre = Uint32List(n);
    var kp = 0;
    for (var i = 0; i < n; i++) {
      final r = uf.find(i);
      if (preOfRoot[r] == u32max) {
        preOfRoot[r] = kp;
        kp++;
      }
      pre[i] = preOfRoot[r];
    }
    final area = Uint64List(kp);
    final sum = List<Int64List>.generate(kp, (_) => Int64List(3));
    for (var i = 0; i < n; i++) {
      final a = pre[i];
      final p = i * 4;
      area[a] += 1;
      sum[a][0] += px[p];
      sum[a][1] += px[p + 1];
      sum[a][2] += px[p + 2];
    }

    // --- Boundary snap, then boundary adjacency ---------------------------
    _snapBoundaries(img, w, h, pre, area, sum);
    final pairs = <(int, int)>[];
    for (var i = 0; i < n; i++) {
      final a = pre[i];
      if (i % w + 1 < w && pre[i + 1] != a) {
        pairs.add((a, pre[i + 1]));
      }
      if (i ~/ w + 1 < h && pre[i + w] != a) {
        pairs.add((a, pre[i + w]));
      }
    }

    // --- Small-basin absorption on the region graph ----------------------
    final ufR = _Uf(kp);
    _absorbSmall(minArea, pairs, ufR, area, sum);

    // --- Final leaf ids in raster order of first appearance --------------
    final leafOf = Uint32List(kp)..fillRange(0, kp, u32max);
    final leafRoot = <int>[]; // leaf id -> absorb root
    final ids = Uint32List(n);
    for (var i = 0; i < n; i++) {
      final r = ufR.find(pre[i]);
      if (leafOf[r] == u32max) {
        leafOf[r] = leafRoot.length;
        leafRoot.add(r);
      }
      ids[i] = leafOf[r];
    }
    final k = leafRoot.length;

    Color mean(Int64List s, int a) => Color(
          (s[0] ~/ a).toUnsigned(8),
          (s[1] ~/ a).toUnsigned(8),
          (s[2] ~/ a).toUnsigned(8),
        );

    final seg = Segmentation(w, h);
    if (k == 1) {
      final r = leafRoot[0];
      seg.layers.add(Layer(Paint.solid(mean(sum[r], area[r].toInt())), _fullCanvas(w, h)));
      return seg;
    }

    // --- Merge tree above the cut ----------------------------------------
    final nTree = 2 * k - 1;
    final treeChild = <(int, int)>[];
    final treeArea = Uint64List(nTree);
    final treeSum = List<Int64List>.generate(nTree, (_) => Int64List(3));
    for (var t = 0; t < k; t++) {
      final r = leafRoot[t];
      treeArea[t] = area[r];
      treeSum[t][0] = sum[r][0];
      treeSum[t][1] = sum[r][1];
      treeSum[t][2] = sum[r][2];
    }
    final uf2 = _Uf(k);
    final nodeRep = Uint32List(k);
    for (var t = 0; t < k; t++) {
      nodeRep[t] = t;
    }
    var next = k;
    for (final e in order) {
      final (p, q) = mst[e];
      final lp = ids[p];
      final lq = ids[q];
      if (lp == lq) {
        continue;
      }
      final a = uf2.find(lp);
      final b = uf2.find(lq);
      if (a == b) {
        continue;
      }
      final node = next;
      treeChild.add((nodeRep[a], nodeRep[b]));
      for (final ch in [nodeRep[a], nodeRep[b]]) {
        treeArea[node] += treeArea[ch];
        for (var c = 0; c < 3; c++) {
          treeSum[node][c] += treeSum[ch][c];
        }
      }
      uf2.link(a, b);
      nodeRep[a] = next;
      next++;
    }
    assert(next == nTree);

    // Per-leaf pixel lists, for painting ancestor masks.
    final leafLen = Uint32List(k);
    for (final id in ids) {
      leafLen[id]++;
    }
    final leafStart = List<int>.filled(k + 1, 0);
    for (var t = 0; t < k; t++) {
      leafStart[t + 1] = leafStart[t] + leafLen[t];
    }
    final leafPx = Uint32List(n);
    final fillCursor = List<int>.from(leafStart);
    for (var i = 0; i < n; i++) {
      final id = ids[i];
      leafPx[fillCursor[id]] = i;
      fillCursor[id]++;
    }

    // --- Emit: root, ancestors (budgeted), then the final regions --------
    final root = nTree - 1;
    seg.layers.add(Layer(
      Paint.solid(mean(treeSum[root], treeArea[root].toInt())),
      _fullCanvas(w, h),
    ));
    var budget = _ancestorAreaBudget * n;
    for (var node = root - 1; node >= k; node--) {
      final nodeArea = treeArea[node];
      if (nodeArea > budget) {
        continue;
      }
      budget -= nodeArea;
      seg.layers.add(Layer(
        Paint.solid(mean(treeSum[node], treeArea[node].toInt())),
        _nodeMask(node, k, treeChild, leafStart, leafPx, w),
      ));
    }
    for (var t = 0; t < k; t++) {
      seg.layers.add(Layer(
        Paint.solid(mean(treeSum[t], treeArea[t].toInt())),
        _nodeMask(t, k, treeChild, leafStart, leafPx, w),
      ));
    }
    return seg;
  }
}

RegionMask _fullCanvas(int w, int h) {
  final image = BinaryImage.newWH(w, h);
  image.pixels.fillRange(0, w * h, 1);
  return RegionMask(image, PointI32(0, 0));
}

/// How many 1-px boundary-snap sweeps to run.
const int _snapSweeps = 4;

/// Tolerance for the mixture test: an antialiased blend of two region colors
/// satisfies `d(p,A) + d(p,B) = d(A,B)` exactly (L1); this slack admits
/// sensor/JPEG noise.
const int _snapSlack = 16;

/// Re-assign boundary pixels to whichever adjacent region's mean color is
/// closest (strictly closer than their own region's mean, L1), gated on the
/// mixture test. Double-buffered sweeps; regions are never emptied.
void _snapBoundaries(ColorImage img, int w, int h, Uint32List labels,
    Uint64List area, List<Int64List> sum) {
  final n = w * h;
  final k = area.length;
  if (k < 2) {
    return;
  }
  final px = img.pixels;

  int? snapTarget(int i, Uint32List labels, List<Int32List> mean) {
    final a = labels[i];
    final x = i % w;
    final y = i ~/ w;
    final nb = [
      labels[x > 0 ? i - 1 : i],
      labels[x + 1 < w ? i + 1 : i],
      labels[y > 0 ? i - w : i],
      labels[y + 1 < h ? i + w : i],
    ];
    if (nb[0] == a && nb[1] == a && nb[2] == a && nb[3] == a) {
      return null; // interior pixel
    }
    final p = i * 4;
    final cv = [px[p].toInt(), px[p + 1].toInt(), px[p + 2].toInt()];
    int dist(Int32List m) =>
        (cv[0] - m[0]).abs() + (cv[1] - m[1]).abs() + (cv[2] - m[2]).abs();
    final da = dist(mean[a]);
    bool mixture(int pIdx, int qIdx) {
      var dpq = 0;
      for (var ch = 0; ch < 3; ch++) {
        dpq += (mean[pIdx][ch] - mean[qIdx][ch]).abs();
      }
      return dist(mean[pIdx]) + dist(mean[qIdx]) <= dpq + _snapSlack;
    }

    var best = (da, a);
    for (final b in nb) {
      if (b == a) {
        continue;
      }
      final db = dist(mean[b]);
      if (db >= best.$1) {
        continue;
      }
      var qualifies = mixture(a, b);
      if (!qualifies) {
        for (final c in nb) {
          if (c != a && c != b && mixture(c, b)) {
            qualifies = true;
            break;
          }
        }
      }
      if (qualifies) {
        best = (db, b);
      }
    }
    return best.$2 != a ? best.$2 : null;
  }

  final mean = List<Int32List>.generate(k, (_) => Int32List(3));
  final flips = <(int, int)>[]; // (pixel, new label)
  var front = <int>[];
  final touched = <int>[];
  for (var sweep = 0; sweep < _snapSweeps; sweep++) {
    for (var r = 0; r < k; r++) {
      for (var ch = 0; ch < 3; ch++) {
        mean[r][ch] = (sum[r][ch] ~/ area[r]).toInt();
      }
    }
    flips.clear();
    if (sweep == 0) {
      // Interior first, then the border rim.
      final hIn = h - 1;
      final wIn = w - 1;
      for (var y = 1; y < hIn; y++) {
        for (var i = y * w + 1; i < y * w + wIn; i++) {
          final a = labels[i];
          if (labels[i - 1] == a && labels[i + 1] == a && labels[i - w] == a &&
              labels[i + w] == a) {
            continue;
          }
          final b = snapTarget(i, labels, mean);
          if (b != null) {
            flips.add((i, b));
          }
        }
      }
      final rim = <int>[
        for (var x = 0; x < w; x++) x,
        for (var y = 1; y < hIn; y++) y * w,
        if (w > 1) for (var y = 1; y < hIn; y++) y * w + w - 1,
        if (h > 1) for (var x = hIn * w; x < n; x++) x,
      ];
      for (final i in rim) {
        final b = snapTarget(i, labels, mean);
        if (b != null) {
          flips.add((i, b));
        }
      }
    } else {
      for (final i in front) {
        final b = snapTarget(i, labels, mean);
        if (b != null) {
          flips.add((i, b));
        }
      }
    }
    if (flips.isEmpty) {
      break;
    }
    for (final (i, b) in flips) {
      final a = labels[i];
      if (area[a] <= 1) {
        continue; // never empty a region
      }
      final p = i * 4;
      labels[i] = b;
      area[a] -= 1;
      area[b] += 1;
      sum[a][0] -= px[p];
      sum[a][1] -= px[p + 1];
      sum[a][2] -= px[p + 2];
      sum[b][0] += px[p];
      sum[b][1] += px[p + 1];
      sum[b][2] += px[p + 2];
    }
    // Next sweep revisits each flipped pixel and its 4-neighbourhood.
    front = [];
    for (final (i, _) in flips) {
      final x = i % w;
      final y = i ~/ w;
      front.add(i);
      if (x > 0) front.add(i - 1);
      if (x + 1 < w) front.add(i + 1);
      if (y > 0) front.add(i - w);
      if (y + 1 < h) front.add(i + w);
    }
    front.sort();
    front = front.toSet().toList();
    touched.addAll(front);
  }
  final touchedSorted = touched.toSet().toList()..sort();
  _absorbFragments(img, w, h, labels, area, sum, touchedSorted);
}

/// Fragments a snap flip may pinch off: a connected component disconnected
/// from the rest of its region and fitting under this floor is re-assigned to
/// the most color-similar adjacent region.
const int _snapFragmentMax = _snapSweeps * _snapSweeps;

void _absorbFragments(ColorImage img, int w, int h, Uint32List labels,
    Uint64List area, List<Int64List> sum, List<int> seeds) {
  final n = w * h;
  final px = img.pixels;
  final visited = List<bool>.filled(n, false);
  final comp = <int>[];
  var rim = <int>[];
  for (final s in seeds) {
    if (visited[s]) {
      continue;
    }
    // Flood s's same-label component, capped: hitting the cap proves it is no
    // fragment.
    final l = labels[s];
    visited[s] = true;
    comp.clear();
    comp.add(s);
    rim = [];
    var over = false;
    var qi = 0;
    flood:
    while (qi < comp.length) {
      final i = comp[qi];
      qi++;
      final x = i % w;
      final y = i ~/ w;
      for (final j in [
        if (x > 0) i - 1,
        if (x + 1 < w) i + 1,
        if (y > 0) i - w,
        if (y + 1 < h) i + w,
      ]) {
        if (labels[j] != l) {
          rim.add(labels[j]);
          continue;
        }
        if (visited[j]) {
          if (!comp.contains(j)) {
            over = true; // joined an earlier over-cap flood
            break flood;
          }
          continue;
        }
        if (comp.length > _snapFragmentMax) {
          over = true;
          break flood;
        }
        visited[j] = true;
        comp.add(j);
      }
    }
    if (over ||
        comp.length > _snapFragmentMax ||
        comp.length >= area[l] ||
        rim.isEmpty) {
      continue;
    }
    // The whole fragment moves to the adjacent region whose mean is closest
    // to the fragment's own mean.
    final fsum = Int64List(3);
    for (final i in comp) {
      final p = i * 4;
      fsum[0] += px[p];
      fsum[1] += px[p + 1];
      fsum[2] += px[p + 2];
    }
    final fl = comp.length;
    final rimSorted = rim.toSet().toList()..sort();
    var best = rimSorted
        .map((b) {
          var d = 0;
          for (var ch = 0; ch < 3; ch++) {
            d += ((fsum[ch] ~/ fl) - (sum[b][ch] ~/ area[b])).abs();
          }
          return (d, b);
        })
        .reduce((a, b) => a.$1 <= b.$1 ? a : b)
        .$2;
    for (final i in comp) {
      final p = i * 4;
      labels[i] = best;
      area[l] -= 1;
      area[best] += 1;
      sum[l][0] -= px[p];
      sum[l][1] -= px[p + 1];
      sum[l][2] -= px[p + 2];
      sum[best][0] += px[p];
      sum[best][1] += px[p + 1];
      sum[best][2] += px[p + 2];
    }
  }
}

/// Absorb regions smaller than `minArea` into their most color-similar
/// neighbour, working on the region graph. Sweeps until nothing undersized
/// remains (or an undersized region has no neighbour at all).
void _absorbSmall(int minArea, List<(int, int)> pairs, _Uf uf, Uint64List area,
    List<Int64List> sum) {
  if (minArea <= 1) {
    return;
  }
  final k = area.length;
  int meanDiff(Int64List sa, int aa, Int64List sb, int ab) {
    var d = 0;
    for (var ch = 0; ch < 3; ch++) {
      d += ((sa[ch] ~/ aa) - (sb[ch] ~/ ab)).abs();
    }
    return d;
  }

  const u32max = 0xFFFFFFFF;
  while (true) {
    // diff sentinel chosen to stay exactly representable on web (2^53).
    const diffSentinel = 0x7FFFFFFFFFFFF;
    final best = List<(int, int)>.filled(k, (diffSentinel, u32max));
    var anySmall = false;
    for (final (p, q) in pairs) {
      final a = uf.find(p);
      final b = uf.find(q);
      if (a == b) {
        continue;
      }
      for (final (s, t) in [(a, b), (b, a)]) {
        if (area[s] < minArea) {
          anySmall = true;
          final d = meanDiff(sum[s], area[s].toInt(), sum[t], area[t].toInt());
          if (d < best[s].$1 || (d == best[s].$1 && t < best[s].$2)) {
            best[s] = (d, t);
          }
        }
      }
    }
    if (!anySmall) {
      break;
    }
    var merged = false;
    for (var r = 0; r < k; r++) {
      final (_, tgt) = best[r];
      if (tgt == u32max) {
        continue;
      }
      final rr = uf.find(r);
      if (rr != r) {
        continue; // already absorbed this sweep
      }
      final rt = uf.find(tgt);
      if (rt == rr) {
        continue;
      }
      uf.link(rt, rr);
      area[rt] += area[r];
      for (var ch = 0; ch < 3; ch++) {
        sum[rt][ch] += sum[r][ch];
      }
      merged = true;
    }
    if (!merged) {
      break; // isolated undersized region (e.g. whole-canvas)
    }
  }
}

/// Paint a tree node's region (the union of the final regions beneath it)
/// into a bbox-cropped mask.
RegionMask _nodeMask(
    int node, int k, List<(int, int)> treeChild, List<int> leafStart, Uint32List leafPx,
    int w) {
  final leaves = <int>[];
  final stack = <int>[node];
  while (stack.isNotEmpty) {
    final t = stack.removeLast();
    if (t < k) {
      leaves.add(t);
    } else {
      final (a, b) = treeChild[t - k];
      stack.add(a);
      stack.add(b);
    }
  }
  var x0 = 0x7FFFFFFF, y0 = 0x7FFFFFFF, x1 = -0x7FFFFFFF, y1 = -0x7FFFFFFF;
  for (final t in leaves) {
    for (var i = leafStart[t]; i < leafStart[t + 1]; i++) {
      final p = leafPx[i];
      final x = p % w;
      final y = p ~/ w;
      if (x < x0) x0 = x;
      if (y < y0) y0 = y;
      if (x > x1) x1 = x;
      if (y > y1) y1 = y;
    }
  }
  final bw = x1 - x0 + 1;
  final bh = y1 - y0 + 1;
  final image = BinaryImage.newWH(bw, bh);
  for (final t in leaves) {
    for (var i = leafStart[t]; i < leafStart[t + 1]; i++) {
      final p = leafPx[i];
      image.setPixel(p % w - x0, p ~/ w - y0, true);
    }
  }
  return RegionMask(image, PointI32(x0, y0));
}

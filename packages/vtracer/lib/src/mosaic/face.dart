part of 'mosaic.dart';

/// Island id for pixels that belong to no region.
const int _noIsland = 0xFFFFFFFF;

/// A closed cycle of directed segments bounding (part of) a region.
class Contour {
  final List<SegRef> refs;
  Contour(this.refs);
}

/// One connected patch of a region and all of its contours (outer + holes).
class Face {
  final RegionId region;
  final List<Contour> contours;

  Face(this.region, this.contours);
}

/// Connected-component ("island") id per pixel, grouping equal labels with
/// 8-connectivity (which matches the successor rule's checkerboard pinch).
Uint32List _islands(LabelMap map) {
  final w = map.width;
  final h = map.height;
  final ids = Uint32List(w * h)..fillRange(0, w * h, _noIsland);
  var next = 0;
  final stack = <int>[];

  for (var start = 0; start < w * h; start++) {
    if (ids[start] != _noIsland || map.labels[start] == outsideRegion) {
      continue;
    }
    final label = map.labels[start];
    final id = next;
    next++;
    ids[start] = id;
    stack.add(start);

    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w;
      final y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) {
            continue;
          }
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
            continue;
          }
          final n = ny * w + nx;
          if (ids[n] == _noIsland && map.labels[n] == label) {
            ids[n] = id;
            stack.add(n);
          }
        }
      }
    }
  }
  return ids;
}

/// Which island a contour bounds, taken from the region-side pixel flanking
/// its first directed edge.
int _islandOf(BoundaryGraph graph, LabelMap map, Uint32List ids, SegRef r) {
  final seg = graph.segments[r.seg];
  int cornerX, cornerY, dir;
  if (seg.isRing) {
    final n = seg.points.length;
    // A ring is used forward by the region on its left, reversed by the one
    // on its right; take the first step of the chosen direction.
    late PointI32 from;
    late PointI32 to;
    if (r.forward) {
      from = seg.points[0];
      to = seg.points[1];
    } else {
      from = seg.points[n - 1];
      to = seg.points[n - 2];
    }
    cornerX = from.x;
    cornerY = from.y;
    dir = dirFromDelta(to.x - from.x, to.y - from.y);
  } else if (r.forward) {
    final node = graph.nodes[seg.start!];
    cornerX = node.corner.x;
    cornerY = node.corner.y;
    dir = seg.firstDir;
  } else {
    final node = graph.nodes[seg.end!];
    cornerX = node.corner.x;
    cornerY = node.corner.y;
    dir = _reverse(seg.lastDir);
  }

  final (px, py) = leftPixelCoord(cornerX, cornerY, dir);
  if (px < 0 || py < 0 || px >= map.width || py >= map.height) {
    return _noIsland;
  }
  return ids[py * map.width + px];
}

/// Left region of a directed segment view.
RegionId _leftRegion(BoundaryGraph graph, SegRef r) {
  final seg = graph.segments[r.seg];
  return r.forward ? seg.left : seg.right;
}

/// Pick the next unit direction leaving `corner`, keeping region `r` on the
/// left: sharpest right turn first (this pinches checkerboard nodes and keeps
/// contours simple).
int _successor(LabelMap map, int x, int y, int dIn, RegionId r) {
  for (final d in [_turnRight(dIn), _straight(dIn), _turnLeft(dIn)]) {
    if (edgePresent(map, x, y, d) && leftPixelAt(map, x, y, d) == r) {
      return d;
    }
  }
  throw StateError('no successor edge keeps the region on the left');
}

List<Face> assemble(BoundaryGraph graph, LabelMap map) {
  final ids = _islands(map);
  // Keyed by (region, island) — a SplayTreeMap keeps face order
  // deterministic: region ascending, then island in raster-scan order.
  final byIsland = SplayTreeMap<(int, int), List<Contour>>(
    (a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    },
  );
  // usage[seg][0] = forward view used, [1] = backward view used.
  final used = List.generate(graph.segments.length, (_) => [false, false]);

  for (var segId = 0; segId < graph.segments.length; segId++) {
    if (graph.segments[segId].isRing) {
      continue;
    }
    for (final forward in [true, false]) {
      final start = SegRef(segId, forward);
      final region = _leftRegion(graph, start);
      if (region == outsideRegion || used[segId][forward ? 1 : 0]) {
        continue;
      }

      final contour = <SegRef>[];
      var cur = start;
      while (true) {
        used[cur.seg][cur.forward ? 1 : 0] = true;
        contour.add(cur);

        final seg = graph.segments[cur.seg];
        final (nodeId, dIn) = cur.forward
            ? (seg.end!, seg.lastDir)
            : (seg.start!, _reverse(seg.firstDir));
        final corner = graph.nodes[nodeId].corner;
        final dNext = _successor(map, corner.x, corner.y, dIn, region);
        final out = graph.nodes[nodeId].out[dNext];
        if (out == null) {
          throw StateError('successor direction must have an outgoing segment');
        }
        cur = out;

        if (cur == start) {
          break;
        }
      }
      if (region < map.paints.length) {
        final island = _islandOf(graph, map, ids, start);
        byIsland.putIfAbsent((region, island), () => []).add(Contour(contour));
      }
    }
  }

  // Rings: the left side uses it forward, the right side reversed.
  for (var segId = 0; segId < graph.segments.length; segId++) {
    final seg = graph.segments[segId];
    if (!seg.isRing) {
      continue;
    }
    for (final (region, forward) in [(seg.left, true), (seg.right, false)]) {
      if (region == outsideRegion || region >= map.paints.length) {
        continue;
      }
      final r = SegRef(segId, forward);
      final island = _islandOf(graph, map, ids, r);
      byIsland.putIfAbsent((region, island), () => []).add(Contour([r]));
    }
  }

  return [
    for (final e in byIsland.entries) Face(e.key.$1, e.value),
  ];
}

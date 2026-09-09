part of 'mosaic.dart';

typedef NodeId = int;
typedef SegId = int;

// Unit directions, clockwise in y-down screen space so `(d + 1) % 4` is a
// right turn and `(d + 2) % 4` is a reversal.
const int _dirN = 0;
const int _dirE = 1;
const int _dirS = 2;
const int _dirW = 3;

/// (dx, dy) per direction.
const List<(int, int)> _dvec = [(0, -1), (1, 0), (0, 1), (-1, 0)];

int _turnRight(int d) => (d + 1) % 4;
int _straight(int d) => d;
int _turnLeft(int d) => (d + 3) % 4;
int _reverse(int d) => (d + 2) % 4;

/// A directed reference to a segment: either traversed forward or reversed.
class SegRef {
  final int seg;
  final bool forward;

  const SegRef(this.seg, this.forward);

  @override
  bool operator ==(Object other) =>
      other is SegRef && seg == other.seg && forward == other.forward;

  @override
  int get hashCode => Object.hash(seg, forward);
}

/// A junction corner (degree >= 3) with the segment leaving it in each unit
/// direction (if any).
class Node {
  final PointI32 corner;
  final List<SegRef?> out;

  Node(this.corner) : out = List.filled(4, null);
}

/// A maximal boundary chain between two nodes, or a nodeless ring.
class Segment {
  /// Lattice polyline; `len >= 2`. For a ring, first == last.
  final List<PointI32> points;

  /// Null for rings.
  final int? start;

  /// Null for rings.
  final int? end;

  /// Region on the left when traversing forward (y-down convention).
  final RegionId left;

  /// Region on the right when traversing forward.
  final RegionId right;

  /// Direction of the first edge (leaving `start`); unused for rings.
  final int firstDir;

  /// Direction of the last edge (arriving at `end`); unused for rings.
  final int lastDir;

  Segment({
    required this.points,
    required this.start,
    required this.end,
    required this.left,
    required this.right,
    required this.firstDir,
    required this.lastDir,
  });

  bool get isRing => start == null;
}

/// The extracted boundary graph. Faces are assembled separately.
class BoundaryGraph {
  final List<Node> nodes;
  final List<Segment> segments;

  BoundaryGraph(this.nodes, this.segments);

  static BoundaryGraph extract(LabelMap map) {
    final ex = _Extractor(map);
    ex.classify();
    ex.traceSegments();
    ex.traceRings();
    return BoundaryGraph(ex.nodes, ex.segments);
  }
}

class _Extractor {
  final LabelMap map;
  final int w;
  final int h;

  /// NodeId per lattice corner, -1 if not a node. Size (W+1)(H+1).
  Int32List nodeAt;

  /// Visited flags for undirected unit edges.
  List<bool> visitedV; // vertical edge (x in 0..=W, y in 0..H)
  List<bool> visitedH; // horizontal edge (x in 0..W, y in 0..=H)

  List<Node> nodes = [];
  List<Segment> segments = [];

  _Extractor(this.map)
      : w = map.width,
        h = map.height,
        nodeAt = Int32List((map.width + 1) * (map.height + 1)),
        visitedV = List<bool>.filled((map.width + 1) * map.height, false),
        visitedH = List<bool>.filled(map.width * (map.height + 1), false) {
    nodeAt.fillRange(0, nodeAt.length, -1);
  }

  int _cornerIndex(int x, int y) => y * (w + 1) + x;

  /// 4-bit edge mask (N,E,S,W) present at corner (x,y).
  int _edgeMask(int x, int y) {
    final nw = map.label(x - 1, y - 1);
    final ne = map.label(x, y - 1);
    final sw = map.label(x - 1, y);
    final se = map.label(x, y);
    var m = 0;
    if (nw != ne) m |= 1 << _dirN;
    if (ne != se) m |= 1 << _dirE;
    if (sw != se) m |= 1 << _dirS;
    if (nw != sw) m |= 1 << _dirW;
    return m;
  }

  static int _countBits(int v) {
    var c = 0;
    while (v != 0) {
      v &= v - 1;
      c++;
    }
    return c;
  }

  /// (left, right) regions flanking the directed edge leaving (x,y) in `d`.
  (RegionId, RegionId) _sidePixels(int x, int y, int d) {
    final nw = map.label(x - 1, y - 1);
    final ne = map.label(x, y - 1);
    final sw = map.label(x - 1, y);
    final se = map.label(x, y);
    switch (d) {
      case _dirN:
        return (nw, ne);
      case _dirE:
        return (ne, se);
      case _dirS:
        return (se, sw);
      case _dirW:
        return (sw, nw);
      default:
        throw StateError('unreachable');
    }
  }

  /// Canonical (is_vertical, index) for the undirected unit edge leaving
  /// (x,y) in direction `d`.
  (bool, int) _edgeSlot(int x, int y, int d) {
    switch (d) {
      case _dirN:
        return (true, (y - 1) * (w + 1) + x);
      case _dirS:
        return (true, y * (w + 1) + x);
      case _dirE:
        return (false, y * w + x);
      case _dirW:
        return (false, y * w + (x - 1));
      default:
        throw StateError('unreachable');
    }
  }

  bool _isVisited(int x, int y, int d) {
    final (v, i) = _edgeSlot(x, y, d);
    return v ? visitedV[i] : visitedH[i];
  }

  void _markVisited(int x, int y, int d) {
    final (v, i) = _edgeSlot(x, y, d);
    if (v) {
      visitedV[i] = true;
    } else {
      visitedH[i] = true;
    }
  }

  /// Pass A — classify corners and allocate node ids for degree >= 3.
  void classify() {
    for (var y = 0; y <= h; y++) {
      for (var x = 0; x <= w; x++) {
        final deg = _countBits(_edgeMask(x, y));
        if (deg >= 3) {
          final id = nodes.length;
          nodes.add(Node(PointI32(x, y)));
          nodeAt[_cornerIndex(x, y)] = id;
        }
      }
    }
  }

  int? _nodeId(int x, int y) {
    final id = nodeAt[_cornerIndex(x, y)];
    return id == -1 ? null : id;
  }

  /// Walk from (x0,y0) heading d0 until a node (or back to the start for
  /// rings). Returns the polyline, final heading, and end corner.
  (List<PointI32>, int, int, int) _walk(int x0, int y0, int d0) {
    final points = <PointI32>[PointI32(x0, y0)];
    var cx = x0, cy = y0, d = d0;
    while (true) {
      _markVisited(cx, cy, d);
      final (dx, dy) = _dvec[d];
      final nx = cx + dx;
      final ny = cy + dy;
      points.add(PointI32(nx, ny));

      final mask = _edgeMask(nx, ny);
      if (_countBits(mask) >= 3) {
        return (points, d, nx, ny); // reached a node
      }
      if (nx == x0 && ny == y0) {
        return (points, d, nx, ny); // closed ring
      }
      // Degree-2: continue via the unique present edge that is not the
      // reverse of how we arrived.
      final rev = _reverse(d);
      var nd = d;
      for (var cand = 0; cand < 4; cand++) {
        if (cand != rev && (mask & (1 << cand)) != 0) {
          nd = cand;
          break;
        }
      }
      d = nd;
      cx = nx;
      cy = ny;
    }
  }

  /// Pass B — trace node-to-node segments.
  void traceSegments() {
    final nodeCorners = nodes.map((n) => n.corner).toList();
    for (var nid = 0; nid < nodeCorners.length; nid++) {
      final corner = nodeCorners[nid];
      final x = corner.x;
      final y = corner.y;
      final mask = _edgeMask(x, y);
      for (var d = 0; d < 4; d++) {
        if ((mask & (1 << d)) == 0 || _isVisited(x, y, d)) {
          continue;
        }
        final (left, right) = _sidePixels(x, y, d);
        final (points, lastDir, ex, ey) = _walk(x, y, d);
        final end = _nodeId(ex, ey);
        if (end == null) {
          throw StateError('segment must end at a node');
        }

        final segId = segments.length;
        segments.add(Segment(
          points: points,
          start: nid,
          end: end,
          left: left,
          right: right,
          firstDir: d,
          lastDir: lastDir,
        ));
        nodes[nid].out[d] = SegRef(segId, true);
        // Leaving the end node backward along this segment.
        final back = _reverse(lastDir);
        nodes[end].out[back] = SegRef(segId, false);
      }
    }
  }

  /// Pass C — closed rings from any remaining unvisited boundary edges.
  void traceRings() {
    for (var y = 0; y <= h; y++) {
      for (var x = 0; x <= w; x++) {
        final mask = _edgeMask(x, y);
        for (var d = 0; d < 4; d++) {
          if ((mask & (1 << d)) == 0 || _isVisited(x, y, d)) {
            continue;
          }
          final (left, right) = _sidePixels(x, y, d);
          final (points, _, _, _) = _walk(x, y, d);
          segments.add(Segment(
            points: points,
            start: null,
            end: null,
            left: left,
            right: right,
            firstDir: d,
            lastDir: 0,
          ));
        }
      }
    }
  }
}

/// Pixel flanking the left of the directed edge leaving (x,y) in `d`.
(int, int) leftPixelCoord(int x, int y, int d) {
  switch (d) {
    case _dirN:
      return (x - 1, y - 1);
    case _dirE:
      return (x, y - 1);
    case _dirS:
      return (x, y);
    case _dirW:
      return (x - 1, y);
    default:
      return (x, y);
  }
}

/// Unit direction of a single lattice step.
int dirFromDelta(int dx, int dy) {
  for (var i = 0; i < 4; i++) {
    if (_dvec[i] == (dx, dy)) {
      return i;
    }
  }
  throw StateError('consecutive lattice points differ by one unit step');
}

/// Left region flanking the directed edge leaving (x,y) in `d`.
RegionId leftPixelAt(LabelMap map, int x, int y, int d) {
  if (d < 0 || d > 3) {
    return outsideRegion;
  }
  final (px, py) = leftPixelCoord(x, y, d);
  return map.label(px, py);
}

/// Edge-present test for face assembly.
bool edgePresent(LabelMap map, int x, int y, int d) {
  final nw = map.label(x - 1, y - 1);
  final ne = map.label(x, y - 1);
  final sw = map.label(x - 1, y);
  final se = map.label(x, y);
  switch (d) {
    case _dirN:
      return nw != ne;
    case _dirE:
      return ne != se;
    case _dirS:
      return sw != se;
    case _dirW:
      return nw != sw;
    default:
      return false;
  }
}

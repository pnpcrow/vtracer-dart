part of 'mosaic.dart';

/// Run the full mosaic pipeline: flatten → merge similar neighbours →
/// boundary graph → faces → fit → curve passes → compose.
///
/// Every boundary curve exists exactly once; the two adjacent regions
/// reference the same fitted geometry, one traversed reversed.
VectorDoc composeMosaic(
    Segmentation seg, SegmentFitter fitter, int mergeDiff, List<CurvePass> passes) {
  final map = LabelMap.fromSegmentation(seg);
  map.mergeSimilar(mergeDiff);
  final graph = BoundaryGraph.extract(map);
  final faces = assemble(graph, map);

  // Fit every segment exactly once; both adjacent faces share the result.
  final fitted = <FittedSegment>[];
  for (final s in graph.segments) {
    final ring = s.isRing;
    var geom = ring ? fitter.fitRing(s).geom : fitter.fitOpen(s).geom;
    for (final pass in passes) {
      geom = ring ? pass.ring(geom) : pass.open(geom);
    }
    fitted.add(FittedSegment(geom));
  }

  final doc = VectorDoc(seg.width, seg.height);
  for (final face in faces) {
    final path = _buildPath(face, fitted);
    if (!path.isEmpty) {
      doc.shapes.add(Shape(map.paints[face.region], path));
    }
  }
  return doc;
}

MultiPath _buildPath(Face face, List<FittedSegment> fitted) {
  final mp = MultiPath();
  for (final contour in face.contours) {
    final sub = SubPath();
    _emitContour(contour, fitted, sub);
    if (!sub.isEmpty) {
      sub.commands.add(const ClosePath());
      mp.subpaths.add(sub);
    }
  }
  return mp;
}

void _emitContour(Contour contour, List<FittedSegment> fitted, SubPath sub) {
  for (var i = 0; i < contour.refs.length; i++) {
    final sref = contour.refs[i];
    final geom = fitted[sref.seg].geom;
    _emitSegment(geom, sref.forward, i == 0, sub);
  }
}

/// Append one oriented segment's commands. When `first`, opens with a
/// `MoveTo`; otherwise the leading point (shared with the previous segment)
/// is skipped.
void _emitSegment(FittedGeom geom, bool forward, bool first, SubPath sub) {
  switch (geom) {
    case FittedPolyline(:final points):
      if (points.length < 2) {
        return;
      }
      final ordered =
          forward ? points : points.reversed.map((p) => p.clone()).toList();
      if (first) {
        sub.commands.add(MoveTo(ordered[0].clone()));
      }
      for (var i = 1; i < ordered.length; i++) {
        sub.commands.add(LineTo(ordered[i].clone()));
      }
    case FittedBeziers(:final curves):
      if (curves.isEmpty) {
        return;
      }
      // Reversing a cubic is exact: [p0,p1,p2,p3] -> [p3,p2,p1,p0], and the
      // whole chain reverses in order too.
      final ordered = forward
          ? curves
          : curves.reversed.map((c) => [c[3], c[2], c[1], c[0]]).toList();
      if (first) {
        sub.commands.add(MoveTo(ordered[0][0].clone()));
      }
      for (final c in ordered) {
        sub.commands.add(CubicTo(c[1].clone(), c[2].clone(), c[3].clone()));
      }
  }
}

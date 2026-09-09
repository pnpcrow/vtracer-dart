import 'dart:typed_data';

import 'bound.dart';
import 'image/binary_image.dart';
import 'path/compound.dart';
import 'path/paths.dart';
import 'point.dart';
import 'path/simplify.dart';
import 'path/spline.dart';

/// A connected component of set pixels in a [BinaryImage].
class BinaryCluster {
  /// Member pixels in absolute coordinates.
  List<PointI32> points;

  BoundingRect rect;

  BinaryCluster()
      : points = [],
        rect = BoundingRect.zero();

  void add(PointI32 pos) {
    points.add(pos);
    rect.addXY(pos.x, pos.y);
  }

  int get size => points.length;

  BinaryImage toBinaryImage() {
    final image = BinaryImage.newWH(rect.width, rect.height);
    for (final p in points) {
      image.setPixel(p.x - rect.left, p.y - rect.top, true);
    }
    return image;
  }

  void offsetBy(PointI32 o) {
    for (final p in points) {
      p.x += o.x;
      p.y += o.y;
    }
    rect.translate(o);
  }

  /// Trace the mask (holes included) into a compound path in absolute
  /// coordinates: this offset handles the rect position.
  CompoundPath toCompoundPath(
    PathSimplifyMode mode,
    double cornerThreshold,
    double segmentLength,
    int maxIterations,
    double spliceThreshold,
  ) {
    final origin = PointI32(rect.left, rect.top);
    return imageToCompoundPath(
      origin,
      toBinaryImage(),
      mode,
      cornerThreshold,
      segmentLength,
      maxIterations,
      spliceThreshold,
    );
  }

  static const double outsetRatio = 8.0;

  /// Trace `image` (a local mask) into a compound path offset by `offset`.
  static CompoundPath imageToCompoundPath(
    PointI32 offset,
    BinaryImage image,
    PathSimplifyMode mode,
    double cornerThreshold,
    double segmentLength,
    int maxIterations,
    double spliceThreshold,
  ) {
    switch (mode) {
      case PathSimplifyMode.none:
      case PathSimplifyMode.polygon:
        final paths = imageToPaths(image, mode);
        final group = CompoundPath();
        for (final path in paths) {
          path.offsetBy(offset);
          group.addPathI32(path);
        }
        return group;
      case PathSimplifyMode.spline:
        final splines = imageToSplines(
            image, cornerThreshold, segmentLength, maxIterations, spliceThreshold);
        final group = CompoundPath();
        for (final spline in splines) {
          spline.offsetBy(offset.toPointF64());
          group.addSpline(spline);
        }
        return group;
    }
  }

  /// Outer boundary + hole boundaries. Holes touching the image border are
  /// merged into the background instead of becoming separate boundaries.
  static List<(BinaryImage, PointI32)> _boundariesWithHoles(BinaryImage image) {
    final boundaries = <(BinaryImage, PointI32)>[(image.clone(), PointI32(0, 0))];
    final holes = image.negative().toClusters(false);
    for (final hole in holes.clusters) {
      if (hole.rect.left == 0 ||
          hole.rect.top == 0 ||
          hole.rect.right == image.width ||
          hole.rect.bottom == image.height) {
        continue;
      }
      // Fill the hole into the outer boundary.
      final outer = boundaries[0].$1;
      for (final p in hole.points) {
        outer.setPixel(p.x, p.y, true);
      }
      boundaries.add((hole.toBinaryImage(), PointI32(hole.rect.left, hole.rect.top)));
    }
    return boundaries;
  }

  static List<PathI32> imageToPaths(BinaryImage image, PathSimplifyMode mode) {
    final boundaries = _boundariesWithHoles(image);
    final paths = <PathI32>[];
    for (var i = 0; i < boundaries.length; i++) {
      final (bImage, offset) = boundaries[i];
      var path = PathI32.imageToPath(bImage, i == 0, mode);
      path.offsetBy(offset);
      if (!path.isEmpty) {
        paths.add(path);
      }
    }
    return paths;
  }

  static List<Spline> imageToSplines(
    BinaryImage image,
    double cornerThreshold,
    double segmentLength,
    int maxIterations,
    double spliceThreshold,
  ) {
    final boundaries = _boundariesWithHoles(image);
    final splines = <Spline>[];
    for (var i = 0; i < boundaries.length; i++) {
      final (bImage, offset) = boundaries[i];
      var spline = Spline.fromImage(
        bImage,
        i == 0,
        cornerThreshold,
        outsetRatio,
        segmentLength,
        maxIterations,
        spliceThreshold,
      );
      spline.offsetBy(offset.toPointF64());
      if (!spline.isEmpty) {
        splines.add(spline);
      }
    }
    return splines;
  }
}

/// A collection of [BinaryCluster]s.
class BinaryClusters {
  List<BinaryCluster> clusters;
  BoundingRect rect;

  BinaryClusters()
      : clusters = [],
        rect = BoundingRect.zero();

  int get length => clusters.length;
  bool get isEmpty => clusters.isEmpty;
  BinaryCluster getCluster(int index) => clusters[index];

  void addCluster(BinaryCluster cluster) {
    rect.merge(cluster.rect);
    clusters.add(cluster);
  }
}

extension BinaryImageClusters on BinaryImage {
  /// Group the set pixels into connected components (4- or 8-connectivity).
  ///
  /// Direct port of the visioncortex scanline algorithm, including its label
  /// recycling behavior (merging into the most recently issued label gives it
  /// back), so cluster order matches the original.
  BinaryClusters toClusters(bool diagonal) {
    final out = BinaryClusters();
    final clusters = <BinaryCluster>[];
    final w = width;
    final h = height;
    final src = pixels;
    final clustermap = Uint32List(w * h);
    var clusterindex = 0;

    int pixelSafe(int x, int y) =>
        (x < 0 || y < 0 || x >= w || y >= h) ? 0 : src[y * w + x];

    void combineCluster(int from, int to) {
      final fromCluster = clusters[from];
      for (final o in fromCluster.points) {
        clustermap[o.y * w + o.x] = to;
      }
      clusters[to].points.addAll(fromCluster.points);
      fromCluster.points.clear();
      clusters[to].rect.merge(fromCluster.rect);
      fromCluster.rect.clear();
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pos = PointI32(x, y);
        final v = src[y * w + x] != 0;
        final vUp = pixelSafe(x, y - 1) != 0;
        final vLeft = pixelSafe(x - 1, y) != 0;
        final vUpLeft = pixelSafe(x - 1, y - 1) != 0;
        var clusterUp = y > 0 ? clustermap[(y - 1) * w + x] : 0;
        var clusterLeft = x > 0 ? clustermap[y * w + x - 1] : 0;
        final clusterUpLeft = (x > 0 && y > 0) ? clustermap[(y - 1) * w + x - 1] : 0;

        if ((v || diagonal) && vUp && vLeft && clusterLeft != clusterUp) {
          if (clusters[clusterLeft].size <= clusters[clusterUp].size) {
            combineCluster(clusterLeft, clusterUp);
            if (clusterindex > 0 &&
                clusterLeft == clusterindex - 1 &&
                clusterindex == clusters.length) {
              clusterindex--;
            }
            clusterLeft = clusterUp;
          } else {
            combineCluster(clusterUp, clusterLeft);
            clusterUp = clusterLeft;
          }
        }

        if (v) {
          out.rect.addXY(x, y);
          if (vUp) {
            clustermap[y * w + x] = clusterUp;
            clusters[clusterUp].add(pos);
          } else if (vLeft) {
            clustermap[y * w + x] = clusterLeft;
            clusters[clusterLeft].add(pos);
          } else if (vUpLeft && diagonal) {
            clustermap[y * w + x] = clusterUpLeft;
            clusters[clusterUpLeft].add(pos);
          } else {
            final newCluster = BinaryCluster()..add(pos);
            if (clusterindex < clusters.length) {
              clusters[clusterindex] = newCluster;
            } else {
              clusters.add(newCluster);
            }
            clustermap[y * w + x] = clusterindex;
            clusterindex++;
          }
        }
      }
    }

    out.clusters = clusters.where((c) => c.size != 0).toList();
    return out;
  }
}

import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:visioncortex/visioncortex.dart';

void main() {
  test('BinaryImage clusters 3x3 isolated pixels', () {
    final image = BinaryImage.newWH(3, 3);
    image.setPixel(0, 0, true);
    image.setPixel(1, 1, true);
    image.setPixel(2, 2, true);
    final clusters = image.toClusters(false);
    expect(clusters.length, 3);
    expect(clusters.clusters[0].size, 1);
    expect(clusters.clusters[0].points[0], PointI32(0, 0));
    expect(clusters.clusters[1].points[0], PointI32(1, 1));
    expect(clusters.clusters[2].points[0], PointI32(2, 2));
    final bin = clusters.clusters[0].toBinaryImage();
    expect(bin.width, 1);
    expect(bin.height, 1);
    expect(bin.getPixel(0, 0), true);
  });

  test('BinaryImage clusters diagonal connectivity', () {
    final image = BinaryImage.newWH(3, 3);
    image.setPixel(0, 0, true);
    image.setPixel(1, 1, true);
    image.setPixel(2, 2, true);
    final clusters = image.toClusters(true);
    expect(clusters.length, 1);
    expect(clusters.clusters[0].size, 3);
  });

  test('BinaryImage clusters 4x4 block', () {
    final image = BinaryImage.newWH(4, 4);
    image.setPixel(1, 1, true);
    image.setPixel(1, 2, true);
    image.setPixel(2, 1, true);
    image.setPixel(2, 2, true);
    final clusters = image.toClusters(false);
    expect(clusters.length, 1);
    expect(clusters.clusters[0].size, 4);
    expect(clusters.clusters[0].rect.left, 1);
    expect(clusters.clusters[0].rect.top, 1);
    expect(clusters.clusters[0].rect.right, 3);
    expect(clusters.clusters[0].rect.bottom, 3);
  });

  test('PathWalker traces a square boundary with holes merged', () {
    // A 3x3 filled square: outer path should be a closed 4-corner ring.
    final image = BinaryImage.newWH(3, 3);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        image.setPixel(x, y, true);
      }
    }
    final paths = BinaryCluster.imageToPaths(image, PathSimplifyMode.none);
    expect(paths.length, 1);
    final path = paths[0];
    // Closed: first == last; corners only (5 points: 4 corners + repeat).
    expect(path.path.first, path.path.last);
    expect(path.length, 5);
  });

  test('imageToPaths emits hole boundaries', () {
    // 4x4 filled with a 2x2 hole in the middle.
    final image = BinaryImage.newWH(4, 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        image.setPixel(x, y, true);
      }
    }
    image.setPixel(1, 1, false);
    image.setPixel(2, 1, false);
    image.setPixel(1, 2, false);
    image.setPixel(2, 2, false);
    final paths = BinaryCluster.imageToPaths(image, PathSimplifyMode.none);
    expect(paths.length, 2); // outer + hole
  });

  test('color clustering of a two-color image', () {
    final image = ColorImage.newWH(4, 2);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        image.setPixel(x, y, const Color(255, 0, 0));
      }
      for (var x = 2; x < 4; x++) {
        image.setPixel(x, y, const Color(0, 0, 255));
      }
    }
    final clusters = ColorClustersRunner(
      RunnerConfig(goodMinArea: 0, goodMaxArea: 64, deepenDiff: 16),
      image,
    ).run();
    final view = clusters.view();
    expect(view.clustersOutput.length, 2);
    // The output color is the residue color (deepened children excluded).
    final colors = view.clustersOutput
        .map((i) => view.getCluster(i).residueColor())
        .toSet()
        .map((c) => (c.r, c.b))
        .toSet();
    expect(colors, {(255, 0), (0, 255)});
  });

  test('Schneider fit approximates a quarter circle', () {
    // Sample a quarter circle and fit; error should be tiny.
    final pts = <PointF64>[];
    const r = 100.0;
    for (var i = 0; i <= 20; i++) {
      final t = i / 20 * 1.5707963267948966;
      pts.add(PointF64(r * math.cos(t), r * math.sin(t)));
    }
    final curves = CurveFit.fitCurve(pts, 0.5)!;
    expect(curves.length, inInclusiveRange(1, 3));
    // Endpoints pinned.
    final c = curves.first;
    expect(c.$1.x, closeTo(pts.first.x, 1e-9));
    expect(c.$1.y, closeTo(pts.first.y, 1e-9));
    final last = curves.last;
    expect(last.$4.x, closeTo(pts.last.x, 1e-9));
    expect(last.$4.y, closeTo(pts.last.y, 1e-9));
  });

  test('limit_penalties collapses a straight staircase', () {
    final pts = <PointI32>[];
    // A diagonal staircase: (0,0),(1,0),(1,1),(2,1),(2,2)...
    for (var i = 0; i < 10; i++) {
      pts.add(PointI32(i, i));
      pts.add(PointI32(i + 1, i));
    }
    pts.add(PointI32(10, 10));
    final path = PathI32.fromPoints(pts);
    final simplified = PathSimplify.limitPenalties(path);
    expect(simplified.length, lessThan(pts.length));
  });

  test('SAT computes region sums', () {
    // Wikipedia example.
    final values = [
      31, 2, 4, 33, 5, 36, //
      12, 26, 9, 10, 29, 25, //
      13, 17, 21, 22, 20, 18, //
      24, 23, 15, 16, 14, 19, //
      30, 8, 28, 27, 11, 7, //
      1, 35, 34, 3, 32, 6,
    ];
    final image = ColorImage.newWH(6, 6);
    for (var i = 0; i < values.length; i++) {
      image.setPixel(i % 6, i ~/ 6, Color(values[i], values[i], values[i]));
    }
    final sat = SummedAreaTable.fromColorImage(image);
    expect(sat.getBotRightSum(0, 0), 31);
    expect(sat.getBotRightSum(1, 1), 71);
    expect(sat.getBotRightSum(5, 5), 666);
    expect(sat.getRegionSumXYWH(2, 3, 3, 2), 111);
    expect(sat.getRegionSumXYWH(0, 0, 6, 6), 666);
  });
}

import '../bound.dart';
import '../clusters.dart';
import '../color.dart';
import '../image/binary_image.dart';
import '../image/color_image.dart';
import '../path/compound.dart';
import '../path/simplify.dart';
import '../point.dart';
import 'container.dart';

/// A cluster of same-colored pixels in the color-cluster hierarchy.
class ColorCluster {
  final List<int> indices;
  final List<int> holes;
  int numHoles;
  int depth;
  ColorSum sum;
  ColorSum residueSum;
  BoundingRect rect;
  int mergedInto;

  ColorCluster()
      : indices = [],
        holes = [],
        numHoles = 0,
        depth = 0,
        sum = ColorSum(),
        residueSum = ColorSum(),
        rect = BoundingRect.zero(),
        mergedInto = 0;

  void add(int i, int r, int g, int b, int x, int y) {
    indices.add(i);
    sum.addChannels(r, g, b);
    rect.addXY(x, y);
  }

  int get area => indices.length;

  Color color() => sum.average();

  Color residueColor() => residueSum.average();

  int perimeter(ClustersView parent) {
    var count = 0;
    final image = toImageWithHole(parent.width, true);
    final w = image.width;
    final h = image.height;
    final px = image.pixels;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[y * w + x] != 0 &&
            (image.getPixelSafe(x - 1, y) == false ||
                image.getPixelSafe(x + 1, y) == false ||
                image.getPixelSafe(x, y - 1) == false ||
                image.getPixelSafe(x, y + 1) == false)) {
          count++;
        }
      }
    }
    return count;
  }

  BinaryImage toImage(ClustersView parent) =>
      toImageWithHole(parent.width, true);

  BinaryImage toImageWithHole(int parentWidth, bool hole) {
    final width = rect.width;
    final height = rect.height;
    final image = BinaryImage.newWH(width, height);

    for (final i in indices) {
      final x = (i % parentWidth) - rect.left;
      final y = (i ~/ parentWidth) - rect.top;
      image.setPixel(x, y, true);
    }

    if (hole) {
      for (final i in holes) {
        final x = (i % parentWidth) - rect.left;
        final y = (i ~/ parentWidth) - rect.top;
        image.setPixel(x, y, false);
      }
    }

    return image;
  }

  void renderToColorImage(ClustersView parent, ColorImage image) {
    renderToColorImageWithColor(parent, image, residueColor());
  }

  void renderToColorImageWithColor(
      ClustersView parent, ColorImage image, Color color) {
    for (final i in indices) {
      final x = i % parent.width;
      final y = i ~/ parent.width;
      image.setPixel(x, y, color);
    }
  }

  CompoundPath toCompoundPath(
    ClustersView parent,
    bool hole,
    PathSimplifyMode mode,
    double cornerThreshold,
    double lengthThreshold,
    int maxIterations,
    double spliceThreshold,
  ) {
    final paths = CompoundPath();
    for (final cluster
        in toImageWithHole(parent.width, hole).toClusters(false).clusters) {
      paths.append(BinaryCluster.imageToCompoundPath(
        PointI32(rect.left + cluster.rect.left, rect.top + cluster.rect.top),
        cluster.toBinaryImage(),
        mode,
        cornerThreshold,
        lengthThreshold,
        maxIterations,
        spliceThreshold,
      ));
    }
    return paths;
  }

  /// Live (not merged-away) neighbouring cluster indices, sorted. Uses a
  /// small list with linear dedup — neighbour counts are tiny, so this
  /// beats a hash set on the hot path.
  List<int> neighbours(ClustersView parent) {
    final myself = parent.getClusterAt(indices[0]);
    final neighbours = <int>[];

    final w = parent.width;
    final h = parent.height;
    final map = parent.clusterIndices;
    bool addIfNew(int index) {
      if (index != 0 && index != myself && !neighbours.contains(index)) {
        neighbours.add(index);
        return true;
      }
      return false;
    }

    for (final i in indices) {
      final y = i ~/ w;
      final x = i - y * w;

      if (y > 0) addIfNew(map[w * (y - 1) + x]);
      if (y < h - 1) addIfNew(map[w * (y + 1) + x]);
      if (x > 0) addIfNew(map[w * y + x - 1]);
      if (x < w - 1) addIfNew(map[w * y + x + 1]);
    }

    neighbours.sort();
    return neighbours;
  }
}

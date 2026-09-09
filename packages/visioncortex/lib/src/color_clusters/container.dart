import 'dart:typed_data';

import '../color.dart';
import '../image/color_image.dart';
import '../point.dart';
import 'cluster.dart';

/// Result of the color-clustering run: pixel data, cluster records, the
/// cluster index per pixel, and the ordered output list.
class ColorClusters {
  final int width;
  final int height;
  final Uint8List pixels;
  final List<ColorCluster> clusters;
  final Uint32List clusterIndices;

  /// Valid outputs: clusters with at least one pixel, ordered bottom-to-top
  /// paint order per the builder's emission (this list itself is
  /// top-to-bottom; consumers reverse it).
  final List<int> clustersOutput;

  ColorClusters({
    required this.width,
    required this.height,
    required this.pixels,
    required this.clusters,
    required this.clusterIndices,
    required this.clustersOutput,
  });

  ClustersView view() => ClustersView(
        width: width,
        height: height,
        pixels: pixels,
        clusters: clusters,
        clusterIndices: clusterIndices,
        clustersOutput: clustersOutput,
      );
}

/// Read-only view over [ColorClusters].
class ClustersView {
  final int width;
  final int height;
  final Uint8List pixels;
  final List<ColorCluster> clusters;
  final Uint32List clusterIndices;
  final List<int> clustersOutput;

  ClustersView({
    required this.width,
    required this.height,
    required this.pixels,
    required this.clusters,
    required this.clusterIndices,
    required this.clustersOutput,
  });

  ColorCluster getCluster(int index) => clusters[index];

  int getClusterAt(int index) => clusterIndices[index];

  int getClusterAtPoint(PointI32 point) =>
      clusterIndices[point.y * width + point.x];

  Color? getPixel(int x, int y) {
    if (x < 0 || y < 0 || x >= width) return null;
    final index = (y * width + x) * 4;
    if (index >= pixels.length) return null;
    return Color(pixels[index], pixels[index + 1], pixels[index + 2],
        pixels[index + 3]);
  }

  ColorImage toColorImage() {
    final image = ColorImage.newWH(width, height);
    for (final u in clustersOutput.reversed) {
      clusters[u].renderToColorImage(this, image);
    }
    return image;
  }
}

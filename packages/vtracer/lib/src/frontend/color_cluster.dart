import 'package:visioncortex/visioncortex.dart';

import '../error.dart';
import '../ir.dart';
import '../progress.dart';
import 'frontend.dart';
import 'keying.dart';

/// Hierarchical color-clustering frontend — the classic VTracer color path.
///
/// Speckle removal happens *inside* clustering, via `goodMinArea`: it is the
/// clusterer's deepen gate, so it decides whether a small/thin patch is
/// absorbed into its neighbor or kept as its own layer.
class ColorClusterFrontend extends Frontend {
  /// Bits of color precision dropped when comparing pixels (0 = full 8-bit).
  final int colorPrecisionLoss;

  /// Color difference between hierarchical gradient layers.
  final int layerDifference;

  /// Minimum area (px) for a patch to be a deepen candidate during
  /// clustering. Below it, patches are absorbed into their nearest-color
  /// neighbor.
  final int goodMinArea;

  ColorClusterFrontend({
    this.colorPrecisionLoss = 2,
    this.layerDifference = 16,
    this.goodMinArea = 0,
  });

  (ColorImage, RunnerConfig, int, int) _prepare(ColorImage img) {
    if (img.width == 0 || img.height == 0) {
      throw const EmptyImageError();
    }

    final width = img.width;
    final height = img.height;
    final keyed = img.clone();

    // Transparency keying (stacked mode discards the keyed background).
    // All-zero is the sentinel understood by the runner as "no keying".
    var keyColor = Color.zero();
    if (shouldKeyImage(keyed)) {
      keyColor = findUnusedColor(keyed);
      applyKey(keyed, keyColor);
    }

    final config = RunnerConfig(
      diagonal: layerDifference == 0,
      hierarchical: hierarchicalMax,
      batchSize: 25600,
      goodMinArea: goodMinArea,
      goodMaxArea: width * height,
      isSameColorA: colorPrecisionLoss,
      isSameColorB: 1,
      deepenDiff: layerDifference,
      hollowNeighbours: 1,
      keyColor: keyColor,
      keyingAction: KeyingAction.discard,
    );

    return (keyed, config, width, height);
  }

  static Segmentation segmentationFromClusters(
      ColorClusters clusters, int width, int height) {
    final view = clusters.view();
    final seg = Segmentation(width, height);
    // clustersOutput is top-to-bottom; reverse for bottom-to-top paint order.
    for (final clusterIndex in view.clustersOutput.reversed) {
      final cluster = view.getCluster(clusterIndex);
      // Solid cluster masks (no holes punched): stacked mode relies on
      // paint-order overdraw for occlusion.
      final image = cluster.toImageWithHole(view.width, false);
      seg.layers.add(Layer(
        Paint.solid(cluster.residueColor()),
        RegionMask(image, PointI32(cluster.rect.left, cluster.rect.top)),
      ));
    }
    return seg;
  }

  @override
  Segmentation segment(ColorImage img) {
    final (image, config, width, height) = _prepare(img);
    final clusters = ColorClustersRunner(config, image).run();
    return segmentationFromClusters(clusters, width, height);
  }

  @override
  Segmentation segmentWith(ColorImage img, Ctx ctx) {
    final (image, config, width, height) = _prepare(img);

    // Drive clustering incrementally to publish progress and observe
    // cancellation between batches.
    final builder = ColorClustersRunner(config, image).start();
    ctx.report(Phase.segment, 0.0);
    while (!builder.tick()) {
      ctx.check();
      ctx.report(Phase.segment, builder.progress() / 100.0);
    }
    ctx.check();
    final clusters = builder.result();
    ctx.report(Phase.segment, 1.0);

    return segmentationFromClusters(clusters, width, height);
  }

  @override
  Future<Segmentation> segmentWithAsync(ColorImage img, Ctx ctx) async {
    final (image, config, width, height) = _prepare(img);

    final builder = ColorClustersRunner(config, image).start();
    ctx.report(Phase.segment, 0.0);
    while (!builder.tick()) {
      ctx.check();
      ctx.report(Phase.segment, builder.progress() / 100.0);
      // Yield between batches so the enclosing UI can paint and react.
      await Future<void>.delayed(Duration.zero);
    }
    ctx.check();
    final clusters = builder.result();
    ctx.report(Phase.segment, 1.0);

    return segmentationFromClusters(clusters, width, height);
  }
}

import '../color.dart';
import '../image/color_image.dart';
import 'builder.dart';
import 'cluster.dart';
import 'container.dart';

class RunnerConfig {
  bool diagonal;
  int hierarchical;
  int batchSize;
  int goodMinArea;
  int goodMaxArea;
  int isSameColorA;
  int isSameColorB;
  int deepenDiff;
  int hollowNeighbours;
  Color keyColor;
  KeyingAction keyingAction;

  RunnerConfig({
    this.diagonal = false,
    this.hierarchical = hierarchicalMax,
    this.batchSize = 25600,
    this.goodMinArea = 16,
    this.goodMaxArea = 256 * 256,
    this.isSameColorA = 4,
    this.isSameColorB = 1,
    this.deepenDiff = 64,
    this.hollowNeighbours = 1,
    Color? keyColor,
    this.keyingAction = KeyingAction.keep,
  }) : keyColor = keyColor ?? Color.zero();
}

/// The color-cluster runner: assembles the vtracer predicates around
/// [ColorClustersBuilder].
class ColorClustersRunner {
  final RunnerConfig config;
  final ColorImage image;

  ColorClustersRunner(this.config, this.image);

  ColorClustersBuilder builder() {
    final conf = config;
    assert(conf.isSameColorA < 8);
    return ColorClustersBuilder(
      image: image,
      config: BuilderConfig(
        diagonal: conf.diagonal,
        hierarchical: conf.hierarchical,
        batchSize: conf.batchSize,
        key: conf.keyColor,
        keyingAction: conf.keyingAction,
      ),
      same: (ar, ag, ab, br, bg, bb) =>
          colorSameChannels(ar, ag, ab, br, bg, bb, conf.isSameColorA, conf.isSameColorB),
      diff: colorDiff,
      deepen: (view, patch, neighbours) =>
          patchGood(view, patch, conf.goodMinArea, conf.goodMaxArea) &&
          neighbours[0].diff > conf.deepenDiff,
      hollow: (view, patch, neighbours) =>
          neighbours.length <= conf.hollowNeighbours,
    );
  }

  IncrementalColorClustersBuilder start() => builder().start();

  ColorClusters run() => builder().run();
}

int colorDiff(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

bool colorSame(Color a, Color b, int shift, int thres) =>
    colorSameChannels(a.r, a.g, a.b, b.r, b.g, b.b, shift, thres);

bool colorSameChannels(
    int ar, int ag, int ab, int br, int bg, int bb, int shift, int thres) {
  final dr = ((ar >> shift) - (br >> shift)).abs();
  if (dr > thres) return false;
  final dg = ((ag >> shift) - (bg >> shift)).abs();
  if (dg > thres) return false;
  final db = ((ab >> shift) - (bb >> shift)).abs();
  return db <= thres;
}

bool patchGood(ClustersView view, ColorCluster patch, int goodMinArea, int goodMaxArea) {
  if (goodMinArea < patch.area && patch.area < goodMaxArea) {
    if (goodMinArea == 0 || patch.perimeter(view) < patch.area) {
      return true;
    } else {
      // cluster is thread-like and thinner than 2px
    }
  }
  return false;
}

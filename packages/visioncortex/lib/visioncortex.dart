/// Pure Dart port of the visioncortex primitives used by vtracer.
///
/// Only the modules the vtracer pipeline needs were ported:
/// * value types — [Color], [PointI32], [PointF64], [BoundingRect];
/// * images — [BinaryImage], [ColorImage], [SummedAreaTable];
/// * binary clustering — [BinaryCluster], [BinaryClusters];
/// * hierarchical color clustering — [ColorClustersRunner] and friends;
/// * path tracing — [PathI32], [PathF64], [Spline], path simplify/smooth;
/// * Schneider cubic fitting (ported from flo_curves).
library visioncortex;

export 'src/color.dart';
export 'src/point.dart';
export 'src/bound.dart';
export 'src/image/binary_image.dart';
export 'src/image/color_image.dart';
export 'src/image/sat.dart';
export 'src/clusters.dart';
export 'src/color_clusters/container.dart';
export 'src/color_clusters/cluster.dart';
export 'src/color_clusters/builder.dart';
export 'src/color_clusters/runner.dart';
export 'src/path/paths.dart';
export 'src/path/simplify.dart';
export 'src/path/smooth.dart';
export 'src/path/spline.dart';
export 'src/path/compound.dart';
export 'src/path/util.dart' show signedAreaI32;
export 'src/flo/fit.dart';

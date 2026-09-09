import 'paths.dart';
import 'spline.dart';

/// An element of a [CompoundPath].
sealed class CompoundPathElement {}

class CompoundPathI32 extends CompoundPathElement {
  final PathI32 path;
  CompoundPathI32(this.path);
}

class CompoundPathF64 extends CompoundPathElement {
  final PathF64 path;
  CompoundPathF64(this.path);
}

class CompoundPathSpline extends CompoundPathElement {
  final Spline spline;
  CompoundPathSpline(this.spline);
}

/// A collection of paths and splines representing a shape with holes.
class CompoundPath {
  final List<CompoundPathElement> elements = [];

  void addPathI32(PathI32 path) => elements.add(CompoundPathI32(path));
  void addPathF64(PathF64 path) => elements.add(CompoundPathF64(path));
  void addSpline(Spline spline) => elements.add(CompoundPathSpline(spline));

  void append(CompoundPath other) => elements.addAll(other.elements);

  bool get isEmpty => elements.isEmpty;
}

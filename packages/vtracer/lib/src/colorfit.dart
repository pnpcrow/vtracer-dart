import 'dart:math' as math;

import 'package:visioncortex/visioncortex.dart';

import 'ir.dart';

part 'colorfit/oklab.dart';
part 'colorfit/palette.dart';
part 'colorfit/quantize.dart';
part 'colorfit/merge.dart';

/// A color fitter rewrites the paints of a segmentation in place.
abstract class ColorFitter {
  void fit(Segmentation seg);
}

/// No-op fitter: paints keep the frontend's mean cluster colors.
class Identity implements ColorFitter {
  const Identity();

  @override
  void fit(Segmentation seg) {}
}

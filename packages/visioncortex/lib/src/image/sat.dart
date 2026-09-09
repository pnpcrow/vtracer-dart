import 'dart:typed_data';

import '../point.dart';
import 'color_image.dart';

/// Summed-area table over the grayscale intensity `(r+g+b)/3` of a
/// [ColorImage], for O(1) region sums.
class SummedAreaTable {
  final Uint32List sums;
  final int width;
  final int height;

  SummedAreaTable._(this.sums, this.width, this.height);

  static SummedAreaTable fromColorImage(ColorImage image) {
    final width = image.width;
    final height = image.height;
    final sums = Uint32List(width * height);
    final px = image.pixels;

    int sumAt(int x, int y) => (x >= 0 && y >= 0) ? sums[y * width + x] : 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final curr = (px[i] + px[i + 1] + px[i + 2]) ~/ 3;
        final upLeft = sumAt(x - 1, y - 1);
        final up = sumAt(x, y - 1);
        final left = sumAt(x - 1, y);
        sums[y * width + x] = up + left + curr - upLeft;
      }
    }

    return SummedAreaTable._(sums, width, height);
  }

  int getBotRightSum(int x, int y) {
    if (x >= 0 && y >= 0 && x < width && y < height) {
      return sums[y * width + x];
    }
    return 0;
  }

  int getRegionSumTopLeftBotRight(PointI32 topLeft, PointI32 botRight) {
    final leftRegion = getBotRightSum(topLeft.x - 1, botRight.y);
    final upRegion = getBotRightSum(botRight.x, topLeft.y - 1);
    final overlap = getBotRightSum(topLeft.x - 1, topLeft.y - 1);
    final total = getBotRightSum(botRight.x, botRight.y);
    return total + overlap - leftRegion - upRegion;
  }

  int getRegionSumXYWH(int x, int y, int w, int h) {
    return getRegionSumTopLeftBotRight(
      PointI32(x, y),
      PointI32(x + w - 1, y + h - 1),
    );
  }
}

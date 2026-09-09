import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final w = 1600, h = 1200;
  final image = img.Image(width: w, height: h);
  final rng = math.Random(42);
  for (var y = 0; y < h; y++) {
    final t = y / h;
    for (var x = 0; x < w; x++) {
      final n = (rng.nextDouble() - 0.5) * 12;
      image.setPixelRgb(
        x, y,
        ((40 + 150 * t) + n).clamp(0, 255).round(),
        ((160 - 80 * t) + n).clamp(0, 255).round(),
        ((230 - 90 * t) + n).clamp(0, 255).round(),
      );
    }
  }
  for (var i = 0; i < 25; i++) {
    final cx = rng.nextInt(w), cy = rng.nextInt(h);
    final r = 20 + rng.nextInt(90);
    final cr = rng.nextInt(256), cg = rng.nextInt(256), cb = rng.nextInt(256);
    for (var y = (cy - r).clamp(0, h - 1); y < (cy + r).clamp(0, h - 1); y++) {
      for (var x = (cx - r).clamp(0, w - 1); x < (cx + r).clamp(0, w - 1); x++) {
        if (math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) < r) {
          image.setPixelRgb(x, y, cr, cg, cb);
        }
      }
    }
  }
  File('../../testdata/big.png').writeAsBytesSync(img.encodePng(image));
  print('wrote ${w}x${h}');
}

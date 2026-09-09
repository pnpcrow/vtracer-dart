import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  // A colorful synthetic scene: gradient sky, sun, mountains.
  final w = 320, h = 240;
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    final t = y / h;
    final r = (60 + 120 * t).round();
    final g = (140 - 60 * t).round();
    final b = (220 - 80 * t).round();
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  // Sun.
  const cx = 250, cy = 60;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) < 30) {
        image.setPixelRgb(x, y, 255, 220, 60);
      }
    }
  }
  // Mountains.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final h1 = 120 + 60 * math.sin(x * 0.02) + 30 * math.sin(x * 0.05 + 1.0);
      final h2 = 150 + 50 * math.sin(x * 0.013 + 2.0);
      if (y > h2) {
        image.setPixelRgb(x, y, 70, 60, 80);
      } else if (y > h1) {
        image.setPixelRgb(x, y, 90, 110, 70);
      }
    }
  }
  final png = img.encodePng(image);
  File('../../testdata/scene.png').writeAsBytesSync(png);
  print('wrote testdata/scene.png (${png.length} bytes)');

  // A black/white line-art image.
  final bw = img.Image(width: 200, height: 200);
  for (var y = 0; y < 200; y++) {
    for (var x = 0; x < 200; x++) {
      bw.setPixelRgb(x, y, 255, 255, 255);
    }
  }
  // Circle outline.
  for (var a = 0; a < 360; a++) {
    final rad = a * math.pi / 180;
    for (var t = 95; t <= 100; t++) {
      final x = (100 + t * math.cos(rad)).round();
      final y = (100 + t * math.sin(rad)).round();
      if (x >= 0 && x < 200 && y >= 0 && y < 200) {
        bw.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
  // Diagonal stroke.
  for (var i = 20; i < 180; i++) {
    for (var t = 0; t < 6; t++) {
      bw.setPixelRgb(i + t, i, 0, 0, 0);
    }
  }
  final bwPng = img.encodePng(bw);
  File('../../testdata/linework.png').writeAsBytesSync(bwPng);
  print('wrote testdata/linework.png (${bwPng.length} bytes)');
}

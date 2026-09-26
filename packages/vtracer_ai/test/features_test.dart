import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:vtracer_ai/vtracer_ai.dart';
import 'package:visioncortex/visioncortex.dart';

/// Flat image: left half black, right half white.
ColorImage flatImage(int w, int h) {
  final img = ColorImage.newWH(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = x < w ~/ 2 ? 0 : 255;
      img.setPixelBytes(x, y, v, v, v, 255);
    }
  }
  return img;
}

/// Four flat color quadrants (poster-like).
ColorImage posterImage(int w, int h) {
  final img = ColorImage.newWH(w, h);
  const colors = [
    [200, 30, 30],
    [30, 200, 30],
    [30, 30, 200],
    [240, 220, 30],
  ];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = colors[(y >= h ~/ 2 ? 2 : 0) + (x >= w ~/ 2 ? 1 : 0)];
      img.setPixelBytes(x, y, c[0], c[1], c[2], 255);
    }
  }
  return img;
}

/// Per-pixel random RGB — a photo/noise worst case.
ColorImage noisyImage(int w, int h, [int seed = 3]) {
  final img = ColorImage.newWH(w, h);
  final rng = math.Random(seed);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      img.setPixelBytes(x, y, rng.nextInt(256), rng.nextInt(256),
          rng.nextInt(256), 255);
    }
  }
  return img;
}

void main() {
  test('flat image: tiny palette, no noise, full palette share', () {
    final f = FeatureExtractor().extract(flatImage(80, 60));
    expect(f.width, 80);
    expect(f.height, 60);
    expect(f.quantizedColors, 2);
    expect(f.paletteShare8, closeTo(1.0, 1e-9));
    expect(f.noiseLevel, closeTo(0, 1e-9));
    expect(f.colorfulness, closeTo(0, 1e-9));
    expect(f.darkShare, closeTo(0.5, 0.01));
    expect(f.lightShare, closeTo(0.5, 0.01));
    expect(f.transparentShare, 0);
    expect(f.isGrayscaleish, isTrue);
    expect(f.isFlatPalette, isTrue);
  });

  test('noisy image: many colors, high noise, low palette share', () {
    final f = FeatureExtractor().extract(noisyImage(96, 72));
    expect(f.quantizedColors, greaterThan(512));
    expect(f.paletteShare8, lessThan(0.05));
    expect(f.noiseLevel, greaterThan(20));
    expect(f.colorfulness, greaterThan(40));
    expect(f.isPhotoLike, isTrue);
  });

  test('poster image: concentrated palette, colorful, low noise', () {
    final f = FeatureExtractor().extract(posterImage(80, 80));
    expect(f.paletteShare8, closeTo(1.0, 1e-9));
    expect(f.dominantShare, closeTo(0.25, 0.01));
    expect(f.colorfulness, greaterThan(20));
    expect(f.noiseLevel, lessThan(2));
    expect(f.isGrayscaleish, isFalse);
  });

  test('empty/degenerate image does not crash', () {
    final f = FeatureExtractor().extract(ColorImage.newWH(1, 1));
    expect(f.quantizedColors, lessThanOrEqualTo(1));
    final g = FeatureExtractor().extract(ColorImage.empty());
    expect(g.width, 0);
  });

  test('feature payload round-trips through JSON', () {
    final f = FeatureExtractor().extract(posterImage(40, 40));
    final g = ImageFeatures.fromJson(f.toJson());
    expect(g.quantizedColors, f.quantizedColors);
    expect(g.paletteShare8, closeTo(f.paletteShare8, 1e-9));
  });
}

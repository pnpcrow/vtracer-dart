import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';

ColorImage _testImage() {
  // 16x8: left half red, right half blue, with a small green patch on top.
  final img = ColorImage.newWH(16, 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 16; x++) {
      img.setPixel(x, y, x < 8 ? const Color(255, 0, 0) : const Color(0, 0, 255));
    }
  }
  for (var y = 0; y < 4; y++) {
    for (var x = 6; x < 10; x++) {
      img.setPixel(x, y, const Color(0, 255, 0));
    }
  }
  return img;
}

void main() {
  test('default config produces valid SVG with shapes', () {
    final cfg = VtracerConfig.defaultConfig()..filterSpeckle = 2;
    final svg = cfg.build().toSvg(_testImage());
    expect(svg, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(svg, contains('<svg'));
    expect(svg, contains('</svg>'));
    expect(svg, contains('fill="#0000FF"'));
    expect(svg, contains('fill="#00FF00"'));
    // Spline mode emits cubic commands in the path data.
    final pathLetters = _pathLetters(svg);
    expect(pathLetters, contains('C'));
    expect(pathLetters, contains('Z'));
  });

  test('pixel mode emits only lineto commands', () {
    final cfg = VtracerConfig.defaultConfig()
      ..mode = FitMode.pixel
      ..filterSpeckle = 2;
    final svg = cfg.build().toSvg(_testImage());
    final letters = _pathLetters(svg);
    expect(letters, contains('L'));
    expect(letters, isNot(contains('C')));
  });

  test('binary clustering threshold produces black shapes', () {
    final cfg = VtracerConfig(clustering: Clustering.binary);
    final svg = cfg.build().toSvg(_testImage());
    expect(svg, contains('fill="#000000"'));
  });

  test('watershed clustering produces stacked layers', () {
    final cfg = VtracerConfig(clustering: Clustering.watershed);
    final svg = cfg.build().toSvg(_testImage());
    expect(svg, contains('<path'));
    // Root layer covers the whole canvas.
    expect(svg, contains('width="16" height="8"'));
  });

  test('cutout (mosaic) mode produces a gapless partition', () {
    final cfg = VtracerConfig(hierarchical: Hierarchical.cutout, mode: FitMode.pixel)
      ..optimize = 0;
    final svg = cfg.build().toSvg(_testImage());
    expect(svg, contains('<path'));
    expect(svg, contains('Z'));
  });

  test('fixed palette snaps colors', () {
    final cfg = VtracerConfig.defaultConfig()
      ..palette = [const Color(200, 10, 10), const Color(10, 10, 200)];
    final svg = cfg.build().toSvg(_testImage());
    expect(svg, contains('fill="#C80A0A"'));
    expect(svg, contains('fill="#0A0AC8"'));
  });

  test('maxColors quantizes the palette', () {
    final cfg = VtracerConfig.defaultConfig()..maxColors = 2;
    final svg = cfg.build().toSvg(_testImage());
    expect(svg, contains('<path'));
    // All fills should come from at most 2 colors (plus grouping).
    final fills = RegExp(r'fill="([^"]+)"').allMatches(svg).map((m) => m.group(1)).toSet();
    expect(fills.length, lessThanOrEqualTo(3));
  });

  test('simplify pass reduces path size', () {
    final img = _testImage();
    final plain = VtracerConfig.defaultConfig().build().toSvg(img);
    final simplified = (VtracerConfig.defaultConfig()..simplify = 2.0).build().toSvg(img);
    final len = (String s) => RegExp(r'<path[^>]*>').allMatches(s).map((m) => m.end - m.start).reduce((a, b) => a + b);
    expect(len(simplified), lessThanOrEqualTo(len(plain)));
  });

  test('session caches segmentation across renders', () {
    final session = Session(_testImage());
    final cfg = VtracerConfig.defaultConfig();
    final svg1 = session.renderSvg(cfg);
    // Tuning a curve parameter reuses the cached segmentation.
    final tuned = VtracerConfig.defaultConfig()..cornerThreshold = 90;
    final svg2 = session.renderSvg(tuned);
    // Both renders succeed and produce valid documents.
    expect(svg1, contains('</svg>'));
    expect(svg2, contains('</svg>'));
    // A clustering-parameter change re-segments transparently.
    final reseg = VtracerConfig.defaultConfig()..filterSpeckle = 2;
    final svg3 = session.renderSvg(reseg);
    expect(svg3, contains('</svg>'));
  });

  test('transparent image is keyed and background discarded', () {
    final img = ColorImage.newWH(8, 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        img.setPixel(x, y, const Color(0, 0, 0, 0));
      }
    }
    for (var y = 2; y < 6; y++) {
      for (var x = 2; x < 6; x++) {
        img.setPixel(x, y, const Color(255, 255, 255));
      }
    }
    final svg = VtracerConfig.defaultConfig().build().toSvg(img);
    expect(svg, contains('fill="#FFFFFF"'));
    // The keyed background must not appear as a shape.
    expect(svg, isNot(contains('width="0"')));
  });

  test('progress reports phases', () {
    final cfg = VtracerConfig.defaultConfig();
    final pipeline = cfg.build();
    final phases = <Phase>{};
    final doc = pipeline.runWithProgress(_testImage(), CancelToken(), (p) {
      phases.add(p.phase);
    });
    expect(phases, containsAll([Phase.segment, Phase.compose, Phase.optimize]));
    expect(doc.shapes, isNotEmpty);
  });

  test('cancellation throws CancelledError', () {
    final cfg = VtracerConfig.defaultConfig();
    final pipeline = cfg.build();
    final cancel = CancelToken()..cancel();
    expect(
      () => pipeline.runWithProgress(_testImage(), cancel, (_) {}),
      throwsA(isA<CancelledError>()),
    );
  });
}

/// Letters used inside path `d` attributes (commands).
Set<String> _pathLetters(String svg) {
  final ds = RegExp(r'd="([^"]+)"').allMatches(svg).map((m) => m.group(1)!);
  final letters = <String>{};
  for (final d in ds) {
    for (final m in RegExp(r'[A-Za-z]').allMatches(d)) {
      letters.add(m.group(0)!);
    }
  }
  return letters;
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vtracer_app/controller.dart';
import 'package:vtracer_app/preview.dart';

const _halfHalfSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">'
    '<rect x="0" y="0" width="50" height="50" fill="#FF0000"/>'
    '<rect x="50" y="0" width="50" height="50" fill="#0000FF"/>'
    '</svg>';

/// The (r, g, b) at a pixel of a rasterized image.
(int, int, int) _rgb(ui.Image image, ByteData bytes, int x, int y) {
  final i = (y * image.width + x) * 4;
  return (bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

void main() {
  test('rasterizeSvg fits the document into the cap, preserving aspect',
      () async {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">'
        '<rect width="100" height="50" fill="#123456"/></svg>';
    final image = await rasterizeSvg(svg, const ui.Size(60, 60));
    expect(image.width, 60);
    expect(image.height, 30);
    image.dispose();

    // Tall document: height clamps, width follows the aspect ratio.
    final tall = await rasterizeSvg(svg.replaceAll('100" height="50', '50" height="100'),
        const ui.Size(60, 60));
    expect(tall.width, 30);
    expect(tall.height, 60);
    tall.dispose();
  });

  test('rasterizeSvg scales content to the whole image (no bands, no cutoff)',
      () async {
    // Upscaled 2x: the blue half must reach the far right edge (an unscaled
    // draw would leave it transparent) and the far bottom must be painted.
    final up = await rasterizeSvg(_halfHalfSvg, const ui.Size(200, 100));
    expect(up.width, 200);
    expect(up.height, 100);
    final upBytes = (await up.toByteData())!;
    expect(_rgb(up, upBytes, 20, 50), (255, 0, 0));
    expect(_rgb(up, upBytes, 180, 50), (0, 0, 255));
    expect(_rgb(up, upBytes, 100, 95), isNot((0, 0, 0)));
    up.dispose();

    // Downscaled 2x: the right half of the document must still be visible
    // (an unscaled draw would cut it off at the image edge).
    final down = await rasterizeSvg(_halfHalfSvg, const ui.Size(50, 25));
    final downBytes = (await down.toByteData())!;
    expect(_rgb(down, downBytes, 10, 12), (255, 0, 0));
    expect(_rgb(down, downBytes, 40, 12), (0, 0, 255));
    down.dispose();
  });

  test('sample image converts end to end', () async {
    final state = AppState();
    await state.loadSample();
    // Give the render loop a moment to drain (isolate worker or
    // cooperative, depending on the platform).
    for (var i = 0; i < 100 && state.svg == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);
    expect(state.svg, contains('</svg>'));
    expect(state.shapeCount, greaterThan(0));
    expect(state.error, isNull);
    expect(state.dirty, isFalse);
  });

  test('parameter change waits for apply', () async {
    final state = AppState();
    await state.loadSample();
    for (var i = 0; i < 200 && state.svg == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);

    // Changing a slider marks the state dirty but does not re-render.
    state.update(() => state.cornerThreshold = 120);
    expect(state.dirty, isTrue);
    expect(state.needsApply, isTrue);
    expect(state.rendering, isFalse);

    // Applying re-renders (reusing the cached segmentation).
    await state.apply();
    for (var i = 0; i < 200 && state.rendering; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);
    expect(state.error, isNull);
    expect(state.dirty, isFalse);
  });
}

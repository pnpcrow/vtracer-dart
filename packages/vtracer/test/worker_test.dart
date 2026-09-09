import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer/worker.dart';

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

ColorImage _noisyImage({int w = 400, int h = 300}) {
  // Enough work that cancellation lands mid render.
  final img = ColorImage.newWH(w, h);
  var seed = 123456789;
  int rnd() {
    seed = (1103515245 * seed + 12345) & 0x7fffffff;
    return seed;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      img.setPixelBytes(x, y, rnd() & 0xff, rnd() & 0xff, rnd() & 0xff, 255);
    }
  }
  return img;
}

void main() {
  test('worker renders the same SVG as an in-process session', () async {
    final image = _testImage();
    final expected = Session(image).renderSvg(VtracerConfig.defaultConfig());

    final worker = await startVtracerWorker(image);
    addTearDown(worker.dispose);
    final svg = await worker.renderSvg(VtracerConfig.defaultConfig());
    expect(svg, expected);
  });

  test('cached segmentation is reused across renders', () async {
    final worker = await startVtracerWorker(_testImage());
    addTearDown(worker.dispose);

    final cfg = VtracerConfig.defaultConfig();
    await worker.renderSvg(cfg);
    final svg = await worker.renderSvg(cfg..cornerThreshold = 90);
    expect(svg, contains('<path'));
    expect(svg, contains('</svg>'));
  });

  test('progress is reported and reaches 100%', () async {
    final worker = await startVtracerWorker(_noisyImage(w: 200, h: 150));
    addTearDown(worker.dispose);

    final phases = <Phase>{};
    await worker.renderSvg(VtracerConfig.defaultConfig(),
        onProgress: (p) => phases.add(p.phase));
    expect(phases, contains(Phase.segment));
  });

  test('cancel aborts an in-flight render', () async {
    final worker = await startVtracerWorker(_noisyImage());
    addTearDown(worker.dispose);

    final render = worker.renderSvg(VtracerConfig.defaultConfig());
    worker.cancel();
    await expectLater(render, throwsA(isA<CancelledError>()));
  });

  test('superseding render cancels the previous one', () async {
    final worker = await startVtracerWorker(_noisyImage());
    addTearDown(worker.dispose);

    final first = worker.renderSvg(VtracerConfig.defaultConfig());
    final second = worker.renderSvg(VtracerConfig(clustering: Clustering.binary));
    await expectLater(first, throwsA(isA<CancelledError>()));
    expect(await second, contains('<path'));
  });

  test('render after dispose throws', () async {
    final worker = await startVtracerWorker(_testImage());
    await worker.dispose();
    expect(() => worker.renderSvg(VtracerConfig.defaultConfig()),
        throwsStateError);
  });

  test('worker error surfaces to the caller', () async {
    // A zero-sized image makes the frontend throw EmptyImageError, which the
    // worker forwards through the error channel.
    final bad = await startVtracerWorker(ColorImage(Uint8List(0), 0, 0));
    try {
      await bad.renderSvg(VtracerConfig.defaultConfig());
      fail('expected an error');
    } catch (e) {
      expect(e, isA<StateError>());
      expect(e.toString(), contains('empty'));
    } finally {
      await bad.dispose();
    }
  });
}

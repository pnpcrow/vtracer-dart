import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:vtracer/vtracer.dart';
import 'package:visioncortex/visioncortex.dart';

/// Stage-level benchmark for the vectorization pipeline.
///
/// Times a fresh conversion, the session-cached re-render (curve-parameter
/// change only), and a breakdown of the color-cluster frontend internals
/// (keying, clustering stage 1/2, mask building) plus the downstream stages
/// (finish / SVG write).
///
/// ```bash
/// dart run packages/vtracer_cli/bin/bench.dart [image ...]
/// ```
void main(List<String> args) async {
  final paths = args.isNotEmpty
      ? args
      : ['testdata/scene.png', 'testdata/linework.png', 'testdata/big.png'];

  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('skipping $path (not found)');
      continue;
    }
    final image = decodePngOrJpeg(file.readAsBytesSync(), path);
    await benchImage(path, image);
    stdout.writeln();
  }

  stdout.writeln('--- synthetic noisy photo (worst case for clustering) ---');
  await benchImage('synthetic-noisy-800x600', noisyPhoto(800, 600));
}

Future<void> benchImage(String label, ColorImage image) async {
  final cfg = VtracerConfig.defaultConfig();
  stdout.writeln('== $label (${image.width}x${image.height}) ==');

  // Warm-up (JIT) + measured fresh conversions.
  final fresh = <int>[];
  for (var i = 0; i <= 2; i++) {
    final sw = Stopwatch()..start();
    cfg.build().toSvg(image);
    sw.stop();
    if (i > 0) fresh.add(sw.elapsedMilliseconds);
  }
  stdout.writeln(
      'fresh convert      : ${fresh.join('/')} ms (median ${_median(fresh)})');

  // Session: first render (segments) then a curve-only re-render (cached).
  final session = Session(image);
  final sw = Stopwatch()..start();
  session.renderSvg(cfg);
  sw.stop();
  final first = sw.elapsedMilliseconds;

  sw..reset()..start();
  session.renderSvg(cfg..cornerThreshold = 90);
  sw.stop();
  final cached = sw.elapsedMilliseconds;
  stdout.writeln('session first/cached: $first / $cached ms');

  // Stage breakdown of the default color-cluster pipeline.
  benchStages(image, cfg);
}

void benchStages(ColorImage image, VtracerConfig cfg) {
  final pipeline = cfg.build();

  // --- frontend internals (replicates ColorClusterFrontend._prepare) -------
  var sw = Stopwatch()..start();
  final keyed = image.clone();
  var keyColor = Color.zero();
  if (shouldKeyImage(keyed)) {
    keyColor = findUnusedColor(keyed);
    applyKey(keyed, keyColor);
  }
  sw.stop();
  final tPrepare = sw.elapsedMilliseconds;

  final width = image.width, height = image.height;
  final config = RunnerConfig(
    diagonal: cfg.layerDifference == 0,
    hierarchical: hierarchicalMax,
    batchSize: 25600,
    goodMinArea: cfg.speckleArea(),
    goodMaxArea: width * height,
    isSameColorA: 8 - cfg.colorPrecision,
    isSameColorB: 1,
    deepenDiff: cfg.layerDifference,
    hollowNeighbours: 1,
    keyColor: keyColor,
    keyingAction: KeyingAction.discard,
  );

  // Cluster with a stage1/stage2 split, inferred from builder progress
  // (stage 1 reports 0..50, stage 2 reports 50..100).
  final builder = ColorClustersRunner(config, keyed).start();
  var tStage1 = 0, tStage2 = 0;
  sw..reset()..start();
  while (!builder.tick()) {
    sw.stop();
    if (builder.progress() < 50) {
      tStage1 += sw.elapsedMilliseconds;
    } else {
      tStage2 += sw.elapsedMilliseconds;
    }
    sw..reset()..start();
  }
  sw.stop();
  if (builder.progress() < 50) {
    tStage1 += sw.elapsedMilliseconds;
  } else {
    tStage2 += sw.elapsedMilliseconds;
  }
  final tCluster = tStage1 + tStage2;
  final clusters = builder.result();
  stdout.writeln(
      '  prepare $tPrepare ms | cluster $tCluster ms '
      '(stage1 $tStage1 / stage2 $tStage2, '
      '${clusters.clustersOutput.length} layers)');

  sw..reset()..start();
  final seg = ColorClusterFrontend.segmentationFromClusters(clusters, width, height);
  sw.stop();
  final tMasks = sw.elapsedMilliseconds;

  sw..reset()..start();
  final doc = pipeline.finish(seg);
  sw.stop();
  final tFinish = sw.elapsedMilliseconds;

  sw..reset()..start();
  pipeline.writer.write(doc);
  sw.stop();
  final tWrite = sw.elapsedMilliseconds;

  stdout.writeln(
      '  masks $tMasks ms | finish $tFinish ms | write $tWrite ms');
}

num _median(List<int> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

ColorImage decodePngOrJpeg(Uint8List bytes, String path) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('could not decode $path');
  }
  final rgba = decoded.convert(numChannels: 4);
  return ColorImage(
    Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba)),
    rgba.width,
    rgba.height,
  );
}

/// A photographic-style gradient with per-pixel noise: the clustering worst
/// case (hundreds of thousands of provisional clusters before merging).
ColorImage noisyPhoto(int w, int h) {
  final image = ColorImage.newWH(w, h);
  final rng = math.Random(42);
  for (var y = 0; y < h; y++) {
    final t = y / h;
    for (var x = 0; x < w; x++) {
      final n = (rng.nextDouble() - 0.5) * 48;
      image.setPixelBytes(
        x,
        y,
        (60 + 120 * t + n).clamp(0, 255).round(),
        (140 - 80 * t + n).clamp(0, 255).round(),
        (220 - 60 * t + n).clamp(0, 255).round(),
        255,
      );
    }
  }
  return image;
}

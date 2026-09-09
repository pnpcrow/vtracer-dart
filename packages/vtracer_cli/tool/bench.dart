import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:vtracer/vtracer.dart';

ColorImage readImage(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes)!.convert(numChannels: 4);
  return ColorImage(
    Uint8List.fromList(decoded.getBytes(order: img.ChannelOrder.rgba)),
    decoded.width,
    decoded.height,
  );
}

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : '../../testdata/scene.png';
  final image = readImage(path);
  print('image: ${image.width}x${image.height} (${image.width * image.height} px)');

  // Warmup JIT.
  VtracerConfig.defaultConfig().build().toSvg(image);

  for (final entry in [
    ('default (color-cluster/spline/stacked)', VtracerConfig.defaultConfig()),
    ('cutout', VtracerConfig.defaultConfig()..hierarchical = Hierarchical.cutout),
    ('watershed', VtracerConfig(clustering: Clustering.watershed)),
    ('binary', VtracerConfig(clustering: Clustering.binary)),
    ('poster+simplify', VtracerConfig.fromPreset(Preset.poster)..simplify = 2.0),
  ]) {
    final sw = Stopwatch()..start();
    final svg = entry.$2.build().toSvg(image);
    sw.stop();
    print('${entry.$1}: ${sw.elapsedMilliseconds}ms, ${(svg.length / 1024).toStringAsFixed(1)} KB');
  }
}

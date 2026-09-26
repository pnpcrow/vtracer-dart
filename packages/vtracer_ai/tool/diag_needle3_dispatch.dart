import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:vtracer_ai/vtracer_ai.dart';
import 'package:visioncortex/visioncortex.dart';

/// Diagnostic: run the embedded Needle3 engine against the real testdata
/// images and dump the RAW engine response (dispatched vs suppressed, the
/// grounding validation verdict, confidence) for each.
Future<void> main() async {
  final root = Directory.current.path;
  final engine = '$root/apps/vtracer_app/assets/needle3/needle.exe';
  final model = '$root/apps/vtracer_app/assets/needle3/needle3.cact';

  for (final name in ['scene.png', 'linework.png']) {
    final bytes = File('$root/testdata/$name').readAsBytesSync();
    final decoded = img.decodeImage(bytes)!;
    final rgba = decoded.convert(numChannels: 4);
    final image = ColorImage(
      rgba.getBytes(order: img.ChannelOrder.rgba),
      rgba.width,
      rgba.height,
    );
    final features = FeatureExtractor().extract(image);
    const goal = TuningGoal.balanced;
    final prompts = DecisionTemplates.promptsFor(
        PromptProfile.compact, features, goal);

    final dir = await Directory.systemTemp.createTemp('needle3_diag');
    final toolsFile = File('${dir.path}/tools.json');
    final systemFile = File('${dir.path}/system.txt');
    await toolsFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert([prompts.tool]));
    await systemFile.writeAsString(prompts.system);

    final sw = Stopwatch()..start();
    final result = await Process.run(engine, [
      '--model', model,
      '--tools', toolsFile.path,
      '--system', systemFile.path,
      '--max', '1024',
      '--prompt', prompts.prompt,
    ], stdoutEncoding: utf8, stderrEncoding: utf8);
    sw.stop();
    await dir.delete(recursive: true);

    final body = jsonDecode(result.stdout as String) as Map<String, Object?>;
    stdout.writeln('=== $name '
        '(${features.quantizedColors} colors, noise ${features.noiseLevel.toStringAsFixed(1)}, '
        'palette8 ${features.paletteShare8.toStringAsFixed(2)}) '
        '${sw.elapsedMilliseconds} ms ===');
    stdout.writeln('success:     ${body['success']}  error: ${body['error']}');
    stdout.writeln('confidence:  ${body['confidence']}');
    stdout.writeln('dispatched:  ${(body['function_calls'] as List).length}  '
        'suppressed: ${(body['suppressed_calls'] as List).length}');
    final calls = body['function_calls'] as List;
    if (calls.isNotEmpty) {
      stdout.writeln('args:        ${jsonEncode((calls.first as Map)['arguments'])}');
    }
    final suppressed = body['suppressed_calls'] as List;
    if (suppressed.isNotEmpty) {
      stdout.writeln('suppressed:  ${jsonEncode((suppressed.first as Map)['arguments'])}');
    }
    stdout.writeln('validation:  ${jsonEncode(body['validation'])}');
  }
}

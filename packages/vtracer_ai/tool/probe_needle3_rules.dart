import 'dart:convert';
import 'dart:io';

import 'package:vtracer_ai/vtracer_ai.dart';

/// Try a rule-guided compact system prompt across three image types and
/// report grounded-call rate and argument quality.
Future<void> main() async {
  const photo = ImageFeatures(
    width: 1920, height: 1080, megapixels: 2.07, aspectRatio: 1.78,
    quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
    edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
    colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
    darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
  );
  const flat = ImageFeatures(
    width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
    quantizedColors: 15, paletteShare8: 0.87, dominantShare: 0.4,
    edgeDensity: 0.05, meanGradient: 6, flatShare: 0.9, noiseLevel: 0.4,
    colorfulness: 30, transparentShare: 0, luminanceSpread: 180,
    darkShare: 0.1, lightShare: 0.2, backgroundUniformity: 4,
  );
  const lineArt = ImageFeatures(
    width: 800, height: 600, megapixels: 0.48, aspectRatio: 1.33,
    quantizedColors: 4, paletteShare8: 0.99, dominantShare: 0.6,
    edgeDensity: 0.15, meanGradient: 20, flatShare: 0.8, noiseLevel: 0.2,
    colorfulness: 2, transparentShare: 0, luminanceSpread: 255,
    darkShare: 0.45, lightShare: 0.5, backgroundUniformity: 1.5,
  );

  const goal = TuningGoal.balanced;
  final ruleSystem = '''
You configure an image-to-vector converter. From the image stats, call
propose_vtracer_parameters exactly once with every field inside its range.
Set max_colors or simplify to null unless the goal needs them. Then stop.

Decision rules:
- Photo: quantized_colors > 96 and palette_share_top8 < 0.55 ->
  clustering color-cluster, color_precision 8, layer_difference 32-64,
  filter_speckle 4-12, corner_threshold 120-180, fit_mode spline.
- Flat art: palette_share_top8 > 0.75 and quantized_colors <= 64 ->
  clustering color-cluster, color_precision 6-8, layer_difference 12-24,
  filter_speckle 2-4, hierarchical cutout.
- Line art: colorfulness < 14 and dark_share + light_share > 0.55 ->
  clustering binary, fit_mode spline, filter_speckle 1-3.
''';

  Object? stripDescriptions(Object? node) {
    if (node is Map<String, Object?>) {
      final out = <String, Object?>{};
      node.forEach((k, v) {
        if (k == 'description') return;
        out[k] = stripDescriptions(v);
      });
      return out;
    }
    if (node is List<Object?>) return node.map(stripDescriptions).toList();
    return node;
  }

  final compactTool =
      stripDescriptions(DecisionTemplates.toolDefinition(goal)) as Map<String, Object?>;

  for (final entry in {'photo': photo, 'flat': flat, 'lineArt': lineArt}.entries) {
    final payload =
        'goal: ${goal.name}\nimage_features: ${jsonEncode(entry.value.toPromptPayload())}';
    final dir = await Directory.systemTemp.createTemp('needle3_rl');
    final toolsFile = File('${dir.path}/tools.json');
    final systemFile = File('${dir.path}/system.txt');
    await toolsFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert([compactTool]));
    await systemFile.writeAsString(ruleSystem);

    final result = await Process.run(
      'apps/vtracer_app/assets/needle3/needle.exe',
      [
        '--model', 'apps/vtracer_app/assets/needle3/needle3.cact',
        '--tools', toolsFile.path,
        '--system', systemFile.path,
        '--max', '768',
        '--prompt', payload,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final body = jsonDecode(result.stdout as String) as Map<String, Object?>;
    final calls = body['function_calls'] as List<Object?>;
    final suppressed = body['suppressed_calls'] as List<Object?>;
    String argsStr = '(none)';
    if (calls.isNotEmpty) {
      argsStr = jsonEncode((calls.first as Map)['arguments']);
    } else if (suppressed.isNotEmpty) {
      argsStr = 'SUPPRESSED ${jsonEncode((suppressed.first as Map)['arguments'])}';
    }
    stdout.writeln('${entry.key.padRight(8)} success=${body['success']} '
        'confidence=${body['confidence']} calls=${calls.length} '
        'suppressed=${suppressed.length}');
    stdout.writeln('  $argsStr');
    await dir.delete(recursive: true);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:vtracer_ai/vtracer_ai.dart';

/// Matrix probe to find a prompt profile the tiny Needle3 model can complete.
Future<void> main(List<String> args) async {
  const features = ImageFeatures(
    width: 1920, height: 1080, megapixels: 2.07, aspectRatio: 1.78,
    quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
    edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
    colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
    darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
  );
  const goal = TuningGoal.balanced;

  final compactSystem = '''
You configure an image-to-vector converter. From the image stats, call
propose_vtracer_parameters exactly once with every field inside its range.
Set max_colors or simplify to null unless the goal needs them. Then stop.
''';
  final fullSystem = DecisionTemplates.systemPrompt(goal);
  final compactPayload =
      'goal: ${goal.name}\nimage_features: ${jsonEncode(features.toPromptPayload())}';

  final fullTool = DecisionTemplates.toolDefinition(goal);
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
      stripDescriptions(fullTool) as Map<String, Object?>;

  final variants = <String, (Map<String, Object?>, String, String)>{
    'compact-all': (compactTool, compactSystem, compactPayload),
    'compact-schema-full-system': (compactTool, fullSystem, compactPayload),
    'full-schema-compact-system': (fullTool, compactSystem, compactPayload),
  };

  for (final entry in variants.entries) {
    final (tool, system, prompt) = entry.value;
    final dir = await Directory.systemTemp.createTemp('needle3_mx');
    final toolsFile = File('${dir.path}/tools.json');
    final systemFile = File('${dir.path}/system.txt');
    await toolsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert([tool]));
    await systemFile.writeAsString(system);

    final result = await Process.run(
      'apps/vtracer_app/assets/needle3/needle.exe',
      [
        '--model', 'apps/vtracer_app/assets/needle3/needle3.cact',
        '--tools', toolsFile.path,
        '--system', systemFile.path,
        '--max', '1024',
        '--prompt', prompt,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    String? verdict;
    Object? body;
    try {
      body = jsonDecode(result.stdout as String);
      final ok = body is Map && body['success'] == true;
      final args_ = ok && (body['function_calls'] as List).isNotEmpty
          ? (body['function_calls'] as List).first['arguments']
          : null;
      verdict = ok
          ? 'OK args=${jsonEncode(args_).substring(0, (jsonEncode(args_).length).clamp(0, 220))}'
          : 'FAIL ${body is Map ? body['error'] : '?'}';
      if (entry.key == 'compact-all') {
        stdout.writeln('--- raw compact-all ---');
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(body));
      }
    } catch (e) {
      verdict = 'PARSE-FAIL $e';
    }
    stdout.writeln('${entry.key.padRight(30)} -> $verdict');
    await dir.delete(recursive: true);
  }
}

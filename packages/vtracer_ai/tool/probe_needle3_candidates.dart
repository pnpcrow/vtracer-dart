import 'dart:convert';
import 'dart:io';

import 'package:vtracer_ai/vtracer_ai.dart';

/// Candidate-selection probe: the heuristic engine proposes 3 candidate
/// parameter sets; the model picks the one best matching the features.
/// Values appear in the prompt, so the engine's grounding validation can
/// accept the choice.
Future<void> main() async {
  const photo = ImageFeatures(
    width: 1920, height: 1080, megapixels: 2.07, aspectRatio: 1.78,
    quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
    edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
    colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
    darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
  );

  const goal = TuningGoal.balanced;
  final system = '''
You configure an image-to-vector converter. Three candidate parameter sets
(A, B, C) are given. Call propose_vtracer_parameters exactly once with the
values of the candidate that best matches the image features. Copy the
candidate values exactly. Set max_colors or simplify to null when the
candidate has none. Then stop.
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

  const candidates = {
    'A': {
      'clustering': 'color-cluster', 'hierarchical': 'stacked',
      'fit_mode': 'spline', 'filter_speckle': 8, 'color_precision': 8,
      'layer_difference': 48, 'corner_threshold': 180,
      'segment_length': 4.0, 'splice_threshold': 45,
      'max_colors': null, 'simplify': 1.0, 'binary_threshold': 128,
      'binary_adaptive': false, 'watershed_detail': 128,
    },
    'B': {
      'clustering': 'color-cluster', 'hierarchical': 'cutout',
      'fit_mode': 'spline', 'filter_speckle': 4, 'color_precision': 6,
      'layer_difference': 20, 'corner_threshold': 60,
      'segment_length': 4.0, 'splice_threshold': 45,
      'max_colors': null, 'simplify': null, 'binary_threshold': 128,
      'binary_adaptive': false, 'watershed_detail': 128,
    },
    'C': {
      'clustering': 'binary', 'hierarchical': 'stacked',
      'fit_mode': 'spline', 'filter_speckle': 3, 'color_precision': 8,
      'layer_difference': 16, 'corner_threshold': 60,
      'segment_length': 4.0, 'splice_threshold': 45,
      'max_colors': null, 'simplify': null, 'binary_threshold': 128,
      'binary_adaptive': false, 'watershed_detail': 128,
    },
  };
  final payload = 'goal: ${goal.name}\n'
      'image_features: ${jsonEncode(photo.toPromptPayload())}\n'
      'candidates: ${jsonEncode(candidates)}';

  final dir = await Directory.systemTemp.createTemp('needle3_cand');
  final toolsFile = File('${dir.path}/tools.json');
  final systemFile = File('${dir.path}/system.txt');
  await toolsFile
      .writeAsString(const JsonEncoder.withIndent('  ').convert([compactTool]));
  await systemFile.writeAsString(system);

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
  stdout.writeln('success=${body['success']} confidence=${body['confidence']} '
      'calls=${calls.length} suppressed=${suppressed.length}');
  stdout.writeln('error=${body['error']}');
  if (calls.isNotEmpty) {
    stdout.writeln(const JsonEncoder.withIndent('  ')
        .convert((calls.first as Map)['arguments']));
  } else if (suppressed.isNotEmpty) {
    stdout.writeln('SUPPRESSED: ${jsonEncode((suppressed.first as Map)['arguments'])}');
  }
  stdout.writeln('reasoning: ${body['reasoning']}');
  await dir.delete(recursive: true);
}

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:vtracer_ai/vtracer_ai.dart';
import 'package:visioncortex/visioncortex.dart';

/// Diagnostic #2: (a) dump the full response for scene.png to see what the
/// model does instead of calling the tool; (b) test a single-enum
/// "candidate chooser" tool schema — does the model reliably dispatch it?
Future<void> main() async {
  final root = Directory.current.path;
  final engine = '$root/apps/vtracer_app/assets/needle3/needle.exe';
  final model = '$root/apps/vtracer_app/assets/needle3/needle3.cact';

  Future<Map<String, Object?>> runRaw(
      Map<String, Object?> tool, String system, String prompt) async {
    final dir = await Directory.systemTemp.createTemp('needle3_d2');
    final toolsFile = File('${dir.path}/tools.json');
    final systemFile = File('${dir.path}/system.txt');
    await toolsFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert([tool]));
    await systemFile.writeAsString(system);
    final result = await Process.run(engine, [
      '--model', model,
      '--tools', toolsFile.path,
      '--system', systemFile.path,
      '--max', '1024',
      '--prompt', prompt,
    ], stdoutEncoding: utf8, stderrEncoding: utf8);
    await dir.delete(recursive: true);
    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  }

  // ---- (a) full response dump for scene.png -------------------------------
  final bytes = File('$root/testdata/scene.png').readAsBytesSync();
  final decoded = img.decodeImage(bytes)!;
  final rgba = decoded.convert(numChannels: 4);
  final scene = ColorImage(
      rgba.getBytes(order: img.ChannelOrder.rgba), rgba.width, rgba.height);
  final features = FeatureExtractor().extract(scene);
  const goal = TuningGoal.balanced;
  final prompts =
      DecisionTemplates.promptsFor(PromptProfile.compact, features, goal);
  final body = await runRaw(prompts.tool, prompts.system, prompts.prompt);
  final pretty = const JsonEncoder.withIndent('  ').convert(body);
  stdout.writeln('=== scene.png full response (current compact profile) ===');
  stdout.writeln(pretty.substring(0, pretty.length.clamp(0, 1200)));

  // ---- (b) candidate chooser schema ---------------------------------------
  const chooserTool = {
    'name': 'choose_candidate',
    'parameters': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['choice'],
      'properties': {
        'choice': {
          'type': 'string',
          'enum': ['A', 'B', 'C'],
        },
      },
    },
  };
  const chooserSystem = '''
You configure an image-to-vector converter. Three candidate parameter sets
(A, B, C) are given. Call choose_candidate exactly once with the letter of
the candidate that best matches the image features.
''';

  for (final entry in {'scene': features}.entries) {
    final payload = 'goal: ${goal.name}\n'
        'image_features: ${jsonEncode(entry.value.toPromptPayload())}\n'
        'candidates:\n'
        'A = {clustering: color-cluster, hierarchical: cutout, fit_mode: spline, '
        'filter_speckle: 4, color_precision: 8, layer_difference: 20, '
        'corner_threshold: 60, segment_length: 4.0, splice_threshold: 45, '
        'max_colors: null, simplify: null, binary_threshold: 128, '
        'binary_adaptive: false, watershed_detail: 128}\n'
        'B = {clustering: color-cluster, hierarchical: stacked, fit_mode: spline, '
        'filter_speckle: 8, color_precision: 8, layer_difference: 48, '
        'corner_threshold: 180, segment_length: 4.0, splice_threshold: 45, '
        'max_colors: null, simplify: 1.0, binary_threshold: 128, '
        'binary_adaptive: false, watershed_detail: 128}\n'
        'C = {clustering: binary, hierarchical: stacked, fit_mode: spline, '
        'filter_speckle: 3, color_precision: 8, layer_difference: 16, '
        'corner_threshold: 60, segment_length: 4.0, splice_threshold: 45, '
        'max_colors: null, simplify: null, binary_threshold: 128, '
        'binary_adaptive: false, watershed_detail: 128}';
    final chooserBody =
        await runRaw(chooserTool, chooserSystem, payload);
    stdout.writeln('=== chooser probe (${entry.key}) ===');
    stdout.writeln('success:    ${chooserBody['success']}  error: ${chooserBody['error']}');
    stdout.writeln('confidence: ${chooserBody['confidence']}');
    final calls = chooserBody['function_calls'] as List;
    stdout.writeln('dispatched: ${calls.length}');
    if (calls.isNotEmpty) {
      stdout.writeln('args:       ${jsonEncode((calls.first as Map)['arguments'])}');
    }
  }
}

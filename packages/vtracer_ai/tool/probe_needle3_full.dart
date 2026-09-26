import 'dart:convert';
import 'dart:io';

import 'package:vtracer_ai/vtracer_ai.dart';

/// Probe the full production prompt set against the raw CLI to inspect the
/// model's reasoning when the tool call truncates.
Future<void> main(List<String> args) async {
  final max = args.isNotEmpty ? int.parse(args[0]) : 1024;
  const features = ImageFeatures(
    width: 1920, height: 1080, megapixels: 2.07, aspectRatio: 1.78,
    quantizedColors: 900, paletteShare8: 0.25, dominantShare: 0.04,
    edgeDensity: 0.2, meanGradient: 18, flatShare: 0.3, noiseLevel: 4,
    colorfulness: 40, transparentShare: 0, luminanceSpread: 220,
    darkShare: 0.1, lightShare: 0.05, backgroundUniformity: 25,
  );
  const goal = TuningGoal.balanced;

  final dir = await Directory.systemTemp.createTemp('needle3_probe');
  final toolsFile = File('${dir.path}/tools.json');
  final systemFile = File('${dir.path}/system.txt');
  await toolsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert([DecisionTemplates.toolDefinition(goal)]));
  await systemFile.writeAsString(DecisionTemplates.systemPrompt(goal));
  final prompt = DecisionTemplates.featurePrompt(features, goal);

  final result = await Process.run(
    'apps/vtracer_app/assets/needle3/needle.exe',
    [
      '--model', 'apps/vtracer_app/assets/needle3/needle3.cact',
      '--tools', toolsFile.path,
      '--system', systemFile.path,
      '--max', '$max',
      '--prompt', prompt,
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  stdout.writeln('exit: ${result.exitCode}');
  stdout.writeln(result.stdout);
  if ((result.stderr as String).isNotEmpty) {
    stdout.writeln('--- STDERR ---');
    stdout.writeln(result.stderr);
  }
  await dir.delete(recursive: true);
}

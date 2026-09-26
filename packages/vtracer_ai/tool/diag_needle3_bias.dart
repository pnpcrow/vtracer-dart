import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:vtracer_ai/vtracer_ai.dart';
import 'package:visioncortex/visioncortex.dart';

/// Bias probe: does the model pick by content or by candidate position?
/// Presents the same three candidates in three orders for one image.
Future<void> main() async {
  final root = Directory.current.path;
  final runtime = Needle3EmbeddedRuntime(
    enginePath: '$root/apps/vtracer_app/assets/needle3/needle.exe',
    modelPath: '$root/apps/vtracer_app/assets/needle3/needle3.cact',
    timeout: const Duration(minutes: 5),
  );
  final heuristic = HeuristicDecisionEngine();
  const goal = TuningGoal.balanced;

  final bytes = File('$root/testdata/scene.png').readAsBytesSync();
  final decoded = img.decodeImage(bytes)!;
  final rgba = decoded.convert(numChannels: 4);
  final scene = ColorImage(
      rgba.getBytes(order: img.ChannelOrder.rgba), rgba.width, rgba.height);
  final features = FeatureExtractor().extract(scene);
  final all = heuristic.candidates(features, goal);

  Future<void> probe(String label, List<(String, AiDecision)> candidates) async {
    final prompts = DecisionTemplates.chooserPrompts(features, goal, candidates);
    final answer = await runtime.run(Needle3Invocation(
      system: prompts.system,
      prompt: prompts.prompt,
      tool: prompts.tool,
    ));
    final letter = answer.arguments['choice'];
    final classOf = switch (letter) {
      'A' => 'line',
      'B' => 'flat',
      'C' => 'photo',
      _ => '?',
    };
    stdout.writeln('$label -> choice: $letter ($classOf) '
        '(confidence ${(answer.confidence ?? 0).toStringAsFixed(2)})');
  }

  // Order 1 (shipped): A=lineArt, B=flatArt, C=photo.
  await probe('order A=line,B=flat,C=photo', all);
  // Order 2: reversed — A=photo, B=flatArt, C=lineArt.
  await probe('order A=photo,B=flat,C=line', [all[2], all[1], all[0]]);
  // Order 3: rotated — A=flatArt, B=photo, C=lineArt.
  await probe('order A=flat,B=photo,C=line', [all[1], all[2], all[0]]);
}

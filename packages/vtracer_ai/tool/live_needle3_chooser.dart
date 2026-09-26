import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:vtracer_ai/vtracer_ai.dart';
import 'package:visioncortex/visioncortex.dart';

/// Live end-to-end check of the chooser engine against real testdata
/// images: the heuristic proposes A/B/C, the embedded Needle3 model picks
/// one, and the decision reports source/confidence.
Future<void> main() async {
  final root = Directory.current.path;
  final engine = Needle3CandidateEngine(
    runtime: Needle3EmbeddedRuntime(
      enginePath: '$root/apps/vtracer_app/assets/needle3/needle.exe',
      modelPath: '$root/apps/vtracer_app/assets/needle3/needle3.cact',
      timeout: const Duration(minutes: 5),
    ),
  );

  for (final name in ['scene.png', 'linework.png']) {
    final bytes = File('$root/testdata/$name').readAsBytesSync();
    final decoded = img.decodeImage(bytes)!;
    final rgba = decoded.convert(numChannels: 4);
    final image = ColorImage(
      rgba.getBytes(order: img.ChannelOrder.rgba),
      rgba.width,
      rgba.height,
    );
    final sw = Stopwatch()..start();
    try {
      final decision = await engine.decide(
          FeatureExtractor().extract(image), TuningGoal.balanced);
      sw.stop();
      stdout.writeln('=== $name ===');
      stdout.writeln('source:   ${decision.source}');
      stdout.writeln('decision: ${decision.toSummary()}');
      stdout.writeln('rationale: ${decision.rationale}');
      stdout.writeln('elapsed:  ${sw.elapsedMilliseconds} ms');
    } on Needle3Exception catch (e) {
      sw.stop();
      stdout.writeln('=== $name ===');
      stdout.writeln('Needle3Exception after ${sw.elapsedMilliseconds} ms: $e');
    }
  }
}

import 'dart:io';

import 'package:vtracer_ai/vtracer_ai.dart';

/// Dumps the decision templates (schema, tools.json, prompt examples) from
/// the Dart single source of truth into `docs/ai_auto/templates/`.
///
/// ```sh
/// dart run packages/vtracer_ai/tool/dump_templates.dart docs/ai_auto/templates
/// ```
void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'docs/ai_auto/templates' : args[0]);
  out.createSync(recursive: true);
  final sep = Platform.pathSeparator;

  // The shipped template files use the default goal; the other goals only
  // change the goal wording inside the descriptions (see prompts.md).
  File('${out.path}${sep}decision.schema.json').writeAsStringSync(
      DecisionTemplates.decisionSchemaJson(TuningGoal.balanced) + '\n');
  File('${out.path}${sep}tools.json').writeAsStringSync(
      DecisionTemplates.toolsJson(TuningGoal.balanced) + '\n');

  final sample = ImageFeatures(
    width: 1920,
    height: 1080,
    megapixels: 2.07,
    aspectRatio: 1.78,
    quantizedColors: 900,
    paletteShare8: 0.25,
    dominantShare: 0.04,
    edgeDensity: 0.2,
    meanGradient: 18.0,
    flatShare: 0.3,
    noiseLevel: 4.0,
    colorfulness: 40.0,
    transparentShare: 0,
    luminanceSpread: 220.0,
    darkShare: 0.1,
    lightShare: 0.05,
    backgroundUniformity: 25.0,
  );

  final buffer = StringBuffer()
    ..writeln('# Needle3 decision prompts (generated from ')
    ..writeln('`packages/vtracer_ai/lib/src/schema.dart` — do not edit by hand)')
    ..writeln()
    ..writeln('## System prompt — goal: balanced')
    ..writeln('```text')
    ..writeln(DecisionTemplates.systemPrompt(TuningGoal.balanced).trim())
    ..writeln('```')
    ..writeln()
    ..writeln('## System prompt — goal: faithful')
    ..writeln('```text')
    ..writeln(DecisionTemplates.systemPrompt(TuningGoal.faithful).trim())
    ..writeln('```')
    ..writeln()
    ..writeln('## System prompt — goal: compact')
    ..writeln('```text')
    ..writeln(DecisionTemplates.systemPrompt(TuningGoal.compact).trim())
    ..writeln('```')
    ..writeln()
    ..writeln('## User prompt (feature payload; values are an example)')
    ..writeln('```text')
    ..writeln(DecisionTemplates.featurePrompt(sample, TuningGoal.balanced).trim())
    ..writeln('```')
    ..writeln()
    ..writeln('## Refinement prompt (second pass after measurable feedback)')
    ..writeln('```text')
    ..writeln(DecisionTemplates.refinementPrompt(sample, {
      'clustering': 'color-cluster',
      'color_precision': 8,
      'layer_difference': 48,
    }, {
      'shape_count': 4231,
      'svg_bytes': 812345,
      'user_complaint': 'too many shapes',
    }).trim())
    ..writeln('```');
  File('${out.path}${sep}prompts.md').writeAsStringSync(buffer.toString());

  stdout.writeln('wrote ${out.path}${sep}{decision.schema.json,tools.json,prompts.md}');
}

import 'dart:convert';

import 'decision.dart';
import 'features.dart';

/// Single source of truth for the model-facing decision templates:
///
/// * [decisionJsonSchema] — the JSON Schema the model must fill (bound to a
///   JSON-grammar-constrained decoder on the Needle3 side, so every answer
///   is parseable and typed).
/// * [toolDefinition] / [toolsJson] — the Needle3 `tools.json` tool spec.
/// * [systemPrompt], [featurePrompt], [refinementPrompt] — prompt templates.
///
/// `docs/ai_auto/templates/` mirrors these files; this class is what the
/// runtimes actually send.
class DecisionTemplates {
  /// Name of the single tool the model is expected to call.
  static const toolName = 'propose_vtracer_parameters';

  /// JSON Schema of the decision the model produces. Every field is required
  /// so the grammar-constrained decoder always emits a complete object;
  /// `max_colors` and `simplify` may be explicitly null.
  static Map<String, Object?> decisionJsonSchema(TuningGoal goal) => {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'clustering', 'hierarchical', 'fit_mode', 'filter_speckle',
          'color_precision', 'layer_difference', 'corner_threshold',
          'segment_length', 'splice_threshold', 'max_colors', 'simplify',
          'binary_threshold', 'binary_adaptive', 'watershed_detail',
          'rationale', 'confidence',
        ],
        'properties': {
          'clustering': {
            'type': 'string',
            'enum': ['color-cluster', 'binary', 'watershed'],
            'description':
                'Region-forming algorithm. binary = black/white line art or '
                '1-bit scans; watershed = organic photo-like regions; '
                'color-cluster = flat/poster color art and the general case.',
          },
          'hierarchical': {
            'type': 'string',
            'enum': ['stacked', 'cutout'],
            'description':
                'stacked traces layers independently; cutout produces a '
                'seam-free mosaic (preferred for flat art with few colors).',
          },
          'fit_mode': {
            'type': 'string',
            'enum': ['pixel', 'polygon', 'spline'],
            'description':
                'pixel = exact lattice (pixel art); polygon = straight '
                'Douglas-Peucker edges; spline = corner detection + cubic '
                'Beziers (photos, smooth art).',
          },
          'filter_speckle': {
            'type': 'integer', 'minimum': 0, 'maximum': 128,
            'description':
                'Discard regions smaller than this many px on a side. Raise '
                'with noiseLevel; keep low (0-4) for fine line art.',
          },
          'color_precision': {
            'type': 'integer', 'minimum': 1, 'maximum': 8,
            'description':
                'Significant bits per RGB channel before clustering. Raise '
                'toward 8 for photos/soft gradients; 5-6 suffices for flat art.',
          },
          'layer_difference': {
            'type': 'integer', 'minimum': 0, 'maximum': 255,
            'description':
                'Color distance between stacked gradient layers. High '
                '(40-64) collapses photo gradients into few layers; low '
                '(8-24) keeps flat-art color boundaries exact.',
          },
          'corner_threshold': {
            'type': 'integer', 'minimum': 0, 'maximum': 180,
            'description':
                'Degrees; smaller = more corners preserved. Photos tolerate '
                'high values (120-180); logos/signage with hard corners want '
                '40-90.',
          },
          'segment_length': {
            'type': 'number', 'minimum': 3.5, 'maximum': 10,
            'description':
                'Max segment length (px) before subdivision. Smaller tracks '
                'detail at the cost of more nodes.',
          },
          'splice_threshold': {
            'type': 'integer', 'minimum': 0, 'maximum': 180,
            'description':
                'Degrees; smaller = more spline splices (smoother, simpler).',
          },
          'max_colors': {
            'type': ['integer', 'null'], 'minimum': 2, 'maximum': 64,
            'description':
                'Quantize the palette to at most this many colors. null = '
                'keep the clustered palette. Use 8-24 for compact output on '
                'complex images.',
          },
          'simplify': {
            'type': ['number', 'null'], 'minimum': 0.1, 'maximum': 10,
            'description':
                'Curve simplification tolerance (px). null = off. Use 1-2.5 '
                'to cut curve count on photos/illustrations; keep off for '
                'precision line art.',
          },
          'binary_threshold': {
            'type': 'integer', 'minimum': 0, 'maximum': 255,
            'description':
                'Fixed black/white cutoff (only when clustering=binary). '
                'Pick the luminance valley for bimodal images.',
          },
          'binary_adaptive': {
            'type': 'boolean',
            'description':
                'Use Bradley-Roth adaptive thresholding when the background '
                'lighting is uneven (high background_uniformity).',
          },
          'watershed_detail': {
            'type': 'integer', 'minimum': 16, 'maximum': 255,
            'description':
                'Watershed hierarchy cut level (only when clustering='
                'watershed); higher keeps more regions.',
          },
          'rationale': {
            'type': 'string', 'maxLength': 400,
            'description':
                'One-sentence justification referencing the image features '
                'that drove the decision.',
          },
          'confidence': {
            'type': 'number', 'minimum': 0, 'maximum': 1,
            'description': 'Calibrated confidence in this decision.',
          },
        },
      };

  /// Needle3 tool spec (the object placed under `tools` in a request).
  static Map<String, Object?> toolDefinition(TuningGoal goal) => {
        'name': toolName,
        'description': 'Choose optimal vtracer raster-to-vector parameters '
            'for one image, given extracted image features. Goal: '
            '${_goalDescription(goal)}',
        'parameters': decisionJsonSchema(goal),
      };

  /// Pretty-printed `tools.json` for `needle --model ... --tools tools.json`.
  static String toolsJson(TuningGoal goal) =>
      const JsonEncoder.withIndent('  ').convert([toolDefinition(goal)]);

  /// Pretty-printed standalone decision schema file.
  static String decisionSchemaJson(TuningGoal goal) =>
      const JsonEncoder.withIndent('  ').convert(decisionJsonSchema(goal));

  /// System prompt: role, hard rules, and the goal contract.
  static String systemPrompt(TuningGoal goal) => '''
You are the parameter expert of an image-to-vector (SVG) converter.
You receive numeric features of one raster image and must call the
$toolName tool once with a complete, valid parameter set.

Hard rules:
1. Choose clustering by image type: binary for black-and-white line art,
   scans or 1-bit logos; color-cluster for flat/poster color art and the
   general case; watershed only for organic photo-like detail.
2. Keep noise visible in the features out of the output: raise
   filter_speckle with noise_level, and prefer higher color_precision with
   larger layer_difference for photographic gradients.
3. Respect the goal: ${_goalDescription(goal)}
4. Use the parameter ranges exactly as given in the tool schema. Set
   max_colors or simplify to null when the goal does not need them.
5. Justify the decision in `rationale` by citing at least two feature
   values. `confidence` must reflect how typical the image is for the
   chosen class.
''';

  /// User prompt: the compact feature payload.
  static String featurePrompt(ImageFeatures f, TuningGoal goal) =>
      'goal: ${goal.name}\nimage_features:\n'
      '${const JsonEncoder.withIndent('  ').convert(f.toPromptPayload())}';

  /// Second-pass prompt after a conversion ran and produced measurable
  /// feedback (`feedback` keys, all optional: shape_count, svg_bytes,
  /// color_count, user_complaint).
  static String refinementPrompt(
    ImageFeatures f,
    Map<String, Object?> previousDecision,
    Map<String, Object?> feedback,
  ) =>
      'The previous decision was applied and the converter reported:\n'
      '${const JsonEncoder.withIndent('  ').convert(feedback)}\n\n'
      'previous decision:\n'
      '${const JsonEncoder.withIndent('  ').convert(previousDecision)}\n\n'
      'image_features:\n'
      '${const JsonEncoder.withIndent('  ').convert(f.toPromptPayload())}\n\n'
      'Call $toolName again with the adjusted parameters. Shift toward the '
      'complaint: too many shapes -> raise layer_difference / '
      'filter_speckle / simplify; lost detail -> lower filter_speckle, '
      'raise color_precision, lower layer_difference; wrong colors -> '
      'adjust color_precision or add max_colors; jagged curves -> lower '
      'corner_threshold or segment_length.';

  static String _goalDescription(TuningGoal goal) => switch (goal) {
        TuningGoal.balanced =>
          'balanced — good visual fidelity with a reasonable shape count and '
              'file size.',
        TuningGoal.faithful =>
          'faithful — preserve maximum detail; larger output is acceptable.',
        TuningGoal.compact =>
          'compact — minimize shape count and file size while staying '
              'recognizable.',
      };
}

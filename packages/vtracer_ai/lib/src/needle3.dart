import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType, Directory, File, HttpClient, Platform, Process, ProcessException;

import 'package:vtracer/vtracer.dart';

import 'decision.dart';
import 'engine.dart';
import 'features.dart';
import 'schema.dart';

/// Thrown when a Needle3 runtime call fails or the answer cannot be parsed.
class Needle3Exception implements Exception {
  final String message;
  Needle3Exception(this.message);

  @override
  String toString() => 'Needle3Exception: $message';
}

/// One model invocation: prompts plus the tool contract to enforce.
class Needle3Invocation {
  final String system;
  final String prompt;
  final Map<String, Object?> tool;
  final String model;
  final double temperature;

  const Needle3Invocation({
    required this.system,
    required this.prompt,
    required this.tool,
    this.model = 'needle3.cact',
    this.temperature = 0.2,
  });

  Map<String, Object?> toRequestJson() => {
        'model': model,
        'system': system,
        'prompt': prompt,
        'tools': [tool],
        'temperature': temperature,
      };
}

/// A parsed Needle3 answer: the tool arguments plus the model's reasoning
/// and calibrated confidence (both standard fields of every Needle3 turn).
class Needle3Answer {
  final String toolName;
  final Map<String, Object?> arguments;
  final double? confidence;
  final String? reasoning;

  const Needle3Answer(
    this.toolName,
    this.arguments, {
    this.confidence,
    this.reasoning,
  });
}

/// Pluggable transport to a Needle3 engine. Implementations ship for the
/// `needle --serve` HTTP mode and the `needle` CLI; a C-API FFI binding can
/// be dropped in for mobile without touching anything else (see
/// docs/ai_auto/needle3_integration.md).
abstract class Needle3Runtime {
  Future<Needle3Answer> run(Needle3Invocation invocation);
}

/// Talks to a `needle --serve` endpoint over HTTP.
///
/// The request/response contract is documented in
/// docs/ai_auto/needle3_integration.md; parsing is deliberately tolerant
/// (`function_calls` or `tool_calls`, arguments as object or JSON string).
class Needle3HttpRuntime implements Needle3Runtime {
  final Uri endpoint;
  final Map<String, String> headers;
  final Duration timeout;

  Needle3HttpRuntime(
    Uri? endpoint, {
    Map<String, String>? headers,
    this.timeout = const Duration(seconds: 30),
  })  : endpoint = endpoint ?? Uri.parse('http://127.0.0.1:8080/run'),
        headers = headers ?? const {};

  @override
  Future<Needle3Answer> run(Needle3Invocation invocation) async {
    final client = HttpClient();
    try {
      final request = await client
          .openUrl('POST', endpoint)
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(invocation.toRequestJson())));
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Needle3Exception('endpoint returned HTTP ${response.statusCode}');
      }
      final bodyBytes = await utf8.decoder.bind(response).join();
      final Object? body;
      try {
        body = jsonDecode(bodyBytes);
      } on FormatException catch (e) {
        throw Needle3Exception('endpoint returned non-JSON body: $e');
      }
      return parseNeedle3Answer(body);
    } on TimeoutException {
      throw Needle3Exception('endpoint timed out after ${timeout.inSeconds}s');
    } finally {
      client.close(force: true);
    }
  }
}

/// Runs the `needle` CLI as a subprocess (`needle --model <file> --tools
/// <file> --system <file> --prompt <prompt>`); desktop platforms only.
class Needle3ProcessRuntime implements Needle3Runtime {
  /// Path to the executable (`needle` / `needle.exe`).
  final String executable;

  /// Path to the `.cact` model file.
  final String modelPath;

  /// Response token limit passed as `--max` (engine default 512).
  final int maxNewTokens;

  final Duration timeout;

  Needle3ProcessRuntime({
    required this.modelPath,
    String? executable,
    this.maxNewTokens = 512,
    this.timeout = const Duration(seconds: 60),
  }) : executable = executable ?? 'needle';

  @override
  Future<Needle3Answer> run(Needle3Invocation invocation) async {
    final dir = await Directory.systemTemp.createTemp('vtracer_needle3');
    final sep = Platform.pathSeparator;
    final toolsFile = File('${dir.path}${sep}tools.json');
    final systemFile = File('${dir.path}${sep}system.txt');
    try {
      await toolsFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert([invocation.tool]));
      // `--system` takes a file path, not inline text.
      await systemFile.writeAsString(invocation.system);
      final result = await Process.run(
        executable,
        [
          '--model',
          modelPath,
          '--tools',
          toolsFile.path,
          '--system',
          systemFile.path,
          '--max',
          '$maxNewTokens',
          '--prompt',
          invocation.prompt,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      if (result.exitCode != 0) {
        throw Needle3Exception(
            'needle CLI exited ${result.exitCode}: ${result.stderr}');
      }
      return parseNeedle3Answer(extractJson(result.stdout as String));
    } on TimeoutException {
      throw Needle3Exception('needle CLI timed out');
    } on ProcessException catch (e) {
      throw Needle3Exception('could not run needle CLI: $e');
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }
}

/// Decision engine backed by a Needle3 on-device model.
///
/// Robustness contract: the model output is merged over the heuristic
/// baseline field by field, so any missing/invalid field silently falls
/// back to the deterministic value; the merged decision is then clamped.
/// `source` reports whether the model answer needed repair.
class Needle3DecisionEngine implements DecisionEngine {
  final Needle3Runtime runtime;
  final String model;
  final DecisionEngine baseline;

  /// Which prompt set to send (see [PromptProfile]); the embedded base
  /// model needs [PromptProfile.compact].
  final PromptProfile promptProfile;

  Needle3DecisionEngine({
    required this.runtime,
    this.model = 'needle3.cact',
    DecisionEngine? baseline,
    this.promptProfile = PromptProfile.full,
  }) : baseline = baseline ?? HeuristicDecisionEngine();

  @override
  String get name => 'needle3';

  @override
  Future<AiDecision> decide(ImageFeatures features, TuningGoal goal) async {
    final base = await baseline.decide(features, goal);
    final prompts = DecisionTemplates.promptsFor(promptProfile, features, goal);
    final invocation = Needle3Invocation(
      model: model,
      system: prompts.system,
      prompt: prompts.prompt,
      tool: prompts.tool,
    );
    final answer = await runtime.run(invocation);
    return mergeAnswer(base, answer, goal);
  }

  /// Decide with the model, falling back to the heuristic engine on any
  /// runtime or parsing failure.
  Future<AiDecision> decideOrHeuristic(
      ImageFeatures features, TuningGoal goal) async {
    try {
      return await decide(features, goal);
    } on Needle3Exception {
      return baseline.decide(features, goal);
    }
  }

  /// Merge the model answer over the heuristic baseline field by field, then
  /// clamp. Visible for tests.
  AiDecision mergeAnswer(AiDecision base, Needle3Answer answer, TuningGoal goal) {
    final args = answer.arguments;
    final requiredRepair = _needsRepair(args);

    AiDecision pick({
      Clustering? clustering,
      Hierarchical? hierarchical,
      FitMode? fitMode,
      int? filterSpeckle,
      int? colorPrecision,
      int? layerDifference,
      int? cornerThreshold,
      double? lengthThreshold,
      int? spliceThreshold,
      int? maxColors,
      double? simplify,
      int? binaryThreshold,
      bool? binaryAdaptive,
      int? watershedDetail,
    }) =>
        AiDecision(
          clustering: clustering ?? base.clustering,
          hierarchical: hierarchical ?? base.hierarchical,
          fitMode: fitMode ?? base.fitMode,
          filterSpeckle: filterSpeckle ?? base.filterSpeckle,
          colorPrecision: colorPrecision ?? base.colorPrecision,
          layerDifference: layerDifference ?? base.layerDifference,
          cornerThreshold: cornerThreshold ?? base.cornerThreshold,
          lengthThreshold: lengthThreshold ?? base.lengthThreshold,
          spliceThreshold: spliceThreshold ?? base.spliceThreshold,
          maxColors: maxColors ?? base.maxColors,
          simplify: simplify ?? base.simplify,
          binaryThreshold: binaryThreshold ?? base.binaryThreshold,
          binaryAdaptive: binaryAdaptive ?? base.binaryAdaptive,
          watershedDetail: watershedDetail ?? base.watershedDetail,
          rationale: (args['rationale'] as String?)?.trim().isNotEmpty == true
              ? (args['rationale'] as String).trim()
              : base.rationale,
          confidence: (answer.confidence ?? base.confidence).toDouble(),
          source:
              requiredRepair ? DecisionSource.needle3Repaired : DecisionSource.needle3,
          goal: goal,
        );

    return pick(
      clustering: _enumArg(
          args['clustering'], ['color-cluster', 'binary', 'watershed'],
          (v) => switch (v) {
                'color-cluster' => Clustering.colorCluster,
                'binary' => Clustering.binary,
                'watershed' => Clustering.watershed,
                _ => null,
              }),
      hierarchical: _enumArg(args['hierarchical'], ['stacked', 'cutout'],
          (v) => switch (v) {
                'stacked' => Hierarchical.stacked,
                'cutout' => Hierarchical.cutout,
                _ => null,
              }),
      fitMode: _enumArg(args['fit_mode'], ['pixel', 'polygon', 'spline'],
          (v) => switch (v) {
                'pixel' => FitMode.pixel,
                'polygon' => FitMode.polygon,
                'spline' => FitMode.spline,
                _ => null,
              }),
      filterSpeckle: _intArg(args['filter_speckle'], 0, 128),
      colorPrecision: _intArg(args['color_precision'], 1, 8),
      layerDifference: _intArg(args['layer_difference'], 0, 255),
      cornerThreshold: _intArg(args['corner_threshold'], 0, 180),
      lengthThreshold: _doubleArg(args['segment_length'], 3.5, 10.0),
      spliceThreshold: _intArg(args['splice_threshold'], 0, 180),
      maxColors: _nullableIntArg(args['max_colors'], 2, 64),
      simplify: _nullableDoubleArg(args['simplify'], 0.1, 10.0),
      binaryThreshold: _intArg(args['binary_threshold'], 0, 255),
      binaryAdaptive:
          args['binary_adaptive'] is bool ? args['binary_adaptive'] as bool : null,
      watershedDetail: _intArg(args['watershed_detail'], 16, 255),
    ).clamped();
  }

  /// The decision needs the `repaired` marker when the answer is missing a
  /// required field or was out of range (so operators can spot drift).
  static bool _needsRepair(Map<String, Object?> args) {
    const required = [
      'clustering', 'hierarchical', 'fit_mode', 'filter_speckle',
      'color_precision', 'layer_difference', 'corner_threshold',
      'segment_length', 'splice_threshold', 'max_colors', 'simplify',
      'binary_threshold', 'binary_adaptive', 'watershed_detail',
    ];
    if (required.any((k) => !args.containsKey(k))) return true;
    return rangeViolations(args) > 0;
  }

  static int rangeViolations(Map<String, Object?> args) {
    var violations = 0;
    void check(String key, num min, num max) {
      final v = args[key];
      if (v is num && (v < min || v > max)) violations++;
    }

    check('filter_speckle', 0, 128);
    check('color_precision', 1, 8);
    check('layer_difference', 0, 255);
    check('corner_threshold', 0, 180);
    check('segment_length', 3.5, 10);
    check('splice_threshold', 0, 180);
    check('watershed_detail', 16, 255);
    return violations;
  }

  static T? _enumArg<T>(
      Object? value, List<String> allowed, T? Function(String) map) {
    final s = value is String ? value : null;
    if (s == null || !allowed.contains(s)) return null;
    return map(s);
  }

  static int? _intArg(Object? value, int min, int max) {
    final v =
        value is num ? value : (value is String ? num.tryParse(value) : null);
    if (v == null) return null;
    return v.round().clamp(min, max);
  }

  static double? _doubleArg(Object? value, double min, double max) {
    final v =
        value is num ? value : (value is String ? num.tryParse(value) : null);
    if (v == null) return null;
    return v.toDouble().clamp(min, max);
  }

  /// Nullable in the schema: explicit null keeps the baseline null, an
  /// out-of-range number falls back to the baseline value.
  static int? _nullableIntArg(Object? value, int min, int max) {
    if (value == null) return null;
    final v =
        value is num ? value : (value is String ? num.tryParse(value) : null);
    if (v == null) return null;
    if (v < min || v > max) return null;
    return v.round();
  }

  static double? _nullableDoubleArg(Object? value, double min, double max) {
    if (value == null) return null;
    final v =
        value is num ? value : (value is String ? num.tryParse(value) : null);
    if (v == null) return null;
    if (v < min || v > max) return null;
    return v.toDouble();
  }
}

/// Parse a runtime response body into a [Needle3Answer]; tolerant to the
/// serve-mode envelope (`function_calls`/`tool_calls`) and to a bare
/// arguments object (direct extraction mode). Exposed for tests and for
/// custom runtimes.
Needle3Answer parseNeedle3Answer(Object? body) {
  if (body is! Map<String, Object?>) {
    throw Needle3Exception('unexpected response shape: ${body.runtimeType}');
  }
  // The engine reports failed turns with success:false and an empty
  // function_calls list; surface the error instead of parsing the envelope
  // as if it were tool arguments.
  if (body['success'] == false) {
    final error = body['error'] ?? body['reason'] ?? 'tool call failed';
    throw Needle3Exception('$error');
  }
  final calls = (body['function_calls'] ?? body['tool_calls']) as List<Object?>?;
  if (calls != null && calls.isEmpty) {
    // success:true but the engine dispatched nothing — the model abstained
    // (e.g. its grounding validation suppressed the call). Treat as a
    // failed call so the caller falls back to the heuristic baseline.
    throw Needle3Exception('model abstained: no tool call dispatched');
  }
  if (calls != null && calls.isNotEmpty) {
    final call = calls.first;
    if (call is Map<String, Object?>) {
      return Needle3Answer(
        (call['name'] ?? DecisionTemplates.toolName) as String,
        argumentsOf(call),
        confidence:
            _numOf(body['confidence'] ?? body['calibrated_confidence']),
        reasoning: body['reasoning'] as String?,
      );
    }
  }
  // Bare-arguments answer (schema-constrained extraction without envelope).
  return Needle3Answer(
    DecisionTemplates.toolName,
    body,
    confidence: _numOf(body['confidence']),
    reasoning: body['rationale'] as String?,
  );
}

/// Read the tool arguments out of a single call object, accepting an object
/// or a JSON string.
Map<String, Object?> argumentsOf(Map<String, Object?> call) {
  final args = call['arguments'] ?? call['args'] ?? call['parameters'];
  if (args is Map<String, Object?>) return args;
  if (args is String && args.trim().isNotEmpty) {
    final decoded = extractJson(args);
    if (decoded is Map<String, Object?>) return decoded;
  }
  throw Needle3Exception('tool call has no parseable arguments');
}

/// Extract the first balanced JSON object from noisy text (CLI banners, log
/// lines). Exposed for tests and custom runtimes.
Object? extractJson(String text) {
  final start = text.indexOf('{');
  if (start < 0) {
    throw Needle3Exception('no JSON object found in model output');
  }
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) {
        final blob = text.substring(start, i + 1);
        try {
          return jsonDecode(blob);
        } on FormatException catch (e) {
          throw Needle3Exception('invalid JSON in model output: $e');
        }
      }
    }
  }
  throw Needle3Exception('unbalanced JSON in model output');
}

double? _numOf(Object? v) => v is num ? v.toDouble() : null;

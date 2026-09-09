import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:image/image.dart' as img;
import 'package:vtracer/vtracer.dart';

const String version = '1.0.0-alpha.4';

/// Convert an image into vector graphics (Pure Dart port of vtracer-cli).
void main(List<String> arguments) {
  final parser = ArgParser(usageLineLength: 100);

  parser.addOption('input', abbr: 'i', valueHelp: 'INPUT',
      help: 'Path to the input raster image.');
  parser.addOption('output', abbr: 'o', valueHelp: 'OUTPUT',
      help: 'Path to the output SVG.');
  parser.addOption('preset',
      help: 'Start from a preset: bw, poster, photo.',
      allowed: ['bw', 'poster', 'photo']);
  parser.addOption('clustering',
      help: 'Region forming: color-cluster (default), bw, or watershed.',
      allowed: ['color-cluster', 'colorcluster', 'color', 'binary', 'bw', 'watershed']);
  parser.addOption('hierarchical',
      help: 'Hierarchical clustering: stacked (default) or cutout (mosaic).',
      allowed: ['stacked', 'cutout']);
  parser.addOption('mode', abbr: 'm',
      help: 'Curve-fitting mode: pixel, polygon, spline.',
      allowed: ['pixel', 'none', 'polygon', 'spline']);
  parser.addOption('filter-speckle', abbr: 'f', valueHelp: 'N',
      help: 'Discard patches smaller than N px in size (0..=128).');
  parser.addOption('color-precision', abbr: 'p', valueHelp: 'N',
      help: 'Significant bits per RGB channel (1..=8).');
  parser.addOption('gradient-step', abbr: 'g', valueHelp: 'N',
      help: 'Color difference between gradient layers (0..=255).');
  parser.addOption('corner-threshold', valueHelp: 'DEG', hide: true,
      help: 'Minimum momentary angle (degrees) to be a corner (0..=180).');
  parser.addOption('segment-length', valueHelp: 'PX', hide: true,
      help: 'Subdivide until all segments are shorter than this (3.5..=10).');
  parser.addOption('splice-threshold', valueHelp: 'DEG', hide: true,
      help: 'Minimum angle displacement (degrees) to splice a spline (0..=180).');
  parser.addOption('simplify', valueHelp: 'TOLERANCE',
      help: 'Simplify curves: fewest cubics within this tolerance in px (try 1-2.5).');
  parser.addOption('path-precision', valueHelp: 'N',
      help: 'Decimal places to use in path coordinates.');
  parser.addOption('palette',
      help: "Fixed palette: comma-separated hex colors, e.g. '#112233,#445566'.");
  parser.addOption('palette-file', valueHelp: 'FILE',
      help: 'Fixed palette from a file (one hex color per line or comma-separated).');
  parser.addOption('max-colors', valueHelp: 'N',
      help: 'Auto-quantize to at most N colors.');
  parser.addOption('optimize', valueHelp: 'LEVEL',
      help: 'Optimization level: 0 = off, 1 = quantize+cleanup, 2 = + shorthands/grouping.');
  parser.addOption('threshold', valueHelp: 'N',
      help: 'Binary mode: fixed threshold (0..=255); foreground when intensity is below it.');
  parser.addFlag('adaptive',
      help: 'Binary mode: use Bradley-Roth adaptive thresholding (handles uneven lighting).',
      defaultsTo: false);
  parser.addOption('adaptive-window', valueHelp: 'PX',
      help: 'Adaptive window side length in px (0 = auto). Implies --adaptive.');
  parser.addOption('adaptive-t', valueHelp: 'PCT',
      help: 'Adaptive sensitivity: percent below the local mean (default 15). Implies --adaptive.');
  parser.addOption('watershed-detail', valueHelp: 'N',
      help: 'Watershed clustering: hierarchy cut level (default 128; higher = more regions).');
  parser.addFlag('version', negatable: false, help: 'Print version and exit.');
  parser.addFlag('help', negatable: false, abbr: 'h', help: 'Print usage and exit.');

  late ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Conversion failed: ${e.message}');
    stderr.writeln(parser.usage);
    exitCode = 1;
    return;
  }

  if (args['help'] as bool) {
    stdout.writeln('Convert an image into vector graphics.\n');
    stdout.writeln(
        'Usage: vtracer [INPUT] [OUTPUT] [options]\n');
    stdout.writeln(parser.usage);
    return;
  }
  if (args['version'] as bool) {
    stdout.writeln('vtracer (dart) $version');
    return;
  }

  final rest = args.rest;
  if (rest.length > 2) {
    stderr.writeln('Conversion failed: unexpected extra positional arguments.');
    exitCode = 1;
    return;
  }

  // Accept input/output as positionals (`vtracer in.png out.svg`) or as named
  // flags; an explicit flag takes precedence over the positional.
  final input = (args['input'] as String?) ?? (rest.isNotEmpty ? rest[0] : null);
  final output = (args['output'] as String?) ?? (rest.length > 1 ? rest[1] : null);
  if (input == null) {
    stderr.writeln('Conversion failed: no input path given (positional or --input)');
    exitCode = 1;
    return;
  }
  if (output == null) {
    stderr.writeln('Conversion failed: no output path given (positional or --output)');
    exitCode = 1;
    return;
  }

  try {
    final config = buildConfig(args);
    final image = readImage(input);
    final svg = config.build().toSvg(image);
    File(output).writeAsStringSync(svg);
    stdout.writeln('Conversion successful.');
  } on VtracerError catch (e) {
    stderr.writeln('Conversion failed: $e');
    exitCode = 1;
  } catch (e) {
    stderr.writeln('Conversion failed: $e');
    exitCode = 1;
  }
}

VtracerConfig buildConfig(ArgResults args) {
  final preset = args['preset'] as String?;
  final config = preset != null
      ? VtracerConfig.fromPreset(Preset.parse(preset)!)
      : VtracerConfig.defaultConfig();

  final clustering = args['clustering'] as String?;
  if (clustering != null) {
    config.clustering = Clustering.parse(clustering)!;
  }
  final hierarchical = args['hierarchical'] as String?;
  if (hierarchical != null) {
    config.hierarchical = Hierarchical.parse(hierarchical)!;
  }
  final mode = args['mode'] as String?;
  if (mode != null) {
    config.mode = FitMode.parse(mode)!;
  }

  int? intOpt(String name) {
    final v = args[name] as String?;
    if (v == null) return null;
    return int.tryParse(v) ?? (throw FormatException('`$v` is not a number'));
  }

  double? doubleOpt(String name) {
    final v = args[name] as String?;
    if (v == null) return null;
    return double.tryParse(v) ?? (throw FormatException('`$v` is not a number'));
  }

  int range(String name, int v, int min, int max) {
    if (v < min || v > max) {
      throw FormatException('$name $v is out of range [$min, $max]');
    }
    return v;
  }

  final filterSpeckle = intOpt('filter-speckle');
  if (filterSpeckle != null) {
    config.filterSpeckle = range('filter speckle', filterSpeckle, 0, 128);
  }
  final colorPrecision = intOpt('color-precision');
  if (colorPrecision != null) {
    config.colorPrecision = range('color precision', colorPrecision, 1, 8);
  }
  final gradientStep = intOpt('gradient-step');
  if (gradientStep != null) {
    config.layerDifference = range('gradient step', gradientStep, 0, 255);
  }
  final cornerThreshold = intOpt('corner-threshold');
  if (cornerThreshold != null) {
    config.cornerThreshold = range('corner threshold', cornerThreshold, 0, 180);
  }
  final segmentLength = doubleOpt('segment-length');
  if (segmentLength != null) {
    if (segmentLength < 3.5 || segmentLength > 10.0) {
      throw FormatException(
          'segment length $segmentLength is out of range [3.5, 10]');
    }
    config.lengthThreshold = segmentLength;
  }
  final spliceThreshold = intOpt('splice-threshold');
  if (spliceThreshold != null) {
    config.spliceThreshold = range('splice threshold', spliceThreshold, 0, 180);
  }
  final simplify = doubleOpt('simplify');
  if (simplify != null) {
    if (!simplify.isFinite || simplify <= 0.0) {
      throw FormatException('simplify tolerance $simplify must be positive');
    }
    config.simplify = simplify;
  }
  final pathPrecision = intOpt('path-precision');
  if (pathPrecision != null) {
    config.pathPrecision = range('path precision', pathPrecision, 0, 20);
  }
  final optimize = intOpt('optimize');
  if (optimize != null) {
    config.optimize = range('optimize', optimize, 0, 2);
  }
  final maxColors = intOpt('max-colors');
  if (maxColors != null) {
    config.maxColors = maxColors;
  }

  // Binary thresholding: --adaptive (or either adaptive tuning flag) selects
  // Bradley-Roth; otherwise --threshold tunes the fixed cutoff.
  final threshold = intOpt('threshold');
  if (threshold != null) {
    config.binaryThreshold = range('threshold', threshold, 0, 255);
  }
  final adaptiveWindow = intOpt('adaptive-window');
  final adaptiveT = doubleOpt('adaptive-t');
  if ((args['adaptive'] as bool) || adaptiveWindow != null || adaptiveT != null) {
    config.binaryAdaptive = true;
  }
  if (adaptiveWindow != null) {
    config.binaryAdaptiveWindow = adaptiveWindow;
  }
  if (adaptiveT != null) {
    config.binaryAdaptiveT = adaptiveT;
  }
  final watershedDetail = intOpt('watershed-detail');
  if (watershedDetail != null) {
    config.watershedDetail = watershedDetail;
  }

  // Palette: inline flag wins over file; both parse to a color list.
  final palette = args['palette'] as String?;
  final paletteFile = args['palette-file'] as String?;
  if (palette != null) {
    config.palette = parsePalette(palette);
  } else if (paletteFile != null) {
    final text = File(paletteFile).readAsStringSync();
    config.palette = parsePalette(text);
  }

  return config;
}

ColorImage readImage(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('no image file found at specified input path');
  }
  final rgba = decoded.convert(numChannels: 4);
  return ColorImage(
    Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba)),
    rgba.width,
    rgba.height,
  );
}

/// Parse a comma/whitespace/newline separated list of `#rrggbb` colors.
List<Color> parsePalette(String text) {
  final colors = <Color>[];
  for (final token in text.split(RegExp(r'[,\s]+'))) {
    if (token.trim().isEmpty) {
      continue;
    }
    colors.add(parseHexColor(token.trim()));
  }
  return colors;
}

Color parseHexColor(String token) {
  var hex = token.startsWith('#') ? token.substring(1) : token;
  if (hex.length == 3) {
    // Allow #abc shorthand by expanding.
    hex = hex.split('').map((c) => c + c).join();
  }
  if (hex.length != 6) {
    throw FormatException('`$token` is not a #rrggbb color');
  }
  final r = int.tryParse(hex.substring(0, 2), radix: 16);
  final g = int.tryParse(hex.substring(2, 4), radix: 16);
  final b = int.tryParse(hex.substring(4, 6), radix: 16);
  if (r == null || g == null || b == null) {
    throw FormatException('`$token` is not a #rrggbb color');
  }
  return Color(r, g, b);
}

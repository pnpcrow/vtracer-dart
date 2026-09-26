import 'dart:convert';
import 'dart:io';

/// One-off probe of the raw `needle` CLI output contract.
Future<void> main() async {
  final tool = {
    'name': 'propose_vtracer_parameters',
    'description': 'Choose optimal vtracer raster-to-vector parameters for one image.',
    'parameters': {
      'type': 'object',
      'required': ['clustering', 'color_precision', 'rationale', 'confidence'],
      'properties': {
        'clustering': {
          'type': 'string',
          'enum': ['color-cluster', 'binary', 'watershed'],
        },
        'color_precision': {'type': 'integer', 'minimum': 1, 'maximum': 8},
        'rationale': {'type': 'string'},
        'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
      },
    },
  };
  final toolsFile = File('.needle3_probe_tools.json');
  await toolsFile.writeAsString(const JsonEncoder.withIndent('  ').convert([tool]));
  final result = await Process.run(
    'apps/vtracer_app/assets/needle3/needle.exe',
    [
      '--model', 'apps/vtracer_app/assets/needle3/needle3.cact',
      '--tools', toolsFile.path,
      '--prompt', 'goal: balanced\nimage_features:\n  quantized_colors: 900\n  noise_level: 4.0\n  palette_share_top8: 0.25\nCall propose_vtracer_parameters with the parameters.',
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  stdout.writeln('exit: ${result.exitCode}');
  stdout.writeln('--- STDOUT ---');
  stdout.writeln(result.stdout);
  stdout.writeln('--- STDERR ---');
  stdout.writeln(result.stderr);
  toolsFile.deleteSync();
}

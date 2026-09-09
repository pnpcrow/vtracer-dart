import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller.dart';

/// The tuning panel — the same controls as the vtracer webapp.
class OptionsPanel extends StatelessWidget {
  final AppState state;

  const OptionsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colorOptions = state.clustering == UiClustering.color;
    final splineOptions = state.mode == UiFitMode.spline;

    return Container(
      width: 320,
      color: Colors.white.withValues(alpha: 0.92),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: state.hasImage ? () => _saveSvg(context) : null,
            icon: const Icon(Icons.download),
            label: const Text('Download as SVG'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _pickImage(context),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Select file'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: state.rendering ? null : state.loadSample,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Try a sample'),
          ),
          const Divider(height: 32),

          _label(
            'Clustering',
            tooltip: 'Algorithm for segmentation and grouping of pixel clusters',
          ),
          Row(children: [
            Expanded(
              child: _toggle(
                'B/W',
                selected: state.clustering == UiClustering.bw,
                tooltip: 'Black & White (Binary Image)',
                onTap: () => state.update(() =>
                    state.clustering = UiClustering.bw),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                'Color',
                selected: state.clustering == UiClustering.color,
                tooltip: 'True Color Image',
                onTap: () => state.update(() =>
                    state.clustering = UiClustering.color),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _toggle(
                'Cutout',
                selected: state.hierarchical == UiHierarchical.cutout,
                tooltip: 'Shapes disjoint with others',
                onTap: () => state.update(() =>
                    state.hierarchical = UiHierarchical.cutout),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                'Stacked',
                selected: state.hierarchical == UiHierarchical.stacked,
                tooltip: 'Stack shapes on top of another',
                onTap: () => state.update(() =>
                    state.hierarchical = UiHierarchical.stacked),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          _slider(
            label: 'Filter Speckle',
            hint: '(Cleaner)',
            tooltip: 'Discard patches smaller than X px in size',
            value: state.filterSpeckle.toDouble(),
            min: 1,
            max: 16,
            divisions: 15,
            valueText: '${state.filterSpeckle}',
            onChanged: (v) =>
                state.update(() => state.filterSpeckle = v.round()),
          ),
          if (colorOptions) ...[
            _slider(
              label: 'Color Precision',
              hint: '(More accurate)',
              tooltip: 'Number of significant bits to use in a RGB channel',
              value: state.colorPrecision.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              valueText: '${state.colorPrecision}',
              onChanged: (v) =>
                  state.update(() => state.colorPrecision = v.round()),
            ),
            _slider(
              label: 'Gradient Step',
              hint: '(Less layers)',
              tooltip: 'Color difference between gradient layers',
              value: state.layerDifference.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              valueText: '${state.layerDifference}',
              onChanged: (v) =>
                  state.update(() => state.layerDifference = v.round()),
            ),
          ],
          const Divider(height: 32),

          _label(
            'Curve Fitting',
            tooltip: 'Algorithm for converting clusters to shapes',
          ),
          Row(children: [
            Expanded(
              child: _toggle(
                'Pixel',
                selected: state.mode == UiFitMode.pixel,
                tooltip: 'Exact cluster boundary',
                onTap: () => state.update(() => state.mode = UiFitMode.pixel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                'Polygon',
                selected: state.mode == UiFitMode.polygon,
                tooltip: 'Simplify to Polygon',
                onTap: () => state.update(() => state.mode = UiFitMode.polygon),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                'Spline',
                selected: state.mode == UiFitMode.spline,
                tooltip: 'Smooth and Curve-fit',
                onTap: () => state.update(() => state.mode = UiFitMode.spline),
              ),
            ),
          ]),
          if (splineOptions) ...[
            _slider(
              label: 'Corner Threshold',
              hint: '(Smoother)',
              tooltip:
                  'Minimum momentary angle (degrees) to be considered a corner',
              value: state.cornerThreshold.toDouble(),
              min: 0,
              max: 180,
              divisions: 180,
              valueText: '${state.cornerThreshold}',
              onChanged: (v) =>
                  state.update(() => state.cornerThreshold = v.round()),
            ),
            _slider(
              label: 'Segment Length',
              hint: '(More coarse)',
              tooltip:
                  'Subdivide until all segments are shorter than this length',
              value: state.lengthThreshold,
              min: 3.5,
              max: 10,
              divisions: 13,
              valueText: state.lengthThreshold.toStringAsFixed(1),
              onChanged: (v) =>
                  state.update(() => state.lengthThreshold = v),
            ),
            _slider(
              label: 'Splice Threshold',
              hint: '(More accurate)',
              tooltip:
                  'Minimum angle displacement (degrees) to splice two curves',
              value: state.spliceThreshold.toDouble(),
              min: 0,
              max: 180,
              divisions: 180,
              valueText: '${state.spliceThreshold}',
              onChanged: (v) =>
                  state.update(() => state.spliceThreshold = v.round()),
            ),
          ],
          const Divider(height: 32),
          if (state.hasImage)
            Text(
              'Input: ${state.imageWidth}×${state.imageHeight} px\n'
              'Output: ${state.shapeCount} shapes, ${state.renderMs} ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final file = result.isEmpty ? null : result.single;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      await state.loadImageBytes(bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load image: $e')));
      }
    }
  }

  Future<void> _saveSvg(BuildContext context) async {
    final svg = state.svg;
    if (svg == null) return;
    final bytes = Uint8List.fromList(svg.codeUnits);
    final name =
        'export-${DateTime.now().toIso8601String().split('T').first}.svg';
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SVG saved.')),
      );
    }
  }

  Widget _label(String text, {String? tooltip}) {
    final textWidget = Text(text, style: const TextStyle(fontWeight: FontWeight.w600));
    return tooltip == null
        ? textWidget
        : Tooltip(message: tooltip, child: textWidget);
  }

  Widget _toggle(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? Colors.blue.withValues(alpha: 0.15) : null,
        foregroundColor: selected ? Colors.blue : null,
        side: selected ? const BorderSide(color: Colors.blue) : null,
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: const Size.fromHeight(36),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  Widget _slider({
    required String label,
    required String hint,
    required String tooltip,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String valueText,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Tooltip(
          message: tooltip,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(hint,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Text(valueText,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 16,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

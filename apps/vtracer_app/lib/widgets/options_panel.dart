import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../l10n/app_localizations.dart';

/// The tuning panel — the same controls as the vtracer webapp, with a short
/// helper description under each setting.
class OptionsPanel extends StatelessWidget {
  final AppState state;

  const OptionsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorOptions = state.clustering == UiClustering.color;
    final splineOptions = state.mode == UiFitMode.spline;

    return Container(
      width: 320,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: state.hasImage ? () => _saveSvg(context) : null,
            icon: const Icon(Icons.download),
            label: Text(l10n.panelDownloadSvg),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => _pickImage(context),
            icon: const Icon(Icons.image_outlined),
            label: Text(l10n.panelSelectFile),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: state.rendering ? null : state.loadSample,
            icon: const Icon(Icons.auto_awesome),
            label: Text(l10n.panelTrySample),
          ),
          const SizedBox(height: 8),
          // Conversions are too heavy for live re-rendering while tuning, so
          // parameter changes wait here until applied.
          FilledButton.icon(
            onPressed: state.needsApply ? state.apply : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(state.rendering ? l10n.panelRendering : l10n.panelApply),
          ),
          const Divider(height: 32),

          _groupHeader(context, l10n.groupClustering, l10n.groupClusteringDesc),
          Row(children: [
            Expanded(
              child: _toggle(
                context,
                l10n.clusterBw,
                selected: state.clustering == UiClustering.bw,
                tooltip: l10n.clusterBwTip,
                onTap: () =>
                    state.update(() => state.clustering = UiClustering.bw),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                context,
                l10n.clusterColor,
                selected: state.clustering == UiClustering.color,
                tooltip: l10n.clusterColorTip,
                onTap: () =>
                    state.update(() => state.clustering = UiClustering.color),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _toggle(
                context,
                l10n.hierarchyCutout,
                selected: state.hierarchical == UiHierarchical.cutout,
                tooltip: l10n.hierarchyCutoutTip,
                onTap: () => state.update(
                    () => state.hierarchical = UiHierarchical.cutout),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                context,
                l10n.hierarchyStacked,
                selected: state.hierarchical == UiHierarchical.stacked,
                tooltip: l10n.hierarchyStackedTip,
                onTap: () => state.update(
                    () => state.hierarchical = UiHierarchical.stacked),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          _slider(
            context,
            label: l10n.sliderFilterSpeckle,
            hint: l10n.sliderFilterSpeckleHint,
            description: l10n.sliderFilterSpeckleDesc,
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
              context,
              label: l10n.sliderColorPrecision,
              hint: l10n.sliderColorPrecisionHint,
              description: l10n.sliderColorPrecisionDesc,
              value: state.colorPrecision.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              valueText: '${state.colorPrecision}',
              onChanged: (v) =>
                  state.update(() => state.colorPrecision = v.round()),
            ),
            _slider(
              context,
              label: l10n.sliderGradientStep,
              hint: l10n.sliderGradientStepHint,
              description: l10n.sliderGradientStepDesc,
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

          _groupHeader(
              context, l10n.groupCurveFitting, l10n.groupCurveFittingDesc),
          Row(children: [
            Expanded(
              child: _toggle(
                context,
                l10n.fitPixel,
                selected: state.mode == UiFitMode.pixel,
                tooltip: l10n.fitPixelTip,
                onTap: () => state.update(() => state.mode = UiFitMode.pixel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                context,
                l10n.fitPolygon,
                selected: state.mode == UiFitMode.polygon,
                tooltip: l10n.fitPolygonTip,
                onTap: () => state.update(() => state.mode = UiFitMode.polygon),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _toggle(
                context,
                l10n.fitSpline,
                selected: state.mode == UiFitMode.spline,
                tooltip: l10n.fitSplineTip,
                onTap: () => state.update(() => state.mode = UiFitMode.spline),
              ),
            ),
          ]),
          if (splineOptions) ...[
            _slider(
              context,
              label: l10n.sliderCornerThreshold,
              hint: l10n.sliderCornerThresholdHint,
              description: l10n.sliderCornerThresholdDesc,
              value: state.cornerThreshold.toDouble(),
              min: 0,
              max: 180,
              divisions: 180,
              valueText: '${state.cornerThreshold}',
              onChanged: (v) =>
                  state.update(() => state.cornerThreshold = v.round()),
            ),
            _slider(
              context,
              label: l10n.sliderSegmentLength,
              hint: l10n.sliderSegmentLengthHint,
              description: l10n.sliderSegmentLengthDesc,
              value: state.lengthThreshold,
              min: 3.5,
              max: 10,
              divisions: 13,
              valueText: state.lengthThreshold.toStringAsFixed(1),
              onChanged: (v) => state.update(() => state.lengthThreshold = v),
            ),
            _slider(
              context,
              label: l10n.sliderSpliceThreshold,
              hint: l10n.sliderSpliceThresholdHint,
              description: l10n.sliderSpliceThresholdDesc,
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
              '${l10n.panelInputSummary(state.imageWidth, state.imageHeight)}\n'
              '${l10n.panelOutputSummary(state.shapeCount, state.renderMs)}',
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
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.snackbarLoadFailed('$e'))),
        );
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
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.snackbarSvgSaved)),
      );
    }
  }

  /// A section header with its helper description underneath.
  Widget _groupHeader(BuildContext context, String title, String description) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            )),
        const SizedBox(height: 2),
        Text(
          description,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _toggle(
    BuildContext context,
    String label, {
    required bool selected,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? primary.withValues(alpha: 0.15) : null,
        foregroundColor: selected ? primary : null,
        side: selected ? BorderSide(color: primary) : null,
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: const Size.fromHeight(36),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String hint,
    required String description,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String valueText,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface)),
            Text(hint,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        Text(valueText,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: theme.colorScheme.primary,
            )),
        // The helper description explains what the slider controls; the
        // value-dependent hint next to the label shows the direction.
        Text(
          description,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

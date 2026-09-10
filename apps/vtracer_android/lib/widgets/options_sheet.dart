import 'package:flutter/material.dart';

import '../controller.dart';
import '../l10n/app_localizations.dart';

/// Opens the trace-options bottom sheet; returns when the sheet is closed.
/// The Apply button inside pops the sheet and then re-renders.
Future<void> showOptionsSheet(BuildContext context, AppState state) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => OptionsSheet(state: state),
  );
}

/// The tuning parameters, mirroring the vtracer webapp's options panel:
/// clustering mode and hierarchy, then curve fitting. Changing a control
/// marks the state dirty; the (expensive) conversion runs on Apply.
class OptionsSheet extends StatelessWidget {
  final AppState state;

  const OptionsSheet({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.optionsTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        l10n.groupClustering,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        l10n.groupClusteringDesc,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<UiClustering>(
                              segments: [
                                ButtonSegment(
                                  value: UiClustering.color,
                                  label: Text(l10n.clusterColor),
                                  tooltip: l10n.clusterColorTip,
                                ),
                                ButtonSegment(
                                  value: UiClustering.bw,
                                  label: Text(l10n.clusterBw),
                                  tooltip: l10n.clusterBwTip,
                                ),
                              ],
                              selected: {state.clustering},
                              onSelectionChanged: (s) => state.update(
                                () => state.clustering = s.first,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<UiHierarchical>(
                              segments: [
                                ButtonSegment(
                                  value: UiHierarchical.stacked,
                                  label: Text(l10n.hierarchyStacked),
                                  tooltip: l10n.hierarchyStackedTip,
                                ),
                                ButtonSegment(
                                  value: UiHierarchical.cutout,
                                  label: Text(l10n.hierarchyCutout),
                                  tooltip: l10n.hierarchyCutoutTip,
                                ),
                              ],
                              selected: {state.hierarchical},
                              onSelectionChanged: (s) => state.update(
                                () => state.hierarchical = s.first,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _SliderTile(
                        label: l10n.sliderFilterSpeckle,
                        hint: l10n.sliderFilterSpeckleHint,
                        desc: l10n.sliderFilterSpeckleDesc,
                        value: state.filterSpeckle.toDouble(),
                        min: 1,
                        max: 16,
                        divisions: 15,
                        valueText: '${state.filterSpeckle}',
                        onChanged: (v) => state.update(
                          () => state.filterSpeckle = v.round(),
                        ),
                      ),
                      _SliderTile(
                        label: l10n.sliderColorPrecision,
                        hint: l10n.sliderColorPrecisionHint,
                        desc: l10n.sliderColorPrecisionDesc,
                        value: state.colorPrecision.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        valueText: '${state.colorPrecision}',
                        onChanged: (v) => state.update(
                          () => state.colorPrecision = v.round(),
                        ),
                      ),
                      _SliderTile(
                        label: l10n.sliderGradientStep,
                        hint: l10n.sliderGradientStepHint,
                        desc: l10n.sliderGradientStepDesc,
                        value: state.layerDifference.toDouble(),
                        min: 0,
                        max: 255,
                        divisions: 255,
                        valueText: '${state.layerDifference}',
                        onChanged: (v) => state.update(
                          () => state.layerDifference = v.round(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.groupCurveFitting,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        l10n.groupCurveFittingDesc,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<UiFitMode>(
                              segments: [
                                ButtonSegment(
                                  value: UiFitMode.pixel,
                                  label: Text(l10n.fitPixel),
                                  tooltip: l10n.fitPixelTip,
                                ),
                                ButtonSegment(
                                  value: UiFitMode.polygon,
                                  label: Text(l10n.fitPolygon),
                                  tooltip: l10n.fitPolygonTip,
                                ),
                                ButtonSegment(
                                  value: UiFitMode.spline,
                                  label: Text(l10n.fitSpline),
                                  tooltip: l10n.fitSplineTip,
                                ),
                              ],
                              selected: {state.mode},
                              onSelectionChanged: (s) =>
                                  state.update(() => state.mode = s.first),
                            ),
                          ),
                        ],
                      ),
                      _SliderTile(
                        label: l10n.sliderCornerThreshold,
                        hint: l10n.sliderCornerThresholdHint,
                        desc: l10n.sliderCornerThresholdDesc,
                        value: state.cornerThreshold.toDouble(),
                        min: 0,
                        max: 180,
                        divisions: 180,
                        valueText: '${state.cornerThreshold}°',
                        onChanged: (v) => state.update(
                          () => state.cornerThreshold = v.round(),
                        ),
                      ),
                      _SliderTile(
                        label: l10n.sliderSegmentLength,
                        hint: l10n.sliderSegmentLengthHint,
                        desc: l10n.sliderSegmentLengthDesc,
                        value: state.lengthThreshold,
                        min: 3.5,
                        max: 10,
                        divisions: 13,
                        valueText: state.lengthThreshold.toStringAsFixed(1),
                        onChanged: (v) => state.update(
                          () => state.lengthThreshold = v,
                        ),
                      ),
                      _SliderTile(
                        label: l10n.sliderSpliceThreshold,
                        hint: l10n.sliderSpliceThresholdHint,
                        desc: l10n.sliderSpliceThresholdDesc,
                        value: state.spliceThreshold.toDouble(),
                        min: 0,
                        max: 180,
                        divisions: 180,
                        valueText: '${state.spliceThreshold}°',
                        onChanged: (v) => state.update(
                          () => state.spliceThreshold = v.round(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.panelApply),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labeled slider with its live value and a one-line helper description.
class _SliderTile extends StatelessWidget {
  final String label;
  final String hint;
  final String desc;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueText;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.label,
    required this.hint,
    required this.desc,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 4),
            Text(
              hint,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const Spacer(),
            Text(
              valueText,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontFeatures: const [],
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        Text(desc, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

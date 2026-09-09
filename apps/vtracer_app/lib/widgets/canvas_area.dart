import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vtracer/vtracer.dart' show Phase;

import '../controller.dart';
import '../detail/detail.dart';
import '../l10n/app_localizations.dart';
import '../preview.dart';
import '../theme.dart';

/// The canvas: a drop zone until an image is loaded, then the traced SVG.
///
/// The trace is shown as a pre-rasterized image (see [rasterizeSvg]) rather
/// than a live vector picture: extremely complex traces dragged the
/// rasterizer down (and crashed it at fullscreen), while a raster at a
/// monitor-capped size displays at any window size for free. Full-detail
/// viewing happens in a separate window.
class CanvasArea extends StatefulWidget {
  final AppState state;

  const CanvasArea({super.key, required this.state});

  @override
  State<CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<CanvasArea> {
  bool _hovering = false;
  ui.Image? _preview;

  /// The SVG string baked into [_preview]; the raster is rebuilt only when
  /// the trace changes, never on window resize.
  String? _bakedSvg;

  /// Displayed-width ÷ source-width of the current preview, live-tracked
  /// from the frame layout for the info bar.
  final ValueNotifier<double?> _previewScale = ValueNotifier(null);

  @override
  void didUpdateWidget(CanvasArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshPreview();
  }

  @override
  void dispose() {
    _previewScale.dispose();
    _preview?.dispose();
    _preview = null;
    super.dispose();
  }

  void _refreshPreview() {
    final svg = widget.state.svg;
    if (svg == null || svg == _bakedSvg) return;

    final cap = previewCap(View.of(context));
    rasterizeSvg(svg, cap).then((image) {
      if (!mounted || widget.state.svg != svg) {
        image.dispose();
        return;
      }
      final old = _preview;
      setState(() {
        _preview = image;
        _bakedSvg = svg;
      });
      old?.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Column(
      children: [
        Expanded(child: _canvas(context)),
        if (state.hasImage) _infoBar(context),
      ],
    );
  }

  Widget _canvas(BuildContext context) {
    final state = widget.state;
    final canvas = Theme.of(context).extension<CanvasColors>()!;
    return DropTarget(
      onDragDone: (details) async {
        final file = details.files.first;
        try {
          final bytes = await file.readAsBytes();
          await state.loadImageBytes(bytes);
        } catch (e) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(this.context)!;
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text(l10n.snackbarLoadFailed('$e'))),
          );
        }
      },
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      child: Stack(
        children: [
          Container(
            color: _hovering
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
                : canvas.dropBackdrop,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: state.hasImage ? _result(context) : _dropHint(context),
          ),
          if (state.svg != null) _detailButton(context),
          if (state.rendering) _progressOverlay(context),
          if (state.needsApply) _dirtyHint(context),
          if (state.error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _errorBanner(context),
            ),
        ],
      ),
    );
  }

  Widget _dropHint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canvas = theme.extension<CanvasColors>()!;
    return Container(
      width: 420,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      decoration: BoxDecoration(
        border: Border.all(
          color: _hovering ? theme.colorScheme.primary : canvas.dropBorder,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _hovering ? Icons.file_download : Icons.image_outlined,
            size: 48,
            color: _hovering
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            _hovering ? l10n.canvasDropHintHover : l10n.canvasDropHint,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.canvasDropHintSub,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context) {
    final canvas = Theme.of(context).extension<CanvasColors>()!;
    final preview = _preview;
    final baked = _bakedSvg;
    final svg = widget.state.svg;
    return LayoutBuilder(builder: (context, constraints) {
      if (preview != null && preview.height > 0) {
        _trackPreviewScale(preview, constraints.maxWidth, constraints.maxHeight);
      }
      return Container(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        ),
        decoration: BoxDecoration(
          color: canvas.paper,
          border: Border.all(color: canvas.paperBorder),
        ),
        clipBehavior: Clip.hardEdge,
        child: CustomPaint(
          // Checkerboard paper so transparency in the trace is visible in
          // both light and dark themes. `painter` (not `foregroundPainter`)
          // keeps the grid behind the image.
          painter: _CheckerPainter(canvas: canvas),
          child: (preview != null && baked == svg)
              ? SizedBox(
                  // Explicit size: a bare RawImage sizes to its intrinsic
                  // pixel size instead of filling the frame.
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: RawImage(
                    image: preview,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    });
  }

  /// Track how large the preview is displayed (contain-fit of the doc-aspect
  /// raster inside the frame) relative to the source image resolution.
  /// Updated post-frame: the info bar listens and rebuilds on change.
  void _trackPreviewScale(ui.Image preview, double frameW, double frameH) {
    final aspect = preview.width / preview.height;
    final displayedW = math.min(frameW, frameH * aspect);
    final srcW = widget.state.imageWidth;
    final scale = srcW > 0 ? displayedW / srcW : null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _previewScale.value != scale) {
        _previewScale.value = scale;
      }
    });
  }

  /// The bottom strip: source/output facts and the preview zoom level.
  Widget _infoBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.state;
    final src = state.sourceInfo;
    final out = state.outputInfo;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _barSegment(
                    style,
                    l10n.infoBarInput,
                    [
                      if (src != null) src.format,
                      '${state.imageWidth}×${state.imageHeight}',
                      if (src != null) src.colorSpace,
                      if (src != null) formatBytes(src.bytes),
                    ],
                  ),
                  const SizedBox(width: 20),
                  _barSegment(
                    style,
                    l10n.infoBarOutput,
                    out == null
                        ? ['SVG', l10n.infoBarPending]
                        : [
                            'SVG',
                            '${out.width}×${out.height}',
                            l10n.infoBarShapes(out.shapes),
                            l10n.infoBarLayers(out.layers),
                            formatBytes(out.bytes),
                            '${out.renderMs} ms',
                          ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<double?>(
            valueListenable: _previewScale,
            builder: (context, scale, _) => Text(
              scale == null ? '' : l10n.infoBarPreviewScale((scale * 100).round()),
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barSegment(TextStyle? style, String label, List<String> parts) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: parts.join(' · ')),
        ],
      ),
      style: style,
    );
  }

  /// Opens the trace full-detail in a separate window/tab.
  Widget _detailButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      top: 8,
      right: 8,
      child: IconButton.filledTonal(
        tooltip: l10n.tooltipOpenFullView,
        icon: const Icon(Icons.open_in_full),
        onPressed:
            widget.state.rendering ? null : () => openDetailView(widget.state.svg!),
      ),
    );
  }

  /// A small banner while parameters have changed but not been applied.
  Widget _dirtyHint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: scheme.primary,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.bannerDirty,
            style: TextStyle(color: scheme.onPrimary, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.error,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          widget.state.error!,
          style: TextStyle(color: scheme.onError),
        ),
      ),
    );
  }

  Widget _progressOverlay(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.state;
    final label = switch (state.progressPhase) {
      Phase.segment => l10n.progressPhaseSegment,
      Phase.compose => l10n.progressPhaseCompose,
      Phase.optimize => l10n.progressPhaseOptimize,
      null => l10n.progressConverting,
    };
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.black87,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label ${(state.progressFraction * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: state.progressFraction,
                minHeight: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transparency checkerboard for the preview paper, theme-tinted via
/// [CanvasColors].
class _CheckerPainter extends CustomPainter {
  static const _square = 12.0;

  final CanvasColors canvas;

  _CheckerPainter({required this.canvas});

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()..color = this.canvas.checker;
    for (var y = 0.0; y < size.height; y += _square) {
      final rowOdd = (y / _square).round().isOdd;
      for (var x = 0.0; x < size.width; x += _square) {
        final colOdd = (x / _square).round().isOdd;
        if (rowOdd != colOdd) continue;
        canvas.drawRect(Offset(x, y) & const Size.square(_square), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) =>
      oldDelegate.canvas != canvas;
}

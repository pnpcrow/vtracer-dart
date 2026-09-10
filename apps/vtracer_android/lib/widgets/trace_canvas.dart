import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controller.dart';
import '../l10n/app_localizations.dart';
import '../preview.dart';
import '../theme.dart';

/// The canvas: an empty-state hint until an image is loaded, then the
/// traced SVG as a pre-rasterized image over a transparency checkerboard.
///
/// Like the desktop app, the preview is baked into a bitmap once per trace
/// (capped at the device's physical resolution) instead of drawing the live
/// vector picture — parameter changes are applied explicitly with the
/// Apply button, so the raster is rebuilt only when the SVG changes.
class TraceCanvas extends StatefulWidget {
  final AppState state;
  final VoidCallback onPickGallery;
  final VoidCallback onTrySample;

  const TraceCanvas({
    super.key,
    required this.state,
    required this.onPickGallery,
    required this.onTrySample,
  });

  @override
  State<TraceCanvas> createState() => _TraceCanvasState();
}

class _TraceCanvasState extends State<TraceCanvas> {
  ui.Image? _preview;

  /// The SVG string baked into [_preview]; the raster is rebuilt only when
  /// the trace changes.
  String? _bakedSvg;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void didUpdateWidget(TraceCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.state, oldWidget.state)) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _onStateChanged();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _preview?.dispose();
    _preview = null;
    super.dispose();
  }

  Future<void> _onStateChanged() async {
    // While a re-render is in flight the old trace stays visible; AppState
    // clears `svg` only when a new image is loaded.
    final svg = widget.state.svg;
    if (svg != null && svg != _bakedSvg && mounted) {
      final cap = previewCap(context);
      try {
        final raster = await rasterizeSvg(svg, cap);
        if (!mounted) {
          raster.dispose();
          return;
        }
        setState(() {
          _preview?.dispose();
          _preview = raster;
          _bakedSvg = svg;
        });
        return;
      } catch (_) {
        // Rasterization failed; fall through to the loading view.
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: _canvasColors(context).paperBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final preview = _preview;

    if (preview != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // The raster's own pixel size carries the document's aspect.
          final doc = Size(
            preview.width.toDouble(),
            preview.height.toDouble(),
          );
          final scale = (constraints.maxWidth / doc.width)
              .clamp(0.0, constraints.maxHeight / doc.height);
          return Center(
            child: SizedBox(
              width: doc.width * scale,
              height: doc.height * scale,
              child: CustomPaint(
                painter: _CheckerPainter(_canvasColors(context)),
                child: RawImage(
                  image: preview,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          );
        },
      );
    }

    if (widget.state.rendering) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.progressConverting),
          ],
        ),
      );
    }

    // Empty state.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.canvasEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.canvasEmptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: widget.onPickGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.pickFromGallery),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onTrySample,
              child: Text(l10n.trySample),
            ),
          ],
        ),
      ),
    );
  }

  CanvasColors _canvasColors(BuildContext context) =>
      Theme.of(context).extension<CanvasColors>() ??
      const CanvasColors(
        paper: Colors.white,
        checker: Color(0xFFEFEFF2),
        paperBorder: Colors.black26,
        dropBorder: Colors.black45,
        dropBackdrop: Colors.white,
      );
}

/// Paints the transparency checkerboard behind the traced preview.
class _CheckerPainter extends CustomPainter {
  final CanvasColors colors;

  const _CheckerPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.paper);
    const square = 12.0;
    final paint = Paint()..color = colors.checker;
    for (var y = 0.0; y < size.height; y += square) {
      for (var x = 0.0; x < size.width; x += square) {
        if (((x / square).floor() + (y / square).floor()).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(
              x,
              y,
              math.min(square, size.width - x),
              math.min(square, size.height - y),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => oldDelegate.colors != colors;
}

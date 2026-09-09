import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

/// Rasterizes an SVG string to a [ui.Image], aspect-fitting the document
/// into [maxSize] (in physical pixels).
///
/// The canvas preview shows this raster instead of the vector picture:
/// drawing an extremely complex path at fullscreen every frame is what
/// overloaded (and crashed) the rasterizer, while a one-shot raster at a
/// capped size is cheap to display at any window size.
Future<ui.Image> rasterizeSvg(String svg, ui.Size maxSize) async {
  final info = await vg.loadPicture(SvgStringLoader(svg), null);
  final picture = info.picture;
  try {
    final doc = info.size;
    if (doc.width <= 0 || doc.height <= 0) {
      throw const FormatException('svg has no intrinsic size');
    }
    var w = maxSize.width;
    var h = w * doc.height / doc.width;
    if (h > maxSize.height) {
      h = maxSize.height;
      w = h * doc.width / doc.height;
    }
    final width = math.max(1, w.round());
    final height = math.max(1, h.round());

    // toImage rasterizes picture coordinates 1:1 — the document must be
    // scaled onto the target surface explicitly, or it lands unscaled in
    // the top-left corner (empty bands when upscaling, cut-off content
    // when downscaling).
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(width / doc.width, height / doc.height);
    canvas.drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      return await scaled.toImage(width, height);
    } finally {
      scaled.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// The physical resolution of the monitor showing [view].
ui.Size monitorSize(ui.FlutterView view) => view.display.size;

/// Preview raster cap: half the monitor's resolution, in physical pixels.
/// The cap is deliberately independent of the current window size so that
/// resizing never re-rasterizes; a half-resolution preview stays sharp
/// enough in any window up to fullscreen.
///
/// Some platforms report a [ui.FlutterView.display] size smaller than the
/// physical monitor (scaled/quirky display metadata), so the cap never
/// drops below half the current window's physical size — the preview is
/// then at worst 2× supersampled when maximized, never undersampled.
ui.Size previewCap(ui.FlutterView view) {
  final monitor = monitorSize(view);
  final window = view.physicalSize;
  return ui.Size(
    math.max(monitor.width, window.width) / 2,
    math.max(monitor.height, window.height) / 2,
  );
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Rasterizes an SVG string to a [ui.Image], aspect-fitting the document
/// into [maxSize] (in physical pixels).
///
/// The canvas preview shows this raster instead of the vector picture:
/// drawing an extremely complex path every frame is what overloaded (and
/// crashed) the desktop rasterizer, while a one-shot raster at a capped
/// size is cheap to display at any size.
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

/// Preview raster cap for a phone screen: the view's physical size, clamped
/// so no side exceeds 2048px. Rasterizing once at (up to) full physical
/// resolution keeps the preview sharp under any pinch/scale the UI applies.
ui.Size previewCap(BuildContext context) {
  final physical = View.of(context).physicalSize;
  const limit = 2048.0;
  var scale = 1.0;
  if (physical.width > limit) scale = math.min(scale, limit / physical.width);
  if (physical.height > limit) scale = math.min(scale, limit / physical.height);
  return physical * scale;
}

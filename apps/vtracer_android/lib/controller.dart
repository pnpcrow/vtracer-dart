import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:vtracer/vtracer.dart';
import 'package:vtracer/worker.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

/// Which pipeline options the UI exposes (mirrors the vtracer webapp).
enum UiClustering { color, bw }

enum UiHierarchical { stacked, cutout }

enum UiFitMode { pixel, polygon, spline }

/// What we know about the loaded source image (shown in the info bar).
class SourceInfo {
  /// Sniffed container format, e.g. "PNG".
  final String format;

  /// Color space of the decoded frames, e.g. "sRGB".
  final String colorSpace;

  /// Encoded byte length (raw pixel count for the built-in sample).
  final int bytes;

  const SourceInfo(this.format, this.colorSpace, this.bytes);
}

/// Facts about the last produced SVG (shown in the info bar).
class OutputInfo {
  final int width;
  final int height;
  final int shapes;
  final int layers;
  final int bytes;
  final int renderMs;

  const OutputInfo({
    required this.width,
    required this.height,
    required this.shapes,
    required this.layers,
    required this.bytes,
    required this.renderMs,
  });
}

/// Format a byte count for display: "8.2 KB", "1.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Sniff the container format from magic bytes.
String sniffImageFormat(Uint8List b) {
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) return 'PNG';
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'JPEG';
  if (b.length >= 4 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'GIF';
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45) {
    return 'WebP';
  }
  if (b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D) return 'BMP';
  return 'Image';
}

String colorSpaceName(ui.ColorSpace? space) {
  switch (space) {
    case ui.ColorSpace.displayP3:
      return 'Display P3';
    case ui.ColorSpace.extendedSRGB:
      return 'Ext sRGB';
    case ui.ColorSpace.sRGB:
    case null:
      return 'sRGB';
  }
}

/// File name (without extension) the SVG should be saved under, derived
/// from the source image's name: "photo.jpg" → "photo-traced.svg".
String suggestedSaveName(String? sourceName, DateTime now) {
  var base = sourceName ?? '';
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.trim().isEmpty ? 'vtracer' : base;
  // MediaStore DISPLAY_NAME only: strip path separators and control chars.
  base = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  final stamp = '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}'
      '-${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
  return '${base}_$stamp-traced.svg';
}

/// App state: the source image, the tuning parameters and the render loop.
///
/// Conversion runs on a [VtracerWorker] — a background isolate on Android
/// (so the UI isolate stays free while the pipeline crunches pixels).
/// Parameter changes mark the state dirty instead of re-rendering live:
/// real-time conversion is too heavy for interactive tuning on larger
/// images, so the user applies changes explicitly via [apply]. Loading an
/// image auto-applies once, matching the open-and-trace flow.
class AppState extends ChangeNotifier {
  VtracerWorker? _worker;
  ColorImage? _image;

  /// Name of the source image (for save-file naming), when known.
  String? sourceName;

  String? svg;
  bool get hasImage => _image != null;
  int get imageWidth => _image?.width ?? 0;
  int get imageHeight => _image?.height ?? 0;

  // --- options (defaults match the webapp) --------------------------------
  UiClustering clustering = UiClustering.color;
  UiHierarchical hierarchical = UiHierarchical.stacked;
  UiFitMode mode = UiFitMode.spline;
  int filterSpeckle = 4;
  int colorPrecision = 6;
  int layerDifference = 16;
  int cornerThreshold = 60;
  double lengthThreshold = 4.0;
  int spliceThreshold = 45;

  /// Extra tuning targets the sheet has no slider for; usually null, set by
  /// the AI auto mode when its decision uses them.
  int? maxColors;
  double? simplify;

  // --- AI auto mode ---------------------------------------------------------
  TuningGoal aiGoal = TuningGoal.balanced;
  bool aiBusy = false;
  String? aiRationale;
  double? aiConfidence;

  // --- render state ---------------------------------------------------------
  bool rendering = false;

  /// Parameters changed since the last render and await an [apply].
  bool dirty = false;
  bool get needsApply => dirty && hasImage && !rendering;

  /// Pipeline phase of the in-flight render; null while converting before
  /// the first progress report. The UI maps this to a localized label.
  Phase? progressPhase;
  double progressFraction = 0;
  String? error;
  int shapeCount = 0;
  int renderMs = 0;

  /// Source/output facts for the info bar.
  SourceInfo? sourceInfo;
  OutputInfo? outputInfo;

  VtracerConfig _config() {
    return VtracerConfig(
      clustering:
          clustering == UiClustering.bw ? Clustering.binary : Clustering.colorCluster,
      hierarchical: hierarchical == UiHierarchical.cutout
          ? Hierarchical.cutout
          : Hierarchical.stacked,
      mode: switch (mode) {
        UiFitMode.pixel => FitMode.pixel,
        UiFitMode.polygon => FitMode.polygon,
        UiFitMode.spline => FitMode.spline,
      },
      filterSpeckle: filterSpeckle,
      colorPrecision: colorPrecision,
      layerDifference: layerDifference,
      cornerThreshold: cornerThreshold,
      lengthThreshold: lengthThreshold,
      spliceThreshold: spliceThreshold,
      maxColors: maxColors,
      simplify: simplify,
    );
  }

  /// Loads an image from encoded bytes (any format the platform codec knows).
  Future<void> loadImageBytes(Uint8List bytes, {String? name}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw Exception('could not decode image');
    }
    sourceInfo = SourceInfo(
      sniffImageFormat(bytes),
      colorSpaceName(frame.image.colorSpace),
      bytes.length,
    );
    sourceName = name;
    final image = ColorImage(
      Uint8List.fromList(data.buffer.asUint8List()),
      frame.image.width,
      frame.image.height,
    );
    frame.image.dispose();
    codec.dispose();
    await setImage(image);
  }

  /// Loads the built-in synthetic sample (no assets needed).
  Future<void> loadSample() async {
    sourceInfo = const SourceInfo('Sample', 'sRGB', 480 * 360 * 4);
    sourceName = null;
    await setImage(_sampleImage());
  }

  Future<void> setImage(ColorImage image) async {
    _image = image;
    final oldWorker = _worker;
    _worker = await startVtracerWorker(image);
    unawaited(oldWorker?.dispose());
    svg = null;
    shapeCount = 0;
    outputInfo = null;
    dirty = false;
    notifyListeners();
    await render();
  }

  /// Record an option change: the new value shows in the panel immediately,
  /// but the (expensive) conversion only runs on the next [apply].
  void update(void Function() mutate) {
    mutate();
    dirty = true;
    notifyListeners();
  }

  /// Re-render with the current parameters.
  Future<void> apply() => render();

  /// AI auto mode (offline heuristics): extract image features, decide the
  /// parameter set, move the sheet controls onto it, and render.
  ///
  /// The Needle3 model path needs the Cactus C-API FFI binding on Android
  /// (docs/ai_auto/needle3_integration.md §3.1); the heuristic engine is
  /// pure Dart, so the feature works fully offline today.
  Future<void> applyAiAuto() async {
    final image = _image;
    if (image == null || aiBusy) return;

    aiBusy = true;
    notifyListeners();
    try {
      final result = await AutoTuner.local()
          .tune(image, goal: aiGoal, base: _config());
      final d = result.decision;

      clustering = switch (d.clustering) {
        Clustering.binary => UiClustering.bw,
        _ => UiClustering.color,
      };
      hierarchical = d.hierarchical == Hierarchical.cutout
          ? UiHierarchical.cutout
          : UiHierarchical.stacked;
      mode = switch (d.fitMode) {
        FitMode.pixel => UiFitMode.pixel,
        FitMode.polygon => UiFitMode.polygon,
        FitMode.spline => UiFitMode.spline,
      };
      filterSpeckle = d.filterSpeckle;
      colorPrecision = d.colorPrecision;
      layerDifference = d.layerDifference;
      cornerThreshold = d.cornerThreshold;
      lengthThreshold = d.lengthThreshold;
      spliceThreshold = d.spliceThreshold;
      maxColors = d.maxColors;
      simplify = d.simplify;

      aiRationale = d.rationale;
      aiConfidence = d.confidence;
      dirty = true;
      await render();
    } catch (e) {
      error = '$e';
    } finally {
      aiBusy = false;
      notifyListeners();
    }
  }

  Future<void> render() async {
    final worker = _worker;
    if (worker == null || rendering) return;

    rendering = true;
    dirty = false;
    error = null;
    progressPhase = null;
    progressFraction = 0;
    notifyListeners();

    final sw = Stopwatch()..start();
    try {
      final result = await worker.renderSvg(
        _config(),
        onProgress: (p) {
          progressPhase = p.phase;
          progressFraction = p.fraction;
          notifyListeners();
        },
      );
      sw.stop();
      svg = result;
      renderMs = sw.elapsedMilliseconds;
      shapeCount = RegExp('<path').allMatches(result).length;
      outputInfo = _measureOutput(result, renderMs);
    } on CancelledError {
      return; // superseded by a newer render
    } catch (e) {
      error = '$e';
    } finally {
      rendering = false;
      progressFraction = 1;
      notifyListeners();
    }
  }

  /// Extract the info-bar facts from a produced SVG string.
  OutputInfo _measureOutput(String svg, int elapsed) {
    final dims = RegExp(r'width="(\d+)"[^>]*?height="(\d+)"').firstMatch(svg);
    final layers =
        RegExp(r'fill="([^"]+)"').allMatches(svg).map((m) => m.group(1)!).toSet();
    return OutputInfo(
      width: dims != null ? int.parse(dims.group(1)!) : imageWidth,
      height: dims != null ? int.parse(dims.group(2)!) : imageHeight,
      shapes: shapeCount,
      layers: layers.length,
      bytes: svg.length,
      renderMs: elapsed,
    );
  }

  @override
  void dispose() {
    unawaited(_worker?.dispose());
    _worker = null;
    super.dispose();
  }

  /// The synthetic sample scene (gradient sky, sun, mountains).
  static ColorImage _sampleImage() {
    const w = 480, h = 360;
    final img = ColorImage.newWH(w, h);
    final rng = math.Random(7);
    for (var y = 0; y < h; y++) {
      final t = y / h;
      final r = (50 + 110 * t).round();
      final g = (150 - 60 * t).round();
      final b = (230 - 90 * t).round();
      for (var x = 0; x < w; x++) {
        final n = (rng.nextDouble() - 0.5) * 4;
        img.setPixelBytes(
          x,
          y,
          (r + n).clamp(0, 255).round(),
          (g + n).clamp(0, 255).round(),
          (b + n).clamp(0, 255).round(),
          255,
        );
      }
    }
    // Sun.
    const cx = 360, cy = 80;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) < 42) {
          img.setPixelBytes(x, y, 255, 220, 60, 255);
        }
      }
    }
    // Mountains.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final h1 = 180 + 70 * math.sin(x * 0.015) + 30 * math.sin(x * 0.04 + 1.2);
        final h2 = 235 + 55 * math.sin(x * 0.01 + 2.1);
        if (y > h2) {
          img.setPixelBytes(x, y, 70, 60, 80, 255);
        } else if (y > h1) {
          img.setPixelBytes(x, y, 90, 115, 70, 255);
        }
      }
    }
    return img;
  }
}

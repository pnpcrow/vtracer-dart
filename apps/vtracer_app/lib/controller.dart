import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:vtracer/vtracer.dart';

/// Which pipeline options the UI exposes (mirrors the vtracer webapp).
enum UiClustering { color, bw }

enum UiHierarchical { stacked, cutout }

enum UiFitMode { pixel, polygon, spline }

/// App state: the source image, the tuning parameters and the render loop.
///
/// Slider changes re-render through a [Session], so tweaking curve parameters
/// re-uses the cached segmentation; only clustering-relevant changes
/// re-segment.
class AppState extends ChangeNotifier {
  Session? _session;
  ColorImage? _image;

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
  int pathPrecision = 8;

  // --- render state ---------------------------------------------------------
  bool rendering = false;
  String progressLabel = '';
  double progressFraction = 0;
  String? error;
  int shapeCount = 0;
  int renderMs = 0;

  CancelToken? _activeCancel;
  Timer? _debounce;

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
      pathPrecision: pathPrecision,
    );
  }

  /// Loads an image from encoded bytes (any format the platform codec knows).
  Future<void> loadImageBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw Exception('could not decode image');
    }
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
    await setImage(_sampleImage());
  }

  Future<void> setImage(ColorImage image) async {
    _image = image;
    _session = Session(image);
    svg = null;
    shapeCount = 0;
    notifyListeners();
    await render(immediate: true);
  }

  void scheduleRender() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      render(immediate: true);
    });
  }

  Future<void> render({bool immediate = false}) async {
    final session = _session;
    if (session == null) return;

    _activeCancel?.cancel();
    final cancel = CancelToken();
    _activeCancel = cancel;

    rendering = true;
    error = null;
    progressLabel = 'Converting…';
    progressFraction = 0;
    notifyListeners();

    final sw = Stopwatch()..start();
    // Throttle progress notifications: every clustering batch would otherwise
    // rebuild (and re-commit semantics) dozens of times per second, which is
    // both wasted work and a crash trigger for the engine's Windows
    // accessibility bridge (see main.dart — ExcludeSemantics workaround).
    final progressWatch = Stopwatch()..start();
    var lastNotifiedFraction = -1.0;
    try {
      final result = await session.renderSvgAsync(
        _config(),
        cancel: cancel,
        onProgress: (p) {
          progressLabel = switch (p.phase) {
            Phase.segment => 'Clustering',
            Phase.compose => 'Composing',
            Phase.optimize => 'Optimizing',
          };
          progressFraction = p.fraction;
          final settled = (p.fraction - lastNotifiedFraction).abs() >= 0.05;
          if (p.phase == Phase.segment &&
              (settled || progressWatch.elapsedMilliseconds >= 100)) {
            progressWatch.reset();
            lastNotifiedFraction = p.fraction;
            notifyListeners();
          }
        },
      );
      if (cancel.isCancelled) return;
      sw.stop();
      svg = result;
      renderMs = sw.elapsedMilliseconds;
      shapeCount = RegExp('<path').allMatches(result).length;
    } on CancelledError {
      return; // superseded by a newer render
    } catch (e) {
      error = '$e';
    } finally {
      if (!cancel.isCancelled) {
        rendering = false;
        progressFraction = 1;
        notifyListeners();
      }
    }
  }

  void update(void Function() mutate) {
    mutate();
    notifyListeners();
    scheduleRender();
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

import 'package:visioncortex/visioncortex.dart';

import 'config.dart';

import 'frontend/watershed.dart';
import 'ir.dart';
import 'pipeline.dart';
import 'progress.dart';

/// A reusable converter for one image: clusters once, re-renders many times.
///
/// The cached [Segmentation] is refreshed transparently whenever the
/// config's clustering parameters change; the watershed hierarchy is cached
/// separately (it depends only on the image).
class Session {
  final ColorImage _img;

  /// The segmentation and the key it was produced with (null until the
  /// first render).
  (SegmentKey, Segmentation)? _cache;

  /// The image's watershed hierarchy, built lazily on the first watershed
  /// render. Parameter-free, so it never goes stale while the image lives.
  WatershedHierarchy? _hierarchy;

  Session(this._img);

  ColorImage get image => _img;

  bool _stale(SegmentKey key) {
    final cache = _cache;
    return cache == null || cache.$1 != key;
  }

  Segmentation get _segmentation => _cache!.$2;

  /// Produce a fresh segmentation for `cfg`. Watershed goes through the
  /// hierarchy cache (build once, cut cheaply).
  Segmentation _segment(VtracerConfig cfg, Pipeline pipeline) {
    if (cfg.clustering == Clustering.watershed) {
      _hierarchy ??= WatershedHierarchy.build(_img);
      return _hierarchy!.cut(_img, cfg.watershedDetail, cfg.speckleArea());
    }
    return pipeline.segment(_img);
  }

  /// Render to the document IR, re-segmenting only if `cfg`'s clustering
  /// parameters differ from the cached segmentation's.
  VectorDoc render(VtracerConfig cfg) {
    final pipeline = cfg.build();
    final key = cfg.segmentKey();
    if (_stale(key)) {
      _cache = (key, _segment(cfg, pipeline));
    }
    return pipeline.finish(_segmentation);
  }

  /// [render], serialized to an SVG string.
  String renderSvg(VtracerConfig cfg) {
    final pipeline = cfg.build();
    final key = cfg.segmentKey();
    if (_stale(key)) {
      _cache = (key, _segment(cfg, pipeline));
    }
    return pipeline.writer.write(pipeline.finish(_segmentation));
  }

  /// [render] with progress reporting and cancellation.
  VectorDoc renderWithProgress(
      VtracerConfig cfg, CancelToken cancel, void Function(Progress) onProgress) {
    final pipeline = cfg.build();
    final key = cfg.segmentKey();
    if (_stale(key)) {
      Segmentation seg;
      if (cfg.clustering == Clustering.watershed) {
        final ctx = Ctx(cancel, onProgress);
        ctx.check();
        seg = _segment(cfg, pipeline);
        ctx.check();
        ctx.report(Phase.segment, 1.0);
      } else {
        seg = pipeline.segmentWithProgress(_img, cancel, onProgress);
      }
      _cache = (key, seg);
    }
    return pipeline.finishWithProgress(_segmentation, cancel, onProgress);
  }

  /// Cooperative variant of [renderSvg]: yields between clustering batches so
  /// a UI stays responsive without isolates (Flutter-web friendly). Reuses the
  /// cached segmentation when only non-clustering parameters changed.
  Future<String> renderSvgAsync(VtracerConfig cfg,
      {CancelToken? cancel, void Function(Progress)? onProgress}) async {
    final token = cancel ?? CancelToken();
    final sink = onProgress ?? (_) {};
    final pipeline = cfg.build();
    final key = cfg.segmentKey();
    if (_stale(key)) {
      final ctx = Ctx(token, sink);
      final seg = await pipeline.frontend.segmentWithAsync(_img, ctx);
      _cache = (key, seg);
    }
    return pipeline.writer.write(pipeline.finish(_segmentation));
  }

  /// Drop the cached segmentation and hierarchy, forcing the next render to
  /// re-cluster.
  void invalidate() {
    _cache = null;
    _hierarchy = null;
  }
}

import '../../vtracer.dart';

/// A conversion worker bound to one image.
///
/// Implementations own the [Session] (and thus the cached segmentation), so
/// repeated renders with different curve parameters re-use the expensive
/// clustering result. The platform-picked implementation from
/// `package:vtracer/worker.dart` runs the conversion on a background isolate
/// where isolates exist (desktop/mobile) and cooperatively on the current
/// isolate elsewhere (web).
abstract class VtracerWorker {
  /// Render `config` to an SVG string.
  ///
  /// [onProgress] is called with phase/fraction updates; implementations
  /// throttle the rate. Only one render may be in flight at a time — a
  /// second call cancels the first.
  Future<String> renderSvg(VtracerConfig config,
      {void Function(Progress)? onProgress});

  /// Request cancellation of the in-flight [renderSvg], if any. Its future
  /// completes with a [CancelledError] (or an equivalent error) rather than
  /// a result.
  void cancel();

  /// Release the worker's resources. Further renders fail.
  Future<void> dispose();
}

import 'error.dart';

/// A cheaply-clonable cancellation flag shared between the UI and the worker.
class CancelToken {
  final CancelFlag _flag;

  CancelToken() : _flag = CancelFlag();

  CancelToken._(this._flag);

  CancelToken clone() => CancelToken._(_flag);

  void cancel() => _flag.cancelled = true;

  bool get isCancelled => _flag.cancelled;
}

class CancelFlag {
  bool cancelled = false;
}

/// Which pipeline phase a [Progress] update belongs to.
enum Phase {
  /// Frontend segmentation (color clustering) — usually the dominant cost.
  segment,

  /// Compositing the segmentation into shapes.
  compose,

  /// Output optimization passes.
  optimize,
}

/// A progress update: the current [Phase] and how far through it we are
/// (0.0..=1.0, within the phase).
class Progress {
  final Phase phase;
  final double fraction;

  const Progress(this.phase, this.fraction);
}

/// Bundles the cancel token and progress sink threaded through the stages.
class Ctx {
  final CancelToken cancel;
  void Function(Progress) onProgress;

  Ctx(this.cancel, this.onProgress);

  /// Throws [CancelledError] if cancellation has been requested.
  void check() {
    if (cancel.isCancelled) {
      throw const CancelledError();
    }
  }

  /// Publish a progress update for `phase` at `fraction` (clamped 0..1).
  void report(Phase phase, double fraction) {
    onProgress(Progress(phase, fraction.clamp(0.0, 1.0)));
  }
}

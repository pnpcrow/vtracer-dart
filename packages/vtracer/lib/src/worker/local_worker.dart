import 'dart:async';

import '../../vtracer.dart';

import 'worker.dart';

/// Starts a [VtracerWorker] that converts on the current isolate.
///
/// This is the web fallback (Dart isolates are unavailable there): renders
/// use the cooperative pipeline, yielding to the event loop between
/// clustering batches so the UI keeps painting and stays responsive.
Future<VtracerWorker> startVtracerWorker(ColorImage image) async =>
    LocalWorker(image);

/// [VtracerWorker] running in the caller's isolate via the cooperative
/// (yielding) pipeline.
class LocalWorker implements VtracerWorker {
  Session? _session;
  CancelToken? _cancel;

  LocalWorker(ColorImage image) : _session = Session(image);

  @override
  Future<String> renderSvg(VtracerConfig config,
      {void Function(Progress)? onProgress}) async {
    final session = _session;
    if (session == null) {
      throw StateError('worker disposed');
    }
    _cancel?.cancel();
    final token = CancelToken();
    _cancel = token;
    return session.renderSvgAsync(config,
        cancel: token, onProgress: onProgress);
  }

  @override
  void cancel() => _cancel?.cancel();

  @override
  Future<void> dispose() async {
    _cancel?.cancel();
    _session = null;
  }
}

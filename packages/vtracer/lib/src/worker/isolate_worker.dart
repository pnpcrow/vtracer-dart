import 'dart:async';
import 'dart:isolate';

import '../../vtracer.dart';

import 'worker.dart';

/// Starts a [VtracerWorker] backed by a dedicated background isolate.
///
/// The image and the session's cached segmentation live on the worker
/// isolate, so conversions never block the caller's event loop (the Flutter
/// UI isolate in particular) and only the config crosses the boundary on
/// re-renders.
Future<VtracerWorker> startVtracerWorker(ColorImage image) async =>
    IsolateWorker(image);

/// [VtracerWorker] on a background isolate.
///
/// Renders run through the cooperative pipeline with event-loop yields
/// between clustering batches, so a [cancel] message can arrive mid render:
/// the worker aborts, reports cancellation, and moves on to the next queued
/// render.
class IsolateWorker implements VtracerWorker {
  final ReceivePort _results;
  late final StreamSubscription<Object?> _subscription;
  final Completer<SendPort> _commands = Completer();
  final Completer<Isolate> _isolate = Completer();

  Completer<String>? _pending;
  void Function(Progress)? _onProgress;
  int _gen = 0;
  bool _disposed = false;

  /// Spawn the worker isolate for `image`. The returned worker is usable
  /// immediately; the first render awaits the isolate handshake internally.
  IsolateWorker(ColorImage image) : _results = ReceivePort() {
    _subscription = _results.listen((Object? message) {
      if (message is _Handshake) {
        if (!_commands.isCompleted) _commands.complete(message.port);
      } else {
        _onMessage(message);
      }
    }, onError: (Object e) {
      if (!_commands.isCompleted) _commands.completeError(e);
      _failPending(e);
    });

    Isolate.spawn(_workerMain, _Bootstrap(_results.sendPort, image))
        .then(_isolate.complete, onError: (Object e) {
      if (!_commands.isCompleted) _commands.completeError(e);
      _failPending(e);
      if (!_isolate.isCompleted) _isolate.completeError(e);
    });
  }

  @override
  Future<String> renderSvg(VtracerConfig config,
      {void Function(Progress)? onProgress}) {
    if (_disposed) {
      throw StateError('worker disposed');
    }
    // Single-flight: supersede any in-flight render locally, and tell the
    // worker to drop it at the next batch boundary.
    _supersede();

    final gen = ++_gen;
    final completer = Completer<String>();
    _pending = completer;
    _onProgress = onProgress;
    // Register the pending completer before the first await so a cancel()
    // fired synchronously after this call is not lost.
    _commands.future.then((commands) {
      if (_disposed || gen != _gen) {
        if (!completer.isCompleted) {
          completer.completeError(const CancelledError());
        }
        return;
      }
      commands.send(_Render(gen, config));
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    });
    return completer.future;
  }

  @override
  void cancel() {
    if (_pending != null && !_pending!.isCompleted) {
      _supersede();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _supersede();
    // Wait for the handshake (or spawn failure) before closing the results
    // port: closing earlier can race the worker's very first message and
    // drop it, leaving nothing to tear down cleanly.
    try {
      final isolate = await _isolate.future;
      final commands = await _commands.future;
      commands.send(const _Dispose());
      isolate.kill(priority: Isolate.immediate);
    } catch (_) {
      // Spawn already failed; nothing to tear down.
    }
    // Fire-and-forget: awaiting a ReceivePort subscription's cancel future
    // can hang under some embedders (seen with package:test zones); closing
    // the port below already stops delivery.
    unawaited(_subscription.cancel());
    _results.close();
  }

  /// Resolve the in-flight render with [CancelledError] here and ask the
  /// worker to abort it (a queued render may even be cancelled before it
  /// starts; the worker tracks that). The generation is captured eagerly:
  /// reading `_gen` inside the closure could pick up a newer render's gen.
  void _supersede() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final gen = _gen;
    _commands.future.then((commands) {
      commands.send(_Cancel(gen));
    }, onError: (_) {});
    pending.completeError(const CancelledError());
  }

  void _failPending(Object error) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(error);
    }
  }

  void _onMessage(Object? message) {
    switch (message) {
      case _ProgressMsg(:final gen, :final phase, :final fraction):
        if (gen == _gen) {
          _onProgress?.call(Progress(phase, fraction));
        }
      case _ResultMsg(:final gen, :final svg):
        if (gen == _gen) {
          final pending = _pending;
          if (pending != null && !pending.isCompleted) {
            pending.complete(svg);
          }
        }
      case _CancelledMsg(:final gen):
        if (gen == _gen) {
          _failPending(const CancelledError());
        }
      case _ErrorMsg(:final gen, :final message):
        if (gen == _gen) {
          _failPending(StateError(message));
        }
    }
  }
}

// --- worker-isolate protocol ------------------------------------------------

class _Bootstrap {
  final SendPort notify;
  final ColorImage image;
  const _Bootstrap(this.notify, this.image);
}

class _Handshake {
  final SendPort port;
  const _Handshake(this.port);
}

class _Render {
  final int gen;
  final VtracerConfig config;
  const _Render(this.gen, this.config);
}

class _Cancel {
  final int gen;
  const _Cancel(this.gen);
}

class _Dispose {
  const _Dispose();
}

class _ProgressMsg {
  final int gen;
  final Phase phase;
  final double fraction;
  const _ProgressMsg(this.gen, this.phase, this.fraction);
}

class _ResultMsg {
  final int gen;
  final String svg;
  const _ResultMsg(this.gen, this.svg);
}

class _CancelledMsg {
  final int gen;
  const _CancelledMsg(this.gen);
}

class _ErrorMsg {
  final int gen;
  final String message;
  const _ErrorMsg(this.gen, this.message);
}

void _workerMain(_Bootstrap bootstrap) {
  final notify = bootstrap.notify;
  final commands = ReceivePort();
  notify.send(_Handshake(commands.sendPort));

  final session = Session(bootstrap.image);
  int activeGen = -1;
  int cancelledUpTo = -1;
  CancelToken? cancel;

  // Progress throttle: the pipeline reports per clustering batch, which is
  // far more often than any UI wants messages to cross the port.
  final lastSend = Stopwatch()..start();
  var lastFraction = -1.0;
  Phase? lastPhase;

  commands.listen((message) {
    switch (message) {
      case _Cancel(:final gen):
        if (gen > cancelledUpTo) cancelledUpTo = gen;
        if (gen == activeGen) cancel?.cancel();
      case _Render(:final gen, :final config):
        if (gen <= cancelledUpTo) {
          // Superseded before it even started.
          notify.send(_CancelledMsg(gen));
          return;
        }
        activeGen = gen;
        cancel = CancelToken();
        lastSend.reset();
        lastFraction = -1.0;
        lastPhase = null;
        () async {
          final token = cancel!;
          try {
            final svg = await session.renderSvgAsync(config, cancel: token,
                onProgress: (p) {
              final phaseChanged = p.phase != lastPhase;
              if (phaseChanged ||
                  p.fraction == 1.0 ||
                  (p.fraction - lastFraction).abs() >= 0.02 ||
                  lastSend.elapsedMilliseconds >= 50) {
                lastPhase = p.phase;
                lastFraction = p.fraction;
                lastSend.reset();
                notify.send(_ProgressMsg(gen, p.phase, p.fraction));
              }
            });
            notify.send(_ResultMsg(gen, svg));
          } on CancelledError {
            notify.send(_CancelledMsg(gen));
          } catch (e) {
            notify.send(_ErrorMsg(gen, '$e'));
          }
        }();
      case _Dispose():
        commands.close();
    }
  });
}

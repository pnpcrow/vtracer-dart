/// Platform-picked conversion worker: a background-isolate [VtracerWorker]
/// where isolates exist (desktop, mobile, CLI) and a cooperative
/// current-isolate worker on the web.
///
/// ```dart
/// import 'package:vtracer/worker.dart';
///
/// final worker = await startVtracerWorker(image);
/// final svg = await worker.renderSvg(config, onProgress: (p) => ...);
/// await worker.dispose();
/// ```
library;

export 'src/worker/worker.dart';
export 'src/worker/local_worker.dart'
    if (dart.library.io) 'src/worker/isolate_worker.dart';

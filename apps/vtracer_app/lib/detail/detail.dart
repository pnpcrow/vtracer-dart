/// Full-detail viewing of a trace: a separate OS window on desktop (its own
/// Flutter engine, so raster work stays off the main UI) and a new browser
/// tab (native SVG rendering) on the web.
library;

export 'detail_native.dart'
    if (dart.library.html) 'detail_web.dart'
    if (dart.library.js_interop) 'detail_web.dart';

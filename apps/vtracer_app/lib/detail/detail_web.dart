import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The web has no multi-window Flutter engines; the main app runs here.
Future<bool> maybeRunDetailWindow() async => false;

/// Opens the SVG full-detail in a new browser tab via a blob URL.
///
/// The tab renders the SVG with the browser's own (native, vector)
/// renderer — no Flutter raster work at all.
Future<void> openDetailView(String svg) async {
  final blob = web.Blob(
    <JSAny>[svg.toJS].toJS,
    web.BlobPropertyBag(type: 'image/svg+xml'),
  );
  final url = web.URL.createObjectURL(blob);
  web.window.open(url, '_blank');
}

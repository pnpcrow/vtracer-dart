import 'dart:async';

import 'package:flutter/services.dart';

/// An image handed over from another app: the raw encoded bytes plus the
/// display name reported by the sending app (may be absent).
class IncomingImage {
  const IncomingImage({required this.bytes, this.name});

  final Uint8List bytes;
  final String? name;
}

/// Bridge to the Android host activity.
///
/// - Image hand-off intents (`ACTION_VIEW` / `ACTION_SEND` with `image/*`)
///   are delivered here: [getInitialImage] pulls the cold-start payload the
///   activity was launched with, and [onImage] receives warm-start
///   deliveries pushed from the activity's `onNewIntent`.
/// - [saveSvgToDownloads] writes into the public Downloads collection via
///   MediaStore — no storage permission of any kind is required.
class AndroidIntents {
  AndroidIntents._();

  static const MethodChannel _channel = MethodChannel('vtracer_android/platform');

  /// Set by the home page; invoked for every image arriving via intent.
  static void Function(IncomingImage image)? onImage;

  static bool _wired = false;

  static void _ensureHandler() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onImageIntent') {
        final image = _imageFrom(call.arguments);
        if (image != null) onImage?.call(image);
      }
      return null;
    });
  }

  /// Directory holding the APK's bundled native libraries — the embedded
  /// Needle3 engine lives here as `libneedle.so`. Null when unavailable.
  static Future<String?> nativeLibraryDir() async {
    try {
      return await _channel.invokeMethod<String>('getNativeLibraryDir');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // The host activity predates the getNativeLibraryDir handler (stale
      // build) — the app must be rebuilt for the embedded engine.
      return null;
    }
  }

  /// Pulls the payload the activity was started with (cold start), if any.
  static Future<IncomingImage?> getInitialImage() async {    _ensureHandler();
    try {
      return _imageFrom(await _channel.invokeMethod<Object?>('getInitialImage'));
    } on PlatformException {
      return null;
    }
  }

  /// Writes [svgBytes] into the public Downloads directory (MediaStore),
  /// returning the display name the file was actually stored under —
  /// MediaStore uniquifies on collision by appending a numeric suffix.
  static Future<String> saveSvgToDownloads(
    Uint8List svgBytes,
    String fileName,
  ) async {
    return await _channel.invokeMethod<String>('saveSvgToDownloads', {
          'bytes': svgBytes,
          'fileName': fileName,
        }) ??
        fileName;
  }

  static IncomingImage? _imageFrom(Object? args) {
    if (args is! Map) return null;
    final bytes = args['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    final name = args['name'];
    return IncomingImage(
      bytes: bytes,
      name: name is String && name.isNotEmpty ? name : null,
    );
  }
}

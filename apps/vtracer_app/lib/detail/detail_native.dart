import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../preview.dart';

/// Whether this engine was launched as a detail-viewer sub-window, and if
/// so, renders it. Returns true when the sub-window app was started (the
/// caller must then not start the main app).
Future<bool> maybeRunDetailWindow() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    final raw = controller.arguments;
    if (raw.isEmpty) return false;
    final Object args;
    try {
      args = jsonDecode(raw);
    } on FormatException {
      return false;
    }
    if (args is Map<String, dynamic> && args['kind'] == 'detail') {
      runApp(DetailViewerApp(io.File(args['path'] as String)));
      return true;
    }
    return false;
  } catch (_) {
    // Main window, or a platform without multi-window support.
    return false;
  }
}

/// Opens the SVG in a new OS window for full-detail viewing.
///
/// The sub-window runs its own Flutter engine, so the (potentially heavy)
/// raster work it does on resize never touches the main UI. The SVG is
/// handed over as a temp file — window arguments are not meant to carry
/// multi-megabyte payloads.
Future<void> openDetailView(String svg) async {
  final file = io.File(
    '${io.Directory.systemTemp.path}'
    '${io.Platform.pathSeparator}'
    'vtracer-detail-${DateTime.now().microsecondsSinceEpoch}.svg',
  );
  await file.writeAsString(svg, flush: true);
  final controller = await WindowController.create(WindowConfiguration(
    hiddenAtLaunch: false,
    arguments: jsonEncode({'kind': 'detail', 'path': file.path}),
  ));
  await controller.show();
}

/// The detail-viewer window: fits the trace to this window, re-rasterizing
/// (debounced) on resize, capped at the monitor's full resolution.
class DetailViewerApp extends StatelessWidget {
  final io.File file;

  const DetailViewerApp(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VTracer — detail',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        // Same engine-bug workaround as the main window (see main.dart):
        // empty the semantics stream in this engine too.
        body: ExcludeSemantics(
          child: _DetailPage(file: file),
        ),
      ),
    );
  }
}

class _DetailPage extends StatefulWidget {
  final io.File file;

  const _DetailPage({required this.file});

  @override
  State<_DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<_DetailPage> with WidgetsBindingObserver {
  String? _svg;
  ui.Image? _image;
  String? _error;
  Timer? _reraster;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.file.readAsString().then((svg) {
      if (!mounted) return;
      setState(() => _svg = svg);
      _rasterize();
    }, onError: (Object e) {
      if (mounted) setState(() => _error = 'could not load: $e');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reraster?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Window resized: re-raster to the new size shortly after the user
    // stops dragging (each resize tick only re-scales the old raster).
    _reraster?.cancel();
    _reraster = Timer(const Duration(milliseconds: 250), _rasterize);
  }

  void _rasterize() {
    final svg = _svg;
    if (svg == null) return;
    final view = View.of(context);
    final window = view.physicalSize;
    final monitor = monitorSize(view);
    final target = ui.Size(
      math.min(window.width, monitor.width),
      math.min(window.height, monitor.height),
    );
    if (target.width < 1 || target.height < 1) return;
    rasterizeSvg(svg, target).then((image) {
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _image;
      setState(() => _image = image);
      old?.dispose();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          RawImage(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          )
        else if (_error != null)
          Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
        else
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned(
          left: 12,
          bottom: 12,
          child: Text(
            _svg == null ? '' : '${_svg!.length} chars',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

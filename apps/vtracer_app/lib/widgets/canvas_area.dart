import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../controller.dart';

/// The canvas: a drop zone until an image is loaded, then the traced SVG.
class CanvasArea extends StatefulWidget {
  final AppState state;

  const CanvasArea({super.key, required this.state});

  @override
  State<CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<CanvasArea> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return DropTarget(
      onDragDone: (details) async {
        final file = details.files.first;
        try {
          final bytes = await file.readAsBytes();
          await state.loadImageBytes(bytes);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(content: Text('Could not load image: $e')),
          );
        }
      },
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      child: Stack(
        children: [
          // Checkerboard background so transparency is visible.
          Container(
            color: _hovering ? Colors.blue.withValues(alpha: 0.06) : Colors.white,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: state.hasImage ? _result(context) : _dropHint(context),
          ),
          if (state.rendering) _progressOverlay(context),
          if (state.error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: Colors.red.shade700,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.error!,
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dropHint(BuildContext context) {
    return Container(
      width: 420,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      decoration: BoxDecoration(
        border: Border.all(
          color: _hovering ? Colors.blue : Colors.black45,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_hovering ? Icons.file_download : Icons.image_outlined,
              size: 48, color: _hovering ? Colors.blue : Colors.black54),
          const SizedBox(height: 12),
          Text(
            _hovering ? 'Drop to trace' : 'Drag an image here',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('or use “Select file” / “Try a sample” on the left'),
        ],
      ),
    );
  }

  Widget _result(BuildContext context) {
    final svg = widget.state.svg;
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          color: Colors.white,
        ),
        child: svg == null
            ? const Center(child: CircularProgressIndicator())
            : SvgPicture.string(
                svg,
                fit: BoxFit.contain,
                placeholderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              ),
      );
    });
  }

  Widget _progressOverlay(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.black87,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.state.progressLabel} '
                '${(widget.state.progressFraction * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: widget.state.progressFraction,
                minHeight: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vtracer/vtracer.dart' show Phase;

import 'controller.dart';
import 'intents.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';
import 'theme.dart';
import 'widgets/options_sheet.dart';
import 'widgets/settings_sheet.dart';
import 'widgets/trace_canvas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsController.load();
  runApp(VtracerApp(settings: settings));
}

/// VTracer for Android — raster to vector (SVG) conversion using the pure
/// Dart port of the vtracer pipeline.
class VtracerApp extends StatelessWidget {
  const VtracerApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        title: 'VTracer',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        locale: settings.localeOverride,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: HomePage(settings: settings),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.settings});

  final SettingsController settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppState _state = AppState();
  final ImagePicker _picker = ImagePicker();

  /// True while an incoming image is being decoded (source → ColorImage).
  bool _loadingImage = false;

  @override
  void initState() {
    super.initState();
    // Images arriving from other apps (share / open-with intents).
    AndroidIntents.onImage = _handleIncomingImage;
    unawaited(_pullInitialIntentImage());
  }

  @override
  void dispose() {
    AndroidIntents.onImage = null;
    _state.dispose();
    super.dispose();
  }

  /// The activity may have been started by an image intent (cold start);
  /// the platform side buffers the payload until we ask for it here.
  Future<void> _pullInitialIntentImage() async {
    final image = await AndroidIntents.getInitialImage();
    if (image != null && mounted) {
      await _handleIncomingImage(image);
    }
  }

  Future<void> _handleIncomingImage(IncomingImage image) async {
    setState(() => _loadingImage = true);
    try {
      await _state.loadImageBytes(image.bytes, name: image.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.snackbarLoadFailed('$e'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingImage = false);
    }
  }

  /// Gallery picking goes through the system photo picker (image_picker):
  /// on Android 13+ that is the platform photo picker, on older versions a
  /// system picker intent — neither requires any storage permission.
  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (file == null) return; // user cancelled
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _handleIncomingImage(IncomingImage(bytes: bytes, name: file.name));
  }

  Future<void> _apply() async {
    await _state.apply();
  }

  /// Writes the traced SVG into the public Downloads directory through the
  /// platform channel (MediaStore — no storage permission involved).
  Future<void> _saveSvg() async {
    final svg = _state.svg;
    if (svg == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final name = suggestedSaveName(_state.sourceName, DateTime.now());
    try {
      final saved =
          await AndroidIntents.saveSvgToDownloads(utf8.encode(svg), name);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.snackbarSavedToDownloads(saved))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.snackbarSaveFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final canApply =
            _state.hasImage && !_state.rendering && !_loadingImage;
        final canSave =
            _state.svg != null && !_state.rendering && !_loadingImage;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.appTitle),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: l10n.optionsTitle,
                onPressed: () => showOptionsSheet(context, _state),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: l10n.settingsTitle,
                onPressed: () => showSettingsSheet(context, widget.settings),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              if (_loadingImage) const LinearProgressIndicator(minHeight: 3),
              if (_state.rendering) _ProgressRow(state: _state),
              Expanded(
                child: TraceCanvas(
                  state: _state,
                  onPickGallery: _pickFromGallery,
                  onTrySample: () => _state.loadSample(),
                ),
              ),
              if (_state.needsApply) _DirtyBanner(onApply: _apply),
              if (_state.hasImage) _InfoStrip(state: _state),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed:
                          _loadingImage || _state.rendering
                              ? null
                              : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l10n.pickFromGallery),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: canApply ? _apply : null,
                      child: Text(l10n.panelApply),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: canSave ? _saveSvg : null,
                      child: Text(l10n.saveSvg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Indeterminate-until-first-tick progress with the current pipeline phase.
class _ProgressRow extends StatelessWidget {
  final AppState state;

  const _ProgressRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final phase = switch (state.progressPhase) {
      Phase.segment => l10n.progressPhaseSegment,
      Phase.compose => l10n.progressPhaseCompose,
      Phase.optimize => l10n.progressPhaseOptimize,
      null => l10n.progressConverting,
    };
    final fraction = state.progressFraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: fraction > 0 && fraction < 1 ? fraction : null,
          minHeight: 3,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(phase, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Shown while parameters have changed but the trace has not been updated.
class _DirtyBanner extends StatelessWidget {
  final VoidCallback onApply;

  const _DirtyBanner({required this.onApply});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.bannerDirty,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
              ),
            ),
            TextButton(onPressed: onApply, child: Text(l10n.panelApply)),
          ],
        ),
      ),
    );
  }
}

/// The compact info strip: source facts on the first line, output facts on
/// the second (a condensed version of the desktop app's summary bar).
class _InfoStrip extends StatelessWidget {
  final AppState state;

  const _InfoStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context).textTheme.bodySmall;
    final info = state.sourceInfo;
    final input = info == null
        ? ''
        : '${info.format} · ${state.imageWidth}×${state.imageHeight}'
            ' · ${formatBytes(info.bytes)}';

    final out = state.outputInfo;
    final output = out == null
        ? l10n.infoPending
        : '${l10n.infoShapes(out.shapes)} · ${l10n.infoLayers(out.layers)}'
            ' · ${formatBytes(out.bytes)} · ${out.renderMs} ms';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.infoInput}: $input',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme,
          ),
          Text(
            '${l10n.infoOutput}: $output',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme,
          ),
        ],
      ),
    );
  }
}

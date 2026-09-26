import 'dart:io';

import 'needle3.dart';

/// Embedded Needle3 runtime: a bundled engine executable plus the `.cact`
/// model that ship inside the app itself.
///
/// The Cactus Needle3 repo distributes the engine as a static library and a
/// self-contained executable (no .so/.dll), so "embedded" means the app
/// carries both files and spawns the engine itself — no separate server,
/// no manual installation. Decision requests go through
/// [Needle3ProcessRuntime]; see docs/ai_auto/needle3_integration.md.
class Needle3EmbeddedRuntime implements Needle3Runtime {
  /// Absolute path of the engine executable (`needle.exe` on Windows,
  /// `needle` elsewhere, or `libneedle.so` in jniLibs on Android).
  final String enginePath;

  /// Absolute path of the extracted `needle3.cact` model file.
  final String modelPath;

  /// Response token limit passed as `--max` (engine default 512).
  final int maxNewTokens;

  final Duration timeout;

  Needle3EmbeddedRuntime({
    required this.enginePath,
    required this.modelPath,
    this.maxNewTokens = 1024,
    this.timeout = const Duration(minutes: 3),
  });

  late final Needle3ProcessRuntime _process = Needle3ProcessRuntime(
    modelPath: modelPath,
    executable: enginePath,
    maxNewTokens: maxNewTokens,
    timeout: timeout,
  );

  @override
  Future<Needle3Answer> run(Needle3Invocation invocation) =>
      _process.run(invocation);
}

/// Materializes a bundled Needle3 (engine + model) into a writable
/// directory and returns a ready [Needle3EmbeddedRuntime].
///
/// Flutter apps inject their asset loader, e.g.
///
/// ```dart
/// Needle3BundleInstaller.install(
///   directory: (await getApplicationSupportDirectory()).path,
///   readAsset: (name) async =>
///       (await rootBundle.load('packages/vtracer_ai/assets/needle3/$name'))
///           .buffer
///           .asUint8List(),
///   engineAssetName: 'needle-windows-x86_64.exe',
///   engineFileName: 'needle.exe',
/// );
/// ```
///
/// Extraction is idempotent: a file is (re)written only when missing, empty,
/// or of a different size than the bundled copy, so the 35 MB model is
/// unpacked once.
class Needle3BundleInstaller {
  /// Default model file name inside the bundle.
  static const modelAssetName = 'needle3.cact';

  /// Windows engine shipped in `packages/vtracer_ai/assets/needle3/`.
  static const windowsEngineAssetName = 'needle-windows-x86_64.exe';

  static Future<Needle3EmbeddedRuntime> install({
    required String directory,
    required Future<List<int>> Function(String assetName) readAsset,
    String? engineAssetName,
    String? engineFileName,
    String? enginePath,
    String modelAssetName = modelAssetName,
    String modelFileName = modelAssetName,
    bool force = false,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);

    // The engine either comes from the bundle (extracted like the model) or
    // from an external location already on disk (e.g. Android's jniLibs,
    // where executables must live to be runnable).
    String resolvedEnginePath;
    if (enginePath != null) {
      resolvedEnginePath = enginePath;
    } else {
      if (engineAssetName == null || engineFileName == null) {
        throw ArgumentError('engineAssetName+engineFileName or enginePath required');
      }
      resolvedEnginePath =
          '${dir.path}${Platform.pathSeparator}$engineFileName';
      await _materialize(
          dir: dir, assetName: engineAssetName, targetPath: resolvedEnginePath, readAsset: readAsset, force: force);
    }
    final modelPath = '${dir.path}${Platform.pathSeparator}$modelFileName';
    await _materialize(
        dir: dir, assetName: modelAssetName, targetPath: modelPath, readAsset: readAsset, force: force);

    return Needle3EmbeddedRuntime(
      enginePath: resolvedEnginePath,
      modelPath: modelPath,
      timeout: timeout,
    );
  }

  static Future<void> _materialize({
    required Directory dir,
    required String assetName,
    required String targetPath,
    required Future<List<int>> Function(String assetName) readAsset,
    required bool force,
  }) async {
    final target = File(targetPath);
    if (!force && await target.exists()) {
      final stat = await target.stat();
      if (stat.size > 0) return; // already extracted
    }
    final bytes = await readAsset(assetName);
    if (bytes.isEmpty) {
      throw Needle3Exception('bundled asset $assetName is empty');
    }
    await target.writeAsBytes(bytes, flush: true);
  }
}

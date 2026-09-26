import 'dart:io';

import 'package:test/test.dart';
import 'package:vtracer_ai/vtracer_ai.dart';

void main() {
  test('install materializes the bundle once and returns a runtime', () async {
    final dir = await Directory.systemTemp.createTemp('vtracer_ai_bundle');
    addTearDown(() => dir.delete(recursive: true));

    var reads = 0;
    Future<List<int>> readAsset(String name) async {
      reads++;
      return List.filled(name == Needle3BundleInstaller.modelAssetName ? 16 : 4, 7);
    }

    final runtime = await Needle3BundleInstaller.install(
      directory: dir.path,
      readAsset: readAsset,
      engineAssetName: Needle3BundleInstaller.windowsEngineAssetName,
      engineFileName: 'needle.exe',
    );

    expect(File(runtime.enginePath).lengthSync(), 4);
    expect(File(runtime.modelPath).lengthSync(), 16);
    expect(reads, 2);
    expect(runtime.enginePath, endsWith('needle.exe'));
    expect(runtime.modelPath, endsWith('needle3.cact'));

    // Second install: files already extracted, no re-read.
    await Needle3BundleInstaller.install(
      directory: dir.path,
      readAsset: readAsset,
      engineAssetName: Needle3BundleInstaller.windowsEngineAssetName,
      engineFileName: 'needle.exe',
    );
    expect(reads, 2);
  });

  test('install re-extracts when the target is empty or force is set', () async {
    final dir = await Directory.systemTemp.createTemp('vtracer_ai_bundle');
    addTearDown(() => dir.delete(recursive: true));

    Future<List<int>> readAsset(String name) async => List.filled(8, 1);
    final opts = (
      directory: dir.path,
      engineAssetName: Needle3BundleInstaller.windowsEngineAssetName,
      engineFileName: 'needle.exe',
    );

    await Needle3BundleInstaller.install(
      directory: opts.directory,
      readAsset: readAsset,
      engineAssetName: opts.engineAssetName,
      engineFileName: opts.engineFileName,
    );
    // Corrupt: truncate the model on disk.
    File('${dir.path}${Platform.pathSeparator}needle3.cact').writeAsBytesSync([]);
    await Needle3BundleInstaller.install(
      directory: opts.directory,
      readAsset: readAsset,
      engineAssetName: opts.engineAssetName,
      engineFileName: opts.engineFileName,
    );
    expect(File('${dir.path}${Platform.pathSeparator}needle3.cact').lengthSync(), 8);

    // force: rewrite even when present.
    await Needle3BundleInstaller.install(
      directory: opts.directory,
      readAsset: readAsset,
      engineAssetName: opts.engineAssetName,
      engineFileName: opts.engineFileName,
      force: true,
    );
    expect(File('${dir.path}${Platform.pathSeparator}needle.exe').lengthSync(), 8);
  });

  test('embedded runtime surfaces engine failures as Needle3Exception', () async {
    final dir = await Directory.systemTemp.createTemp('vtracer_ai_bundle');
    addTearDown(() => dir.delete(recursive: true));
    final runtime = Needle3EmbeddedRuntime(
      enginePath: '${dir.path}${Platform.pathSeparator}missing.exe',
      modelPath: '${dir.path}${Platform.pathSeparator}missing.cact',
      timeout: const Duration(seconds: 5),
    );
    await expectLater(
      runtime.run(const Needle3Invocation(system: 's', prompt: 'p', tool: {})),
      throwsA(isA<Needle3Exception>()),
    );
  });
}

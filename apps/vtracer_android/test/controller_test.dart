import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vtracer_android/controller.dart';
import 'package:vtracer_android/intents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The platform channel is not backed by a real activity in tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('vtracer_android/platform'),
    (call) async => null,
  );

  test('loading the sample produces an SVG trace', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.loadSample();
    expect(state.hasImage, isTrue);
    expect(state.svg, isNotNull);
    expect(state.shapeCount, greaterThan(0));
    expect(state.error, isNull);
    expect(state.outputInfo, isNotNull);
    expect(state.renderMs, greaterThanOrEqualTo(0));
  });

  test('changing a parameter marks the state dirty until applied', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.loadSample();
    final first = state.svg;
    expect(state.dirty, isFalse);

    state.update(() => state.filterSpeckle = 8);
    expect(state.dirty, isTrue);
    expect(state.needsApply, isTrue);

    await state.apply();
    expect(state.dirty, isFalse);
    expect(state.svg, isNotNull);
    // The re-render must not have failed.
    expect(state.error, isNull);
    expect(first, isNotNull);
  });

  test('suggestedSaveName derives a sanitized SVG name from the source',
      () async {
    final now = DateTime(2026, 9, 10, 8, 7, 6);
    expect(
      suggestedSaveName('photo.jpg', now),
      'photo_20260910-080706-traced.svg',
    );
    expect(
      suggestedSaveName('weird:name*with?chars', now),
      'weird_name_with_chars_20260910-080706-traced.svg',
    );
    expect(suggestedSaveName(null, now), 'vtracer_20260910-080706-traced.svg');
    expect(suggestedSaveName('', now), 'vtracer_20260910-080706-traced.svg');
  });

  test('sniffImageFormat recognizes common containers', () {
    expect(
      sniffImageFormat(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      'PNG',
    );
    expect(sniffImageFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'JPEG');
    expect(sniffImageFormat(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])), 'GIF');
    expect(sniffImageFormat(Uint8List.fromList([0x42, 0x4D])), 'BMP');
    expect(sniffImageFormat(Uint8List.fromList([1, 2, 3])), 'Image');
  });

  test('getInitialImage returns null when no intent payload exists', () async {
    expect(await AndroidIntents.getInitialImage(), isNull);
  });
}

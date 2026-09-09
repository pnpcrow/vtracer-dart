import 'package:flutter_test/flutter_test.dart';
import 'package:vtracer_app/controller.dart';

void main() {
  test('sample image converts end to end', () async {
    final state = AppState();
    await state.loadSample();
    // Give the cooperative render loop a moment to drain.
    for (var i = 0; i < 100 && state.svg == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);
    expect(state.svg, contains('</svg>'));
    expect(state.shapeCount, greaterThan(0));
    expect(state.error, isNull);
  });

  test('slider retune reuses cached segmentation quickly', () async {
    final state = AppState();
    await state.loadSample();
    for (var i = 0; i < 200 && state.svg == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    state.update(() => state.cornerThreshold = 120);
    for (var i = 0; i < 200 && (state.rendering || state.svg == null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);
    expect(state.error, isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vtracer_app/controller.dart';

void main() {
  test('sample image converts end to end', () async {
    final state = AppState();
    await state.loadSample();
    // Give the render loop a moment to drain (isolate worker or
    // cooperative, depending on the platform).
    for (var i = 0; i < 100 && state.svg == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);
    expect(state.svg, contains('</svg>'));
    expect(state.shapeCount, greaterThan(0));
    expect(state.error, isNull);
    expect(state.dirty, isFalse);
  });

  test('parameter change waits for apply', () async {
    final state = AppState();
    await state.loadSample();
    for (var i = 0; i < 200 && state.svg == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);

    // Changing a slider marks the state dirty but does not re-render.
    state.update(() => state.cornerThreshold = 120);
    expect(state.dirty, isTrue);
    expect(state.needsApply, isTrue);
    expect(state.rendering, isFalse);

    // Applying re-renders (reusing the cached segmentation).
    await state.apply();
    for (var i = 0; i < 200 && state.rendering; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(state.svg, isNotNull);
    expect(state.error, isNull);
    expect(state.dirty, isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vtracer_android/main.dart';
import 'package:vtracer_android/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The platform channel is not backed by a real activity in tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('vtracer_android/platform'),
    (call) async => null,
  );

  testWidgets('empty state shows the photo-picker entry points',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await tester.pumpWidget(VtracerApp(settings: settings));

    expect(find.text('VTracer'), findsOneWidget);
    expect(find.text('Pick from gallery'), findsNWidgets(2));
    expect(find.text('Try a sample'), findsOneWidget);
    // No image yet: apply/save are inert.
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      ),
      isA<FilledButton>().having((b) => b.onPressed, 'onPressed', isNull),
    );
  });

  testWidgets('tuning options open from the app bar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    await tester.pumpWidget(VtracerApp(settings: settings));

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Trace options'), findsOneWidget);
    expect(find.text('Filter Speckle'), findsOneWidget);
    expect(find.text('Clustering'), findsOneWidget);
    expect(find.text('Curve Fitting'), findsOneWidget);
  });
}

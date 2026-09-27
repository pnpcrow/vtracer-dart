import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vtracer_android/controller.dart';
import 'package:vtracer_android/l10n/app_localizations.dart';
import 'package:vtracer_android/main.dart';
import 'package:vtracer_android/settings.dart';
import 'package:vtracer_android/widgets/trace_canvas.dart';

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

  testWidgets('canvas mounts with a loaded trace without framework errors',
      (tester) async {
    // Regression: TraceCanvas recreated while an SVG was already loaded ran
    // previewCap() -> View.of() synchronously from initState(), which the
    // framework forbids. The cap must be read in didChangeDependencies and
    // the initial bake deferred to a post-frame callback.
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    addTearDown(state.dispose);
    state
      ..sourceInfo = const SourceInfo('Sample', 'sRGB', 1)
      ..svg = 'not-a-valid-svg'; // bake attempt fails harmlessly

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TraceCanvas(
            state: state,
            onPickGallery: () {},
            onTrySample: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

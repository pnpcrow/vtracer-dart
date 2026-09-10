import 'package:flutter/material.dart';

/// Canvas-specific colors that must adapt to light/dark: the checkerboard
/// "paper" behind the traced SVG and the drop-target hint chrome.
@immutable
class CanvasColors extends ThemeExtension<CanvasColors> {
  const CanvasColors({
    required this.paper,
    required this.checker,
    required this.paperBorder,
    required this.dropBorder,
    required this.dropBackdrop,
  });

  /// Base square of the transparency checkerboard.
  final Color paper;

  /// Alternate checkerboard square.
  final Color checker;

  final Color paperBorder;
  final Color dropBorder;
  final Color dropBackdrop;

  @override
  CanvasColors copyWith({
    Color? paper,
    Color? checker,
    Color? paperBorder,
    Color? dropBorder,
    Color? dropBackdrop,
  }) {
    return CanvasColors(
      paper: paper ?? this.paper,
      checker: checker ?? this.checker,
      paperBorder: paperBorder ?? this.paperBorder,
      dropBorder: dropBorder ?? this.dropBorder,
      dropBackdrop: dropBackdrop ?? this.dropBackdrop,
    );
  }

  @override
  CanvasColors lerp(CanvasColors? other, double t) {
    if (other is! CanvasColors) return this;
    return CanvasColors(
      paper: Color.lerp(paper, other.paper, t)!,
      checker: Color.lerp(checker, other.checker, t)!,
      paperBorder: Color.lerp(paperBorder, other.paperBorder, t)!,
      dropBorder: Color.lerp(dropBorder, other.dropBorder, t)!,
      dropBackdrop: Color.lerp(dropBackdrop, other.dropBackdrop, t)!,
    );
  }
}

/// App-wide Material themes. Both modes share the indigo seed color of the
/// original single-theme app.
class AppTheme {
  static const _seed = Color(0xFF3F51B5);

  static const _canvasLight = CanvasColors(
    paper: Colors.white,
    checker: Color(0xFFEFEFF2),
    paperBorder: Colors.black26,
    dropBorder: Colors.black45,
    dropBackdrop: Colors.white,
  );

  static const _canvasDark = CanvasColors(
    paper: Color(0xFF202024),
    checker: Color(0xFF2A2A30),
    paperBorder: Colors.white24,
    dropBorder: Colors.white38,
    dropBackdrop: Color(0xFF17171A),
  );

  static ThemeData light() => _base(Brightness.light).copyWith(
        extensions: <ThemeExtension<dynamic>>[_canvasLight],
      );

  static ThemeData dark() => _base(Brightness.dark).copyWith(
        extensions: <ThemeExtension<dynamic>>[_canvasDark],
      );

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      sliderTheme: const SliderThemeData(
        trackHeight: 16,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
    );
  }
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'VTracer';

  @override
  String get pickFromGallery => 'Pick from gallery';

  @override
  String get trySample => 'Try a sample';

  @override
  String get panelApply => 'Apply';

  @override
  String get saveSvg => 'Save SVG';

  @override
  String get optionsTitle => 'Trace options';

  @override
  String get canvasEmptyTitle => 'No image yet';

  @override
  String get canvasEmptyHint =>
      'Pick a photo from the gallery, or share an image from another app.';

  @override
  String get bannerDirty =>
      'Parameters changed — press Apply to update the trace';

  @override
  String get groupClustering => 'Clustering';

  @override
  String get groupClusteringDesc =>
      'How pixels are segmented and grouped into color layers.';

  @override
  String get clusterBw => 'B/W';

  @override
  String get clusterBwTip => 'Black & White (Binary Image)';

  @override
  String get clusterColor => 'Color';

  @override
  String get clusterColorTip => 'True Color Image';

  @override
  String get hierarchyCutout => 'Cutout';

  @override
  String get hierarchyCutoutTip => 'Shapes disjoint with others';

  @override
  String get hierarchyStacked => 'Stacked';

  @override
  String get hierarchyStackedTip => 'Stack shapes on top of another';

  @override
  String get sliderFilterSpeckle => 'Filter Speckle';

  @override
  String get sliderFilterSpeckleHint => '(Cleaner)';

  @override
  String get sliderFilterSpeckleDesc =>
      'Discard patches smaller than this many pixels.';

  @override
  String get sliderColorPrecision => 'Color Precision';

  @override
  String get sliderColorPrecisionHint => '(More accurate)';

  @override
  String get sliderColorPrecisionDesc =>
      'Number of significant bits to use in an RGB channel.';

  @override
  String get sliderGradientStep => 'Gradient Step';

  @override
  String get sliderGradientStepHint => '(Less layers)';

  @override
  String get sliderGradientStepDesc =>
      'Color difference between gradient layers.';

  @override
  String get groupCurveFitting => 'Curve Fitting';

  @override
  String get groupCurveFittingDesc =>
      'How clusters are converted into vector shapes.';

  @override
  String get fitPixel => 'Pixel';

  @override
  String get fitPixelTip => 'Exact cluster boundary';

  @override
  String get fitPolygon => 'Polygon';

  @override
  String get fitPolygonTip => 'Simplify to Polygon';

  @override
  String get fitSpline => 'Spline';

  @override
  String get fitSplineTip => 'Smooth and Curve-fit';

  @override
  String get sliderCornerThreshold => 'Corner Threshold';

  @override
  String get sliderCornerThresholdHint => '(Smoother)';

  @override
  String get sliderCornerThresholdDesc =>
      'Minimum momentary angle (degrees) to be considered a corner.';

  @override
  String get sliderSegmentLength => 'Segment Length';

  @override
  String get sliderSegmentLengthHint => '(More coarse)';

  @override
  String get sliderSegmentLengthDesc =>
      'Subdivide until all segments are shorter than this length.';

  @override
  String get sliderSpliceThreshold => 'Splice Threshold';

  @override
  String get sliderSpliceThresholdHint => '(More accurate)';

  @override
  String get sliderSpliceThresholdDesc =>
      'Minimum angle displacement (degrees) to splice two curves.';

  @override
  String get infoInput => 'Input';

  @override
  String get infoOutput => 'Output';

  @override
  String get infoPending => 'pending…';

  @override
  String infoShapes(int count) {
    return '$count shapes';
  }

  @override
  String infoLayers(int count) {
    return '$count layers';
  }

  @override
  String get progressConverting => 'Converting…';

  @override
  String get progressLoadingImage => 'Loading image…';

  @override
  String get progressPhaseSegment => 'Clustering';

  @override
  String get progressPhaseCompose => 'Composing';

  @override
  String get progressPhaseOptimize => 'Optimizing';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeSystemDesc =>
      'Follows your OS light/dark setting (default).';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeLightDesc =>
      'Bright surfaces; best in well-lit environments.';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeDarkDesc =>
      'Dimmed surfaces; easier on the eyes at night.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageSystemDesc =>
      'Matches your OS language (default).';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageEnDesc => 'Use English for menus and messages.';

  @override
  String get settingsLanguageKo => '한국어';

  @override
  String get settingsLanguageKoDesc => '메뉴와 안내를 한국어로 표시합니다.';

  @override
  String snackbarSavedToDownloads(String name) {
    return 'Saved to Downloads: $name';
  }

  @override
  String snackbarSaveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String snackbarLoadFailed(String error) {
    return 'Could not load image: $error';
  }
}

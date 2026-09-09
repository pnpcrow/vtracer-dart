import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VTracer'**
  String get appTitle;

  /// No description provided for @detailWindowTitle.
  ///
  /// In en, this message translates to:
  /// **'VTracer — detail'**
  String get detailWindowTitle;

  /// No description provided for @windowButtonMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowButtonMinimize;

  /// No description provided for @windowButtonMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowButtonMaximize;

  /// No description provided for @windowButtonRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowButtonRestore;

  /// No description provided for @windowButtonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowButtonClose;

  /// No description provided for @panelDownloadSvg.
  ///
  /// In en, this message translates to:
  /// **'Download as SVG'**
  String get panelDownloadSvg;

  /// No description provided for @panelSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select file'**
  String get panelSelectFile;

  /// No description provided for @panelTrySample.
  ///
  /// In en, this message translates to:
  /// **'Try a sample'**
  String get panelTrySample;

  /// No description provided for @panelApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get panelApply;

  /// No description provided for @panelRendering.
  ///
  /// In en, this message translates to:
  /// **'Rendering…'**
  String get panelRendering;

  /// No description provided for @groupClustering.
  ///
  /// In en, this message translates to:
  /// **'Clustering'**
  String get groupClustering;

  /// No description provided for @groupClusteringDesc.
  ///
  /// In en, this message translates to:
  /// **'How pixels are segmented and grouped into color layers.'**
  String get groupClusteringDesc;

  /// No description provided for @clusterBw.
  ///
  /// In en, this message translates to:
  /// **'B/W'**
  String get clusterBw;

  /// No description provided for @clusterBwTip.
  ///
  /// In en, this message translates to:
  /// **'Black & White (Binary Image)'**
  String get clusterBwTip;

  /// No description provided for @clusterColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get clusterColor;

  /// No description provided for @clusterColorTip.
  ///
  /// In en, this message translates to:
  /// **'True Color Image'**
  String get clusterColorTip;

  /// No description provided for @hierarchyCutout.
  ///
  /// In en, this message translates to:
  /// **'Cutout'**
  String get hierarchyCutout;

  /// No description provided for @hierarchyCutoutTip.
  ///
  /// In en, this message translates to:
  /// **'Shapes disjoint with others'**
  String get hierarchyCutoutTip;

  /// No description provided for @hierarchyStacked.
  ///
  /// In en, this message translates to:
  /// **'Stacked'**
  String get hierarchyStacked;

  /// No description provided for @hierarchyStackedTip.
  ///
  /// In en, this message translates to:
  /// **'Stack shapes on top of another'**
  String get hierarchyStackedTip;

  /// No description provided for @sliderFilterSpeckle.
  ///
  /// In en, this message translates to:
  /// **'Filter Speckle'**
  String get sliderFilterSpeckle;

  /// No description provided for @sliderFilterSpeckleHint.
  ///
  /// In en, this message translates to:
  /// **'(Cleaner)'**
  String get sliderFilterSpeckleHint;

  /// No description provided for @sliderFilterSpeckleDesc.
  ///
  /// In en, this message translates to:
  /// **'Discard patches smaller than this many pixels.'**
  String get sliderFilterSpeckleDesc;

  /// No description provided for @sliderColorPrecision.
  ///
  /// In en, this message translates to:
  /// **'Color Precision'**
  String get sliderColorPrecision;

  /// No description provided for @sliderColorPrecisionHint.
  ///
  /// In en, this message translates to:
  /// **'(More accurate)'**
  String get sliderColorPrecisionHint;

  /// No description provided for @sliderColorPrecisionDesc.
  ///
  /// In en, this message translates to:
  /// **'Number of significant bits to use in an RGB channel.'**
  String get sliderColorPrecisionDesc;

  /// No description provided for @sliderGradientStep.
  ///
  /// In en, this message translates to:
  /// **'Gradient Step'**
  String get sliderGradientStep;

  /// No description provided for @sliderGradientStepHint.
  ///
  /// In en, this message translates to:
  /// **'(Less layers)'**
  String get sliderGradientStepHint;

  /// No description provided for @sliderGradientStepDesc.
  ///
  /// In en, this message translates to:
  /// **'Color difference between gradient layers.'**
  String get sliderGradientStepDesc;

  /// No description provided for @groupCurveFitting.
  ///
  /// In en, this message translates to:
  /// **'Curve Fitting'**
  String get groupCurveFitting;

  /// No description provided for @groupCurveFittingDesc.
  ///
  /// In en, this message translates to:
  /// **'How clusters are converted into vector shapes.'**
  String get groupCurveFittingDesc;

  /// No description provided for @fitPixel.
  ///
  /// In en, this message translates to:
  /// **'Pixel'**
  String get fitPixel;

  /// No description provided for @fitPixelTip.
  ///
  /// In en, this message translates to:
  /// **'Exact cluster boundary'**
  String get fitPixelTip;

  /// No description provided for @fitPolygon.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get fitPolygon;

  /// No description provided for @fitPolygonTip.
  ///
  /// In en, this message translates to:
  /// **'Simplify to Polygon'**
  String get fitPolygonTip;

  /// No description provided for @fitSpline.
  ///
  /// In en, this message translates to:
  /// **'Spline'**
  String get fitSpline;

  /// No description provided for @fitSplineTip.
  ///
  /// In en, this message translates to:
  /// **'Smooth and Curve-fit'**
  String get fitSplineTip;

  /// No description provided for @sliderCornerThreshold.
  ///
  /// In en, this message translates to:
  /// **'Corner Threshold'**
  String get sliderCornerThreshold;

  /// No description provided for @sliderCornerThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'(Smoother)'**
  String get sliderCornerThresholdHint;

  /// No description provided for @sliderCornerThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Minimum momentary angle (degrees) to be considered a corner.'**
  String get sliderCornerThresholdDesc;

  /// No description provided for @sliderSegmentLength.
  ///
  /// In en, this message translates to:
  /// **'Segment Length'**
  String get sliderSegmentLength;

  /// No description provided for @sliderSegmentLengthHint.
  ///
  /// In en, this message translates to:
  /// **'(More coarse)'**
  String get sliderSegmentLengthHint;

  /// No description provided for @sliderSegmentLengthDesc.
  ///
  /// In en, this message translates to:
  /// **'Subdivide until all segments are shorter than this length.'**
  String get sliderSegmentLengthDesc;

  /// No description provided for @sliderSpliceThreshold.
  ///
  /// In en, this message translates to:
  /// **'Splice Threshold'**
  String get sliderSpliceThreshold;

  /// No description provided for @sliderSpliceThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'(More accurate)'**
  String get sliderSpliceThresholdHint;

  /// No description provided for @sliderSpliceThresholdDesc.
  ///
  /// In en, this message translates to:
  /// **'Minimum angle displacement (degrees) to splice two curves.'**
  String get sliderSpliceThresholdDesc;

  /// No description provided for @panelInputSummary.
  ///
  /// In en, this message translates to:
  /// **'Input: {width}×{height} px'**
  String panelInputSummary(int width, int height);

  /// No description provided for @panelOutputSummary.
  ///
  /// In en, this message translates to:
  /// **'Output: {shapes} shapes, {ms} ms'**
  String panelOutputSummary(int shapes, int ms);

  /// No description provided for @snackbarSvgSaved.
  ///
  /// In en, this message translates to:
  /// **'SVG saved.'**
  String get snackbarSvgSaved;

  /// No description provided for @snackbarLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load image: {error}'**
  String snackbarLoadFailed(String error);

  /// No description provided for @canvasDropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag an image here'**
  String get canvasDropHint;

  /// No description provided for @canvasDropHintHover.
  ///
  /// In en, this message translates to:
  /// **'Drop to trace'**
  String get canvasDropHintHover;

  /// No description provided for @canvasDropHintSub.
  ///
  /// In en, this message translates to:
  /// **'or use “Select file” / “Try a sample” on the left'**
  String get canvasDropHintSub;

  /// No description provided for @tooltipOpenFullView.
  ///
  /// In en, this message translates to:
  /// **'Open full view in a new window'**
  String get tooltipOpenFullView;

  /// No description provided for @bannerDirty.
  ///
  /// In en, this message translates to:
  /// **'Parameters changed — press Apply to update the trace'**
  String get bannerDirty;

  /// No description provided for @infoBarInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get infoBarInput;

  /// No description provided for @infoBarOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get infoBarOutput;

  /// No description provided for @infoBarPending.
  ///
  /// In en, this message translates to:
  /// **'pending…'**
  String get infoBarPending;

  /// No description provided for @infoBarShapes.
  ///
  /// In en, this message translates to:
  /// **'{count} shapes'**
  String infoBarShapes(int count);

  /// No description provided for @infoBarLayers.
  ///
  /// In en, this message translates to:
  /// **'{count} layers'**
  String infoBarLayers(int count);

  /// No description provided for @infoBarPreviewScale.
  ///
  /// In en, this message translates to:
  /// **'Preview {percent}%'**
  String infoBarPreviewScale(int percent);

  /// No description provided for @progressConverting.
  ///
  /// In en, this message translates to:
  /// **'Converting…'**
  String get progressConverting;

  /// No description provided for @progressPhaseSegment.
  ///
  /// In en, this message translates to:
  /// **'Clustering'**
  String get progressPhaseSegment;

  /// No description provided for @progressPhaseCompose.
  ///
  /// In en, this message translates to:
  /// **'Composing'**
  String get progressPhaseCompose;

  /// No description provided for @progressPhaseOptimize.
  ///
  /// In en, this message translates to:
  /// **'Optimizing'**
  String get progressPhaseOptimize;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeSystemDesc.
  ///
  /// In en, this message translates to:
  /// **'Follows your OS light/dark setting (default).'**
  String get settingsThemeSystemDesc;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeLightDesc.
  ///
  /// In en, this message translates to:
  /// **'Bright surfaces; best in well-lit environments.'**
  String get settingsThemeLightDesc;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeDarkDesc.
  ///
  /// In en, this message translates to:
  /// **'Dimmed surfaces; easier on the eyes at night.'**
  String get settingsThemeDarkDesc;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageSystemDesc.
  ///
  /// In en, this message translates to:
  /// **'Matches your OS language (default).'**
  String get settingsLanguageSystemDesc;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsLanguageEnDesc.
  ///
  /// In en, this message translates to:
  /// **'Use English for menus and messages.'**
  String get settingsLanguageEnDesc;

  /// No description provided for @settingsLanguageKo.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get settingsLanguageKo;

  /// No description provided for @settingsLanguageKoDesc.
  ///
  /// In en, this message translates to:
  /// **'메뉴와 안내를 한국어로 표시합니다.'**
  String get settingsLanguageKoDesc;

  /// No description provided for @settingsClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsClose;

  /// No description provided for @detailChars.
  ///
  /// In en, this message translates to:
  /// **'{count} chars'**
  String detailChars(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

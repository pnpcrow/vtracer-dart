// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'VTracer';

  @override
  String get detailWindowTitle => 'VTracer — 상세 보기';

  @override
  String get windowButtonMinimize => '최소화';

  @override
  String get windowButtonMaximize => '최대화';

  @override
  String get windowButtonRestore => '이전 크기로';

  @override
  String get windowButtonClose => '닫기';

  @override
  String get panelDownloadSvg => 'SVG로 내보내기';

  @override
  String get panelSelectFile => '파일 선택';

  @override
  String get panelTrySample => '샘플 이미지 시도';

  @override
  String get panelApply => '적용';

  @override
  String get panelRendering => '변환 중…';

  @override
  String get groupClustering => '클러스터링';

  @override
  String get groupClusteringDesc => '픽셀을 어떻게 나누고 색 레이어로 묶을지 정합니다.';

  @override
  String get clusterBw => '흑백';

  @override
  String get clusterBwTip => '흑백(이진 이미지)';

  @override
  String get clusterColor => '컬러';

  @override
  String get clusterColorTip => '실제 색상 이미지';

  @override
  String get hierarchyCutout => '컷아웃';

  @override
  String get hierarchyCutoutTip => '도형이 서로 겹치지 않게 분리';

  @override
  String get hierarchyStacked => '겹침';

  @override
  String get hierarchyStackedTip => '도형을 위로 겹쳐 쌓기';

  @override
  String get sliderFilterSpeckle => '잡점 제거';

  @override
  String get sliderFilterSpeckleHint => '(더 깨끗하게)';

  @override
  String get sliderFilterSpeckleDesc => '이 크기(픽셀)보다 작은 잡점을 제거합니다.';

  @override
  String get sliderColorPrecision => '색상 정밀도';

  @override
  String get sliderColorPrecisionHint => '(더 정확하게)';

  @override
  String get sliderColorPrecisionDesc => 'RGB 채널에 사용할 유효 비트 수입니다.';

  @override
  String get sliderGradientStep => '그라데이션 단계';

  @override
  String get sliderGradientStepHint => '(레이어 감소)';

  @override
  String get sliderGradientStepDesc => '그라데이션 레이어 사이의 색상 차이입니다.';

  @override
  String get groupCurveFitting => '곡선 피팅';

  @override
  String get groupCurveFittingDesc => '클러스터를 벡터 도형으로 바꾸는 방식입니다.';

  @override
  String get fitPixel => '픽셀';

  @override
  String get fitPixelTip => '클러스터 경계를 그대로 유지';

  @override
  String get fitPolygon => '다각형';

  @override
  String get fitPolygonTip => '다각형으로 단순화';

  @override
  String get fitSpline => '스플라인';

  @override
  String get fitSplineTip => '부드러운 곡선으로 근사';

  @override
  String get sliderCornerThreshold => '코너 임계값';

  @override
  String get sliderCornerThresholdHint => '(더 부드럽게)';

  @override
  String get sliderCornerThresholdDesc => '코너로 판단하는 최소 순간 각도(도)입니다.';

  @override
  String get sliderSegmentLength => '선분 길이';

  @override
  String get sliderSegmentLengthHint => '(더 굵게)';

  @override
  String get sliderSegmentLengthDesc => '모든 선분이 이 길이보다 짧아질 때까지 분할합니다.';

  @override
  String get sliderSpliceThreshold => '곡선 연결 임계값';

  @override
  String get sliderSpliceThresholdHint => '(더 정확하게)';

  @override
  String get sliderSpliceThresholdDesc => '두 곡선을 하나로 연결하는 최소 각도 변위(도)입니다.';

  @override
  String panelInputSummary(int width, int height) {
    return '입력: $width×$height px';
  }

  @override
  String panelOutputSummary(int shapes, int ms) {
    return '출력: 도형 $shapes개, $ms ms';
  }

  @override
  String get snackbarSvgSaved => 'SVG를 저장했습니다.';

  @override
  String snackbarLoadFailed(String error) {
    return '이미지를 불러올 수 없습니다: $error';
  }

  @override
  String get canvasDropHint => '이미지를 여기로 끌어다 놓으세요';

  @override
  String get canvasDropHintHover => '놓아서 변환 시작';

  @override
  String get canvasDropHintSub => '또는 왼쪽의 “파일 선택” / “샘플 이미지 시도”를 사용하세요';

  @override
  String get tooltipOpenFullView => '새 창에서 전체 크기로 보기';

  @override
  String get bannerDirty => '설정이 변경되었습니다 — 적용을 눌러 결과를 갱신하세요';

  @override
  String get infoBarInput => '입력';

  @override
  String get infoBarOutput => '출력';

  @override
  String get infoBarPending => '대기 중…';

  @override
  String infoBarShapes(int count) {
    return '도형 $count개';
  }

  @override
  String infoBarLayers(int count) {
    return '레이어 $count개';
  }

  @override
  String infoBarPreviewScale(int percent) {
    return '미리보기 $percent%';
  }

  @override
  String get progressConverting => '변환 중…';

  @override
  String get progressPhaseSegment => '클러스터링 중';

  @override
  String get progressPhaseCompose => '합성 중';

  @override
  String get progressPhaseOptimize => '최적화 중';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsTheme => '테마';

  @override
  String get settingsThemeSystem => '시스템';

  @override
  String get settingsThemeSystemDesc => '운영체제의 라이트/다크 설정을 따라갑니다(기본값).';

  @override
  String get settingsThemeLight => '라이트';

  @override
  String get settingsThemeLightDesc => '밝은 화면으로, 밝은 환경에서 보기 편합니다.';

  @override
  String get settingsThemeDark => '다크';

  @override
  String get settingsThemeDarkDesc => '어두운 화면으로, 어두운 환경에서 눈에 편합니다.';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsLanguageSystem => '시스템';

  @override
  String get settingsLanguageSystemDesc => '운영체제 언어를 따라갑니다(기본값).';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageEnDesc => 'Use English for menus and messages.';

  @override
  String get settingsLanguageKo => '한국어';

  @override
  String get settingsLanguageKoDesc => '메뉴와 안내를 한국어로 표시합니다.';

  @override
  String get settingsClose => '닫기';

  @override
  String detailChars(int count) {
    return '$count자';
  }
}

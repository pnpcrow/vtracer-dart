# VTracer × Needle3 — AI 자동 모드 기술 분석

> 상태: 구현 완료 (2026-09)
> 구현: `packages/vtracer_ai` · 템플릿: `docs/ai_auto/templates/` · 적용 방법: [`needle3_integration.md`](needle3_integration.md)

## 1. 요약

vtracer 파이프라인에는 "정답이 없고 이미지 성격에 따라 최적값이 달라지는" 판단 지점이
10여 개 있다. 지금까지는 사용자가 프리셋(bw/poster/photo)과 슬라이더로 수동 판단했지만,
이 문서는 그 판단을 모델에게 넘기는 **AI 자동 모드**의 기술적 근거를 정리한다.

채택된 모델은 Cactus Compute의 **Needle 3**([Hugging Face `Cactus-Compute/needle3`](https://huggingface.co/Cactus-Compute/needle3))
— 121M 파라미터, 8–29MB `.cact` 파일로 배포되는 온디바이스 자동화 파운데이션 모델로,
function calling과 **JSON 스키마 문법 제약 출력**(토큰 단위로 스키마 문법이 강제되므로
파싱 실패가 없음), 캘리브레이션된 신뢰도 점수가 표준 출력이다. Apache-2.0.

핵심 설계 판단 3가지:

1. **모델은 픽셀을 보지 않고, 피처를 본다.** 이미지를 모델 입력으로 넣는 대신
   순수 Dart `FeatureExtractor`가 이미지를 17개 통계 피처(팔레트 집중도, 에지 밀도,
   잡음, 색채, 배경 균일도 등)로 압축하고, 모델은 이 숫자 벡터에서 파라미터를 판단한다.
   Needle3가 텍스트/구조화 출력 전용 소형 모델이라는 점과, 피처 17개는 토큰 수십 개로
   충분하다는 점에서 컨텍스트·비용이 극도로 작아진다. (VLM 대안 분석은 §4.2)
2. **모델 출력은 절대 신뢰하지 않는다.** 모델 결정은 필드 단위로 휴리스틱 베이스라인 위에
   병합(merge)되고, 파이프라인 허용 범위로 클램프된 뒤(`AiDecision.clamped()`) 적용된다.
   누락·범위 이탈 필드는 자동으로 휴리스틱 값으로 수복되며, 이 경우
   `source = needle3Repaired`로 표시되어 운영에서 드리프트를 감지할 수 있다.
3. **오프라인 폴백이 1등급 시민이다.** 휴리스틱 엔진(`HeuristicDecisionEngine`)은
   결정론적 규칙만으로 동작하므로 모델·서버 없이도 AI 자동 모드가 성립하고,
   Needle3 호출 실패 시 `decideOrHeuristic()`이 같은 인터페이스로 대행한다.

## 2. vtracer 파이프라인의 판단 지점

파이프라인: `image → Frontend(분할) → ColorFitter → Compositing → CurveFitter → Optimizer → SVG`

| # | 판단 지점 (VtracerConfig 필드) | 역할 | 잘못 고르면 | 이미지 피처와의 상관 |
|---|---|---|---|---|
| 1 | `clustering` | 분할 알고리즘 (color-cluster / binary / watershed) | 사진에 binary → 전부 단색화, 라인아트에 color-cluster → 회색 잔파편 | 색채·팔레트 집중도·명도 이봉성 |
| 2 | `hierarchical` | 레이어 적층(stacked) vs 심리스 모자이크(cutout) | 평면 아트에 stacked → 경계 틈·헤일로 | flatShare, 팔레트 집중도 |
| 3 | `filterSpeckle` | 스피클(잡점) 제거 면적 | 크면 디테일 소실, 작으면 잡음 파편 폭발 | noiseLevel, edgeDensity |
| 4 | `colorPrecision` | 채널당 유효 비트 (1–8) | 낮으면 색 밴딩, 높으면 미세 색조 파편 | quantizedColors, 색채 |
| 5 | `layerDifference` | 그라데이션 레이어 간 색차 (0–255) | 작으면 사진에서 수천 레이어, 크면 포스터화 | noiseLevel, meanGradient |
| 6 | `mode` (fit) | pixel / polygon / spline | 픽셀아트에 spline → 흐릿해짐, 사진에 pixel → 노드 폭발 | 팔레트 집중도, edgeDensity |
| 7 | `cornerThreshold` | 코너 판정 각도 | 낮으면 지그재그, 높으면 날카로운 코너 유실 | edgeDensity (로고/사진 구분) |
| 8 | `lengthThreshold` / `spliceThreshold` | 세그먼트 분할/연결 | 곡선 품질·노드 수의 미세 조정기 | 목표에 따라 보정 |
| 9 | `maxColors` / `palette` | 팔레트 양자화 | 크면 파일 증가, 작으면 색 유실 | quantizedColors, 목표 |
| 10 | `simplify` / `pathPrecision` / `optimize` | 곡선 단순화·좌표 압축 | 곡선 수와 파일 크기의 트레이드오프 | noiseLevel, 목표 |

기존 프리셋(bw/poster/photo)은 이 중 4–5개만 상수로 고정한 3개의 정적 스냅샷이다.
AI 자동 모드는 피처에 따라 **연속적으로** 값을 고르고, 판단 근거(`rationale`)와
신뢰도를 함께 반환한다는 점이 차이다.

## 3. 피처 벡터 (`ImageFeatures`)

분석 다운샘플: 장변 200px, 최근접 이웃(박스 평균을 쓰면 잡음이 사라져
`noiseLevel`이 무의미해지므로 의도적으로 nearest) — 비용은 해상도와 무관하게 사실상 상수.

| 피처 | 정의 | 판단에서의 의미 |
|---|---|---|
| `quantizedColors` | 4bit/채널 양자화 후 고유 색 수 | 팔레트 복잡도 |
| `paletteShare8` / `dominantShare` | 상위 8개(1개) 색 버킷의 픽셀 점유율 | 평면 아트 ↔ 사진 구분의 1차 축 |
| `edgeDensity` / `meanGradient` / `flatShare` | Sobel 임계 초과 비율 / 평균 기울기 / 평탄 영역 비율 | 디테일 밀도, 모자이크 적합성 |
| `noiseLevel` | 평탄 영역의 평균 절대 라플라시안 | JPEG 아티팩트·디더링 감지 → speckle/양자화 상향 |
| `colorfulness` | Hasler–Süsstrunk(2003) 지표 | 흑백 스캔 판정 |
| `transparentShare` | alpha<250 픽셀 비율 | 배경 제거 아이콘 판별 |
| `luminanceSpread`, `darkShare`, `lightShare` | 명도 p95−p5, 양끝 단 점유 | 이진화(라인아트) 판정 |
| `backgroundUniformity` | 테두리 8% 프레임 명도 표준편차 | 불균등 조명 → Bradley–Roth 적응형 임계값 |
| 크기/비율/알파 | width, height, megapixels, aspectRatio | 처리량 산정 |

토큰 예산: `toPromptPayload()` 직렬화 시 약 200–250 토큰. Needle3의 소형 컨텍스트에
시스템 프롬프트 + 도구 스키마 + 페이로드가 모두 들어간다.

## 4. 모델 선택 분석

### 4.1 요구사항

vtracer의 판단은 "이 이미지에 어떤 파라미터 세트?"라는 **단일 턴, 구조화 출력,
저지연** 문제다. 요구사항: (a) 구조화(JSON) 출력 보장, (b) 온디바이스/오프라인
가능, (c) 수백 KB–수 MB 바이너리, (d) 함수 호출 형식으로 스키마 강제, (e) 라이선스.

### 4.2 후보 비교

| 후보 | 크기 | 구조화 출력 | 온디바이스 | 평가 |
|---|---|---|---|---|
| **Needle 3** (Cactus) | 8–29MB `.cact` + 플랫폼 엔진 <1MB | **JSON 스키마 문법 제약**(파싱 실패 없음) + 신뢰도 | C API/CLI/WASM, Android·iOS·데스크톱 | 채택. 소형·즉시·도구 호출 특화 |
| Needle 2 | ~14MB | 도구 호출 | 모바일 | Needle 3이 상위 호환 |
| 범용 소형 LLM (0.5–2B급) | 0.3–2GB | 프롬프트 의존(파싱 실패 가능) | 가능하지만 무거움 | 과잉·지연 큼 |
| VLM(이미지 입력) | 수 GB | — | 비현실적 | 픽셀 이해는 불필요 — 필요한 건 통계→파라미터 매핑 |
| 순수 분류기/회귀 (ML이 아니라 휴리스틱) | 0 | — | — | 채택(베이스라인). 규칙으로 충분한 구간이 크고, 모델 수복·폴백의 기준점 |

### 4.3 Needle 3가 가진 운영상 이점

- **모든 턴이 `{function_calls, reasoning, calibrated confidence}` JSON** — vtracer_ai의
  병합/클램프 계층과 신뢰도 UI가 바로 연결된다.
- **지원 불가 판단 시 빈 리스트 반환**(환각 억제) — 피처가 비정상이면 모델이 침묵하고,
  그때 휴리스틱이 책임지는 이중 안전망이 성립한다.
- **LoRA 파인튜닝 + 2–20레이어 서브네티어링** — 변환 로그(피처→결정→사용자 수정)를
  모아 재학습하면 더 작은 레이어 수로 슬라이싱해 지연을 줄일 수 있다(§6 로드맵).

## 5. 아키텍처와 데이터 흐름

```text
                    ┌──────────────────────────── packages/vtracer_ai ───────────────────────────┐
                    │                                                                            │
ColorImage ──▶ FeatureExtractor ──▶ ImageFeatures ──┬─▶ HeuristicDecisionEngine ──┐            │
                    (장변 200px 다운샘플)            │                             ├─▶ AiDecision│
                    │                               │        (베이스라인·수복)     │   (clamp)  │
                    │                               └─▶ Needle3DecisionEngine ────┘     │       │
                    │                                      │                            │       │
                    │                          Needle3Runtime (플러그형)                 ▼       │
                    │                          ├─ Needle3HttpRuntime (needle --serve)   VtracerConfig
                    │                          ├─ Needle3ProcessRuntime (needle CLI)        │
                    │                          └─ C-API FFI (모바일, 확장 지점)              ▼
                    └──────────────────────────────────────────────────────  Pipeline ──▶ SVG
```

- **판단 템플릿은 Dart가 단일 진실 공급원.** `DecisionTemplates`(decision.schema.json,
  tools.json, 시스템/사용자/정제 프롬프트)가 코드로 정의되어 있고
  `dart run packages/vtracer_ai/tool/dump_templates.dart`로 문서 사본을 재생성한다.
  스키마와 코드가 어긋날 수 없다.
- **결정 스키마**: 14개 파라미터 필드 + `rationale`(근거) + `confidence`(신뢰도).
  `max_colors`·`simplify`만 nullable. 전체는 `docs/ai_auto/templates/decision.schema.json`.
- **품질 루프(확장)**: 변환 결과의 측정치(도형 수, 바이트, 레이어 수)를 `refinementPrompt`
  양식으로 모델에 재투입해 2차 조정하는 인터페이스가 준비되어 있다.

## 6. 한계와 리스크

1. **모델은 픽셀 의미를 모른다.** "고양이가 보이니 매끈하게" 같은 의미론 판단은 불가능하다.
   필요하면(예: 인물 사진 전용 프로파일) 피처에 임베딩/의미 피처를 추가하는 방향으로 확장.
2. **Cactus 엔진 플랫폼 매트릭스.** Windows/macOS/Linux는 `needle` CLI·`--serve`가
   경로이고, Android/iOS는 C API FFI 바인딩이 필요하다(적용 방법 문서 §3 참조).
   웹은 WASM 프록시 서버를 통해야 한다.
3. **피처의 한계.** 장변 200px 다운샘플은 초고해상도 아이콘의 1px 라인을 놓칠 수 있다.
   필요 시 `maxSamplesPerSide` 상향(비용 증가) 또는 전체 해상도 히스토그램 병행.
4. **모델 편향.** Needle3는 이미지 도메인 특화 학습이 아니므로, 로그 기반 LoRA
   파인튜닝이 실질 품질 상한이다. 휴리스틱 베이스라인이 항상 하한을 보장한다.

## 7. 구현 매핑

| 문서 개념 | 코드 |
|---|---|
| 피처 추출 | `vtracer_ai/lib/src/features.dart` (`FeatureExtractor`, `ImageFeatures`) |
| 판단 템플릿 | `vtracer_ai/lib/src/schema.dart` (`DecisionTemplates`) + `docs/ai_auto/templates/` |
| 결정 모델·클램프 | `vtracer_ai/lib/src/decision.dart` (`AiDecision`, `TuningGoal`) |
| 휴리스틱 엔진 | `vtracer_ai/lib/src/engine.dart` |
| Needle3 런타임·엔진 | `vtracer_ai/lib/src/needle3.dart` (`Needle3HttpRuntime`, `Needle3ProcessRuntime`, `Needle3DecisionEngine`) |
| 오케스트레이션 | `vtracer_ai/lib/src/autotune.dart` (`AutoTuner`, `TuningResult`) |
| CLI | `vtracer_cli/bin/vtracer.dart` (`--preset ai`, `--ai-goal`, `--needle3`) |
| 앱 UI | `vtracer_app` 옵션 패널 "AI 자동" 섹션 + 설정의 Needle3 엔드포인트 |

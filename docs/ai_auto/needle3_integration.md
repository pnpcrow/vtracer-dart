# Needle3 모듈 적용 방법 (vtracer_ai)

> 기술 배경: [`analysis.md`](analysis.md) · 판단 템플릿: [`templates/`](templates/)

Needle 3는 Cactus Compute가 공개한 온디바이스 자동화 모델
(121M 파라미터, 8–29MB `.cact`, Apache-2.0,
[모델 카드](https://huggingface.co/Cactus-Compute/needle3))다. 모델 파일 하나와
플랫폼별 엔진(<1MB)만 있으면 클라우드 없이 function calling/구조화 출력을 수행하며,
`vtracer_ai`는 이것을 `Needle3Runtime` 인터페이스 뒤로 숨겨 어디서 어떻게 띄울지와
"무엇을 판단할지"를 분리해 둔다.

## 0. 모델 준비

```sh
# 모델 파일(needle3.cact) 확보 — Hugging Face에서 내려받는다.
# https://huggingface.co/Cactus-Compute/needle3 (needle3.cact, 20레이어 전체본)
#
# Cactus Python SDK로 직접 다운로드/빌드하는 경우:
pip install cactus-needle
needle build --platform <플랫폼 폴더> [--layers N]   # 2–20 레이어 서브네티어링
```

`--layers N`로 자른 작은 서브넷도 스키마 제약 결정에는 충분할 수 있다(파인튜닝 로드맵은 §5).

## 1. 가장 빠른 사용법 — 이미 구현된 세 가지 경로

### 1-1. 휴리스틱만 (모델 없음, 오프라인)

```dart
final result = await AutoTuner.local().tune(image);          // goal: balanced
final svg = result.config.build().toSvg(image);
print(result.decision.rationale);   // 판단 근거
print(result.decision.confidence);  // 신뢰도 0..1
```

### 1-2. CLI (`vtracer` 명령)

```sh
# 휴리스틱 엔진
vtracer --preset ai photo.jpg out.svg
vtracer --preset ai --ai-goal compact photo.jpg out.svg   # balanced | faithful | compact

# Needle3 serve 서버 사용
vtracer --preset ai --needle3 http://127.0.0.1:8080/run photo.jpg out.svg

# needle CLI 실행 파일 + .cact 파일 직접 사용 (데스크톱)
vtracer --preset ai --needle3 C:\models\needle3.cact photo.jpg out.svg
```

모델 호출 실패/타임아웃 시 자동으로 휴리스틱으로 폴백하며, 모델 출력이 스키마 범위를
벗어나면 클램프 + `needle3Repaired` 표시가 된다(로그의 `engine=`/`repaired` 확인).

### 1-3. Flutter 앱 (vtracer_app) — Needle3 내장

1. **설정 → AI 판단 엔진**이 기본값 **내장**이면 별도 준비가 전혀 필요 없습니다:
   앱에 번들된 Needle3 엔진(`needle.exe`)과 모델(`needle3.cact`, 35MB)이 첫
   분석 시 앱 데이터 디렉터리에 자동 추출되어 실행됩니다.
   고급 옵션으로 **서버**(실행 중인 `needle --serve` 주소 입력)와
   **규칙**(오프라인 내장 규칙만)을 선택할 수 있습니다.
2. 왼쪽 패널 **AI 자동** 섹션에서 목표(균형/충실/경량)를 고르고 **분석 후 적용** 클릭.
3. 패널의 모든 슬라이더가 결정값으로 움직이고 즉시 변환 결과가 갱신된다. 섹션 하단에
   엔진·신뢰도·판단 근거가 표시된다.

Android 앱(vtracer_android)도 동일하게 내장 Needle3를 기본 사용한다 — 엔진은
`jniLibs/arm64-v8a/libneedle.so`, 모델은 자산에서 추출한다. 두 앱 모두 모델이
사용 불가능하면 내장 규칙으로 자동 전환된다.

## 2. Needle3 serve 모드 (HTTP) — 권장 경로

Cactus 엔진의 `--serve` 모드를 띄워 두고 HTTP로 호출한다. 데스크톱 전퇴/사내 서버/
모바일(로컬 루프백) 모두에서 동작하며, 웹 빌드는 이 서버를 프록시로 거친다.

```sh
needle --model needle3.cact --serve     # 엔진이 HTTP 엔드포인트를 연다
```

```dart
final engine = Needle3DecisionEngine(
  runtime: Needle3HttpRuntime(
    Uri.parse('http://127.0.0.1:8080/run'),
    headers: {'authorization': 'Bearer ...'},   // 선택
    timeout: const Duration(seconds: 30),
  ),
);
final result = await AutoTuner(engine).tune(image, goal: TuningGoal.compact);
```

**요청 본문** (`Needle3Invocation.toRequestJson()`):

```json
{
  "model": "needle3.cact",
  "system": "<DecisionTemplates.systemPrompt(goal)>",
  "prompt": "<DecisionTemplates.featurePrompt(features, goal)>",
  "tools": [ { "name": "propose_vtracer_parameters", "parameters": { "...": "decision.schema.json" } } ],
  "temperature": 0.2
}
```

**응답 파싱** (`parseNeedle3Answer`) — 다음 형태를 모두 수용한다:

| 형태 | 예 |
|---|---|
| serve 봉투 + `function_calls` | `{"function_calls":[{"name":"propose_vtracer_parameters","arguments":{...}}],"confidence":0.82,"reasoning":"..."}` |
| `tool_calls` 표기 | 위와 동일하되 `tool_calls` 키 |
| arguments가 JSON 문자열 | `"arguments": "{\"clustering\": ... }"` |
| 봉투 없는 순수 extraction | arguments 객체 그 자체 (`{"clustering": "...", ...}`) |

이 계약은 실제 `needle --serve` 응답 필드명과 다를 수 있으므로, 처음 붙일 때는 한 번의
실제 호출로 응답을 덤프해 확인하고 필요하면 `parseNeedle3Answer`의 키 후보에 한 줄을
추가하면 된다. 파싱 실패는 `Needle3Exception` → `decideOrHeuristic()` 폴백.

## 3. 플랫폼별 임베딩 매트릭스

Cactus는 플랫폼 폴더마다 **정적 라이브러리(`libneedle.a`) + 독립 실행 엔진
(`needle`/`needle.exe`, ~1.2MB)**만 배포한다 — 로더블 공유 라이브러리(.so/.dll)는
없다. 따라서 Dart FFI(`DynamicLibrary.open`)는 불가능하고, "내장"은
**엔진 실행 파일 + `needle3.cact` 모델을 앱 자산으로 휴대하고 런타임에 추출·실행**
하는 방식으로 구현된다. vtracer_ai의 `Needle3EmbeddedRuntime`과
`Needle3BundleInstaller`가 이 경로를 담당하며, 별도 서버나 수동 설치가 필요 없다.

| 플랫폼 | 내장 방식 | 상태 |
|---|---|---|
| Windows (데스크톱 앱·CLI) | `needle.exe` + 모델을 자산으로 번들 → 첫 사용 시 앱 데이터 디렉터리에 추출 → `Needle3EmbeddedRuntime`(자식 프로세스) | **구현됨** (`apps/vtracer_app/assets/needle3/`) |
| Android | 엔진을 `jniLibs/arm64-v8a/libneedle.so`로 패키징(nativeLibraryDir에서만 실행 가능) + 모델 자산 추출 → 같은 런타임. **필수 빌드 설정**: 최신 AGP 기본값(`extractNativeLibs=false`)에서는 `.so`가 APK 안에만 존재해 `nativeLibraryDir`에 나타나지 않으므로, `build.gradle.kts`에 `packaging { jniLibs { useLegacyPackaging = true; doNotStrip("**/libneedle.so") } }`가 필요하다 (미설정 시 스폰 실패 → 휴리스틱 폴백) | **구현됨** (`apps/vtracer_android`) |
| macOS / Linux | 실행 엔진은 존재(`macos-arm64/needle`, `linux-x86_64/needle`) — 데스크톱 앱이 대상 플랫폼용 엔진 자산을 추가하면 즉시 확장 가능 | 미번들 (폴백: 휴리스틱) |
| iOS / Web | 미대응 (폴백: 휴리스틱) | 미번들 |

모든 내장 경로는 실패 시(엔진 부재·실행 오류·모델 중단) `Needle3Exception` →
내장 휴리스틱으로 자동 폴백한다. AI 자동 모드 자체가 실패로 끝나지 않는다.

### 3-1. 임베디드 엔진 설계 (compact + chooser) — 실측 기반

베이스 121M 모델은 프롬프트 접두사가 무거워지면 반복 루프에 빠져 토큰 예산을
소진한다(`tool call truncated: token budget exhausted`). 실측 결과:

| 프롬프트 구성 | 결과 |
|---|---|
| 전체 시스템 프롬프트 + 설명 포함 스키마 + 개행 페이로드 | **실패** (반복 루프, `--max 1024`로도 소진) |
| 3문장 시스템 프롬프트 + **설명 없는 스키마** + **한 줄 페이로드** | 16필드 호출 완성 — 단, 실제 이미지에서 (a) 툴 호출 생략(`type: respond`), (b) 반복 루프, (c) 그라운딩 억제가 관측됨 |
| **후보 선택(chooser)**: 휴리스틱 후보 3개 제시 → 모델이 `choose_candidate(choice: A\|B\|C)` 하나만 반환 | **안정적으로 디스패치됨** (실측 5/5, 신뢰도 0.48–0.85) |

그래서 내장 경로의 실제 설계는 **chooser 방식**이다
(`Needle3CandidateEngine`): 휴리스틱이 **컬러 패밀리 후보**를 만들고, 모델은
피처에 가장 맞는 후보의 글자를 고른다. 선택된 후보는 이미 검증·클램프된
`AiDecision`이므로 병합 없이 바로 유효하다.

메뉴 정책 (중요):

- **binary(문서/스캔) 프로파일은 자동 메뉴에서 의도적으로 제외**되어 있다.
  이는 유일하게 본질적으로 파괴적인 후보(임계값보다 밝은 영역을 전부 폐기)라서,
  글자 편향이 그쪽에 떨어지면 이미지가 외곽선만 남는 결과가 되기 때문이다.
  binary는 명시적 B/W 모드와 [AutoTuner.tune]의 `preserveBinary`(사용자가
  B/W를 고른 상태에서 AI가 패밀리를 바꾸지 않도록 함)로만 도달한다.
- 자동 메뉴는 **컬러 패밀리 5종**이며 각각 적합성 조건을 통과한 것만 제시된다:
  flat(항상) / line-illustration(밝은 배경 + 높은 에지 밀도 + 색채) /
  gradient-illustration(평탄 다수 + 색채 + 저잡음) / photo(항상) /
  pixel-icon(소형 + 소수 색). 메뉴가 비지 않도록 flat·photo는 무조건 후보.
- **문서/스캔 직접 경로**: 거의 무채색 + 강한 이봉성 조건이면 모델을 거치지
  않고 규칙이 binary를 직접 적용한다(`scanDirect`) — 모델은 내용을 볼 수
  없으므로 이 판단은 규칙의 몫이다.
- 클래스 내부 파라미터는 고정값이 아니라 피처에서 보간된다(예: photo의
  filter_speckle ∝ noise, layer_difference ∝ mean_gradient).

또한 엔진의 **그라운딩 검증**이 입력에 근거 없는 값으로 판단한 호출을 자동
억제한다(`success: true, function_calls: [], suppressed_calls: [...]`).
이는 모델 카드 명세("환각 대신 빈 목록 반환")대로의 안전 동작이며, vtracer_ai는
이를 **중단(abstention)** 으로 처리해 휴리스틱 폴백으로 넘긴다.

엔진 CLI의 실제 계약 (`needle --help` 확인치):

```text
needle --model needle3.cact --tools tools.json --system system.txt
       --prompt "..." [--serve] [--max N] [--threads N] [--tool-index path]
- --system: 인라인 문자열이 아니라 파일 경로
- --max: 응답 토큰 상한(기본 512); 내장 경로는 1024 사용
- 출력: {"type":"call"|"respond","success":bool,"function_calls":[...],
         "reasoning":...,"confidence":...}
- 호출 생략/실패 시 function_calls가 비거나 success:false
```

### 3-2. C API (참고용)

엔진을 프로세스 내로 가져오려면 `libneedle.a`에서 공유 라이브러리를 직접
빌드해야 한다(`needle.h`: `needle_load(bytes)` → `needle_init(system,
tools, tool_index_path)` → `needle_complete(input, max_new_tokens, out,
cap)`; 프로세스 전역·비스레드 세이프). vtracer_ai는 이 경로를 지원하지 않으며,
공유 라이브러리가 공식 배포되면 `Needle3Runtime` 구현체 하나로 추가하면 된다.

## 4. 판단 템플릿 관리

- 단일 진실 공급원: `packages/vtracer_ai/lib/src/schema.dart` (`DecisionTemplates`).
- 문서 사본 재생성: `dart run packages/vtracer_ai/tool/dump_templates.dart docs/ai_auto/templates`
  → `decision.schema.json`, `tools.json`, `prompts.md`.
- `tools.json`은 `needle --model ... --tools tools.json`에 그대로 전달 가능.

## 5. 파인튜닝 로드맵 (선택)

1. **결정 로그 축적**: `TuningResult.features` + 최종 `decision.toJson()` +
   사용자의 사후 수정(앱에서 슬라이더를 다시 만진 경우)을 세션별로 기록.
2. **LoRA 파인튜닝**: Needle 3는 20레이어 베이스에 LoRA를 얹고 `needle build`로 병합·
   슬라이싱한다(모델 카드 기준, 도메인 튜닝으로 서브넷 정확도 +18~36pt 사례).
   우리 레이블은 "피처 → 사용자가 최종 수용한 파라미터" 세트.
3. **작은 서브넷 배포**: 튜닝 후 4–8레이어(≈29MB 이하)로 슬라이싱해 모바일 배포.
4. **회귀 게이트**: `packages/vtracer_ai/test/`의 골든 피처 세트에 "결정이 사용자 수정
   중심값과 일치" 어설션을 추가해 재학습 품질을 CI에서 검증.

## 6. 트러블슈팅

| 증상 | 원인/조치 |
|---|---|
| `Needle3Exception: endpoint returned HTTP ...` | serve 프로세스 미기동/포트 불일치 — 앱은 자동으로 휴리스틱 폴백 |
| 응답 파싱 실패 | serve 응답 필드명 차이 — `parseNeedle3Answer`의 키 후보에 추가 |
| `model abstained: no tool call dispatched` | 엔진 그라운딩 검증이 호출을 억제(베이스 모델의 정상 동작) — 휴리스틱 폴백, §5 파인튜닝으로 개선 |
| `model choice is not one of A/B/C` | chooser 응답의 글자가 유효하지 않음 — 휴리스틱 폴백 |
| 결정이 항상 `needle3Repaired` | 모델이 필수 필드를 누락·범위 이탈 — 시스템 프롬프트/스키마 확인, 로그로 드리프트 추적 |
| `tool call truncated: token budget exhausted` | 프롬프트 접두사가 무거워 모델이 반복 루프 진입 — compact/chooser 프로파일 사용(내장 경로 기본), `--max` 상향 |
| 내장 모델이 실행 안 됨 (앱) | 엔진/모델 자산 미번들 플랫폼(macOS·Linux·Web) — 휴리스틱으로 동작, §3 매트릭스 참조 |

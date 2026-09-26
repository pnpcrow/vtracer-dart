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

### 1-3. Flutter 앱 (vtracer_app)

1. **설정 → Needle3 엔드포인트**에 `needle --serve` 주소(예: `http://127.0.0.1:8080/run`)를
   넣는다. 비워 두면 내장 휴리스틱으로 동작(기본값, 오프라인).
2. 왼쪽 패널 **AI 자동** 섹션에서 목표(균형/충실/경량)를 고르고 **분석 후 적용** 클릭.
3. 패널의 모든 슬라이더가 결정값으로 움직이고 즉시 변환 결과가 갱신된다. 섹션 하단에
   엔진·신뢰도·판단 근거가 표시된다.

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

| 플랫폼 | 경로 | 비고 |
|---|---|---|
| Windows / macOS / Linux (CLI·앱) | `Needle3ProcessRuntime`(needle CLI) 또는 `Needle3HttpRuntime`(serve) | 프로세스 1회 기동, 상시 serve 권장 |
| Android / iOS | **C API FFI 바인딩**(아래) | 플랫폼 엔진 <1MB를 앱에 포함 |
| Web (Flutter web) | serve 프록시 | 브라우저 WASM 엔진은 모델 카드의 browser 데모 참조 |

### 3-1. 모바일 C API FFI 바인딩 (확장 지점)

Cactus 저장소의 플랫폼 폴더에 C API 헤더와 엔진 바이너리가 있다. 새 런타임은
`Needle3Runtime`을 구현하면 되고, 다른 코드는 전혀 바뀌지 않는다:

```dart
class Needle3FfiRuntime implements Needle3Runtime {
  // 1) 플랫폼 엔진 dylib 로드 (android: jniLibs, ios: frameworks)
  // 2) needle_init(model_path, tools_json) → 정적 프리픽스 토큰 수 확인
  // 3) needle_run(system, prompt) → JSON 버퍼
  // 4) parseNeedle3Answer(jsonDecode(buffer))로 마무리
  @override
  Future<Needle3Answer> run(Needle3Invocation invocation) async {
    final json = _needleRun(invocation.system, invocation.prompt);
    return parseNeedle3Answer(jsonDecode(json));
  }
}

final tuner = AutoTuner(Needle3DecisionEngine(runtime: Needle3FfiRuntime()));
```

주의: 모델 카드 기준 `needle_init`이 정적 프리픽스(시스템 프롬프트 + 도구 스키마)의
토큰 수를 반환하고 컨텍스트 초과 시 실패한다. 도구 스키마는 이미 최소화되어 있지만
시스템 프롬프트를 늘릴 때는 이 값을 확인할 것.

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
| 결정이 항상 `needle3Repaired` | 모델이 필수 필드를 누락·범위 이탈 — 시스템 프롬프트/스키마 확인, 로그로 드리프트 추적 |
| `needle_init` 실패 (모바일 FFI) | 정적 프리픽스(시스템 프롬프트+스키마)가 컨텍스트 초과 — 프롬프트 축소 |
| 모델 호출이 느림 | `.cact` 레이어 수 줄이기(`--layers`), serve 상시 기동, 피처 페이로드는 이미 수백 토큰으로 최소화됨 |

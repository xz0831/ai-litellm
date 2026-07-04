# P3: 모델 라인업 교체 + Codex 실명 카탈로그 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude tier를 새 라인업(fable=Kimi-K2.7-Code, opus=GLM-5.2, sonnet=Mimo-V2.5, haiku=Qwen3.6-27B-omlx)으로 교체하고, Codex의 gpt-* facade를 실명 카탈로그 엔트리로 전환한다(`codex-auto-review`만 유지, Kimi-K2.7-Code로 재지정). P2 carry-over(고아 헬퍼 3개 + status 폴리시 2건)를 함께 처리한다.

**Architecture:** 스파이크(T0)가 codex 실명 클라우드 엔트리의 실동작을 배선 전에 검증한다(go/no-go). 이후 P1/P2 패턴: check RED flip → registry/settings/descriptor/generator 편집 → lib.zsh facade 제거+carry-over → budget 재앵커 + 전체 check GREEN 단일 커밋 → 자격검증 프로브 → 문서 → 머신 반영(sync = proxy 재시작 포함).

**Tech Stack:** zsh/ruby/node (lib.zsh, codex shell.zsh 생성기), YAML registry, JSON descriptors, OpenRouter API.

**Spec:** `docs/superpowers/specs/2026-07-04-ai-litellm-refactor-design.md` §6 + P2 최종리뷰 carry-over (원장 `.superpowers/sdd/p2-remove-tui-router/progress.md`)

## 확정 입력 (OpenRouter 정본 확인 완료, 2026-07-04)

| 대상 | OpenRouter id | ctx | max output | 비고 |
|---|---|---|---|---|
| fable | `moonshotai/kimi-k2.7-code` | 262144 | 16384 (provider) | 출력캡이 작음 — 예약이 capability로 클램프되는 케이스 |
| opus | `z-ai/glm-5.2` | 1048576 | **API 현재값 128000** (앵커는 131072) | refresh-capabilities로 reconcile |
| sonnet | `xiaomi/mimo-v2.5` | 1048576 | 미공개 → **owned-policy 131072** (GLM 선례) | 사용자 확정: 일반판(Pro 아님) |
| haiku | (로컬) `openai/Qwen3.6-27B-4bit` @ :8000 | 131072/16384 (owned) | 기존 `Qwen3.6-27B-omlx` 라우트·앵커 그대로 |

파생 수치(예약 32000·headroom 8192 기준): Kimi-K2.7-Code effective_input = 262144 − min(32000,16384) − 8192 = **237568**. GLM/Mimo effective_input = 1048576 − 32000 − 8192 = **1008384** (기존 핀과 동일값).

## Global Constraints

- 라인 번호는 커밋 `dc37d8b` 기준 앵커다. 어긋나면 **인용된 앵커 텍스트로** 위치를 찾는다.
- native 디렉토리 무접촉 / 날짜 있는 결정 로그·관측 seed는 역사로 보존(**context-observations.json의 DeepSeek 관측 기록은 라우트가 죽어도 삭제 금지** — F2.5 규칙) / goose·opencode·dash legacy cleanup 유지.
- check.zsh 전체 battery는 단일 single-quoted `zsh -fc` 문자열 — **어포스트로피 삽입 금지**, node -e는 escaped-double-quote 관용구.
- 함수/블록 삭제 시 **그 callee들의 caller-count 재스윕**(P2 최종리뷰 습관 권고) — 새 고아를 만들지 않는다.
- 커밋은 check green 상태에서만. 검증은 pipefail-safe 관용구(`> /tmp/log 2>&1; rc=$?`).
- 과금 발생 태스크는 T0(스파이크)·T8(자격검증 프로브)뿐이며 각각 1-2문장 one-shot 호출로 최소화한다.
- 커밋 메시지 말미: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 0: 스파이크 — codex 실명 클라우드 엔트리 go/no-go (머신, 소액 과금)

**Files:** 없음 (설치본 state의 생성 카탈로그를 임시 편집 — git 밖; 종료 시 원복)

**Interfaces:**
- Produces: go/no-go 판정 + (③에서) review 기능의 카탈로그 의존 여부 → T4의 catalogEntries에 codex-auto-review 추가 여부 결정.

- [ ] **Step 1: 설치 카탈로그 백업 + 실명 엔트리 수동 추가**

```bash
CAT=~/.local/share/ai-litellm-fabric/state/codex-litellm/model-catalog.json
cp "$CAT" /tmp/p3-spike-catalog.bak
node -e '
const fs=require("fs");const p=process.argv[1];const c=JSON.parse(fs.readFileSync(p,"utf8"));
const base=c.models.find(m=>m.slug==="gpt-5.4-mini");
c.models.push({...base,slug:"GLM-5.2-openrouter",display_name:"GLM-5.2 (openrouter)",description:"Real-name spike entry.",priority:95,additional_speed_tiers:[],service_tiers:[],availability_nux:null,upgrade:null,supports_search_tool:false});
fs.writeFileSync(p,JSON.stringify(c,null,2)+"\n");console.log("spike entry added");
' "$CAT"
```

(GLM-5.2-openrouter 라우트는 registry에 이미 존재하므로 proxy 쪽 준비 불요.)

- [ ] **Step 2: ① exec 스모크 (BILLABLE, 1문장)**

Run: `codex-litellm GLM-5.2-openrouter exec --skip-git-repo-check --sandbox read-only 'Reply with exactly OK' 2>&1 | tail -5`
Expected: `OK` 응답. 실패(슬러그 검증 거부/400) 시 그 출력 그대로 보고서에 담고 **no-go 판정 → BLOCKED** (폴백=표시명-만 실명화, 스펙 §6.3).

- [ ] **Step 3: ② picker/목록 확인 (무과금)**

Run: `codex-litellm --list 2>&1 | head -20`
Expected: `GLM-5.2-openrouter` 항목이 표시명과 함께 노출.

- [ ] **Step 4: ③ review 기능의 카탈로그 의존 판정 (무과금-우선)**

임시 카탈로그에서 gpt-* 엔트리를 전부 뺀 사본을 만들어 review가 뜨는지 기동만 확인:

```bash
node -e '
const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
c.models=c.models.filter(m=>!/^gpt-/.test(m.slug));
fs.writeFileSync(process.argv[1],JSON.stringify(c,null,2)+"\n");
' "$CAT"
codex-litellm review --help >/dev/null 2>&1; echo "help rc=$?"
```

review 실행 경로가 카탈로그에서 `codex-auto-review` 슬러그를 요구하는지 여부를 판단할 수 있는 가장 싼 신호를 기록한다(기동 에러 메시지에 슬러그/카탈로그 언급이 있으면 의존 O). 판단이 안 서면 "의존 여부 불명 — 안전측으로 catalogEntries에 codex-auto-review 포함"으로 기록.

- [ ] **Step 5: 원복 + 보고**

Run: `cp /tmp/p3-spike-catalog.bak "$CAT" && echo restored`
보고서에 ①②③ 결과와 **go/no-go**를 명시.

---

### Task 1: check.zsh 기대값 뒤집기 (RED)

**Files:**
- Modify: `scripts/check.zsh` — 아래 사이트들 (라인은 dc37d8b 기준)

**Interfaces:**
- Produces: 새 라인업·실명 codex를 단언하는 check. RED 원천 = 코드가 아직 구 라인업이므로 매핑/기본값 단언들이 죽는다.

- [ ] **Step 1: resolver/limits/reasoning 스모크 재키잉 (L87-91)**

```
old: test "$(ai_litellm_model_resolve openrouter/deepseek/deepseek-v4-pro)" = "DeepSeek-V4-Pro-openrouter"
new: test "$(ai_litellm_model_resolve openrouter/moonshotai/kimi-k2.7-code)" = "Kimi-K2.7-Code-openrouter"
old: test "$(ai_litellm_model_resolve deepseek/deepseek-v4-pro)" = "DeepSeek-V4-Pro-openrouter"
new: test "$(ai_litellm_model_resolve xiaomi/mimo-v2.5)" = "Mimo-V2.5-openrouter"
old: test "$(ai_litellm_model_backend openrouter/deepseek/deepseek-v4-pro)" = "openrouter/deepseek/deepseek-v4-pro"
new: test "$(ai_litellm_model_backend openrouter/moonshotai/kimi-k2.7-code)" = "openrouter/moonshotai/kimi-k2.7-code"
old: ai_litellm_model_limits openrouter/moonshotai/kimi-k2.6 >/dev/null
new: ai_litellm_model_limits openrouter/xiaomi/mimo-v2.5 >/dev/null
old: test "$(ai_litellm_model_reasoning_allowed_efforts openrouter/deepseek/deepseek-v4-pro)" = "none minimal low medium high xhigh"
new: test "$(ai_litellm_model_reasoning_allowed_efforts openrouter/z-ai/glm-5.2)" = "none minimal low medium high xhigh"
```

- [ ] **Step 2: gemma dedup 테스트 재키잉 (L100-104)**

Gemma 영구 엔트리가 사라지므로 dedup 전제를 Qwen 엔트리로 교체: `ai_litellm_runtime_routes_write omlx 1 MarkItDown Qwen3.6-27B-4bit` 형태로 바꾸고, 주석(L102)과 부정 단언(L104)을 `Qwen3.6-27B-omlx registry entry serves openai/Qwen3.6-27B-4bit` / `!= *"Qwen3.6-27B-4bit-omlx"*` 로 재서술. (기존 테스트의 의미 — "registry가 이미 서빙하는 백엔드는 discovered route를 만들지 않는다" — 는 유지.)

- [ ] **Step 3: harness alias set 왕복 재키잉 (L230-233)**

`fable`을 임시로 딴 모델로 set→복원하는 왕복 테스트. `DeepSeek-V4-Pro-openrouter` 참조 2곳을 `GLM-5.2-openrouter`로 교체(임시 대상은 라인업 내 아무 실명 라우트면 됨; fable 원값은 Kimi-K2.7-Code-openrouter가 된다).

- [ ] **Step 4: codex facade 테스트 블록 삭제 (L237-263 부근)**

`codex facade get/set` 왕복(L241-245), anchor-guard(L253-263, PlainLocal 사용) 등 facade 관련 블록 전체 삭제 — facade 명령 자체가 T6에서 사라진다. 대체 단언(자리 그대로):

```zsh
"$HOME/.local/bin/ai-litellm" harness info codex --json >/dev/null
test "$(ai_litellm_harness_json codex models.default)" = "GLM-5.2-openrouter"
echo "ok: codex real-name default (facade surface retired)"
```

(주의: L421의 기존 `models.default = "gpt-5.5"` 단언은 이 값으로 **교체**하고, 여기 새 블록과 중복되면 한쪽만 남긴다.)

- [ ] **Step 5: refresh-capabilities 픽스처 재키잉 (L374)**

목 픽스처의 3개 모델을 새 라인업으로 교체 (single-quoted battery 안이므로 어포스트로피 금지 그대로):

```
{"data":[{"id":"moonshotai/kimi-k2.7-code","context_length":262144,"top_provider":{"context_length":262144,"max_completion_tokens":16384},"supported_parameters":["reasoning","reasoning_effort"]},{"id":"xiaomi/mimo-v2.5","context_length":1048576,"top_provider":{"context_length":1048576},"supported_parameters":["reasoning","reasoning_effort"]},{"id":"z-ai/glm-5.2","context_length":1048576,"top_provider":{"context_length":1048576,"max_completion_tokens":128000},"supported_parameters":["reasoning","reasoning_effort"]}]}
```

(mimo는 max_completion_tokens 자체를 생략 — owned-policy 케이스의 drift-미보고를 그대로 검증.)

- [ ] **Step 6: 핀·파생 단언 재키잉 (L32 주석, L418-430, L567)**

- L32 주석의 `221950` → `237568`로 갱신 (1008384/3277은 유지 — Mimo·GLM이 1008384를 공유, 3277은 합성 소형 윈도우 값).
- L418 `ai_litellm_context_observations DeepSeek >/dev/null` — **유지** (seed 역사 기록은 불변).
- L421 codex default 단언 → Step 4 참조.
- L422-부근 `ai_litellm_harness_output_budget claude sonnet Kimi-K2.6-openrouter` → `claude sonnet Mimo-V2.5-openrouter`로 바꾸고 기대값을 1008384 계열로 갱신; fable 쪽 한 줄을 추가해 `claude fable Kimi-K2.7-Code-openrouter` → effective 237568 단언 (капability-클램프 경로의 살아있는 핀).
- L430 codex catalog map `Gemma4-12B-omlx` → `Qwen3.6-27B-omlx` = `131072` (로컬은 카탈로그 축소 면제 규칙 그대로).
- L567 proxy env 단언 `haiku=Gemma4-12B-omlx` → `haiku=Qwen3.6-27B-omlx`.

- [ ] **Step 7: RED 확인**

Run: `zsh -n scripts/check.zsh && { ./scripts/check.zsh > /tmp/p3-t1.log 2>&1; rc=$?; tail -8 /tmp/p3-t1.log; echo "exit=$rc"; }`
Expected: 문법 통과, 실행 FAIL — 첫 실패는 Step 1의 resolver 단언(신규 라우트 미존재). 커밋 금지.

---

### Task 2: Registry — 앵커/라우트 교체

**Files:**
- Modify: `config/litellm_config.yaml`

**Interfaces:**
- Produces: 실명 라인업 registry. T3-T5가 이 model_name들을 참조: `Kimi-K2.7-Code-openrouter`, `GLM-5.2-openrouter`, `Mimo-V2.5-openrouter`, `Qwen3.6-27B-omlx`, `codex-auto-review`.

- [ ] **Step 1: 새 앵커 2개 추가 (x-limits, 기존 앵커들과 같은 서식)**

```yaml
  kimi_k27_code: &kimi_k27_code
    max_input_tokens: 262144
    max_output_tokens: 16384
    supports_reasoning: true
    x_input_confidence: provider
    x_input_source: openrouter.top_provider.context_length
    x_output_confidence: provider
    x_output_source: openrouter.top_provider.max_completion_tokens
  mimo_v25: &mimo_v25
    max_input_tokens: 1048576
    max_output_tokens: 131072
    supports_reasoning: true
    x_input_confidence: provider
    x_input_source: openrouter.top_provider.context_length
    x_output_confidence: owned-policy
    x_output_source: openrouter-unpublished; conservative ceiling mirroring glm52 precedent
```

- [ ] **Step 2: 라우트 교체**

- 추가 (실명 컨벤션, 기존 엔트리 서식):

```yaml
  - model_name: Kimi-K2.7-Code-openrouter
    litellm_params:
      model: openrouter/moonshotai/kimi-k2.7-code
      api_key: os.environ/OPENROUTER_API_KEY
    model_info: *kimi_k27_code

  - model_name: Mimo-V2.5-openrouter
    litellm_params:
      model: openrouter/xiaomi/mimo-v2.5
      api_key: os.environ/OPENROUTER_API_KEY
    model_info: *mimo_v25
```

- `codex-auto-review`: litellm_params.model → `openrouter/moonshotai/kimi-k2.7-code`, model_info → `*kimi_k27_code` (주석에 review 기능용 hidden 슬러그임을 유지).
- `glm52` 앵커 reconcile: `max_output_tokens: 131072` → `128000` (2026-07-04 OpenRouter API 확인값 — provider가 낮췄으므로 provider-confidence 정본 추종; `x_output_source` 주석도 갱신). T1 Step 5의 픽스처 128000과 일치해야 drift 테스트가 no-drift로 통과한다.
- 삭제: `gpt-5.5`/`gpt-5.4`/`gpt-5.4-mini`/`gpt-5.2`/`gpt-5.3-codex` 라우트 5개, `Kimi-K2.6-openrouter`, `DeepSeek-V4-Pro-openrouter`, `Gemma4-12B-omlx` 영구 엔트리, 앵커 `deepseek_v4_pro`/`kimi_k26`/`gemma_local`.
- 실험 라우트 판정: `Qwen3.6-Test-27B-omlx`·`PlainLocal-omlx`는 check.zsh의 modelInfoOverrides/inline-guard 테스트가 참조(T1 이후 PlainLocal의 facade-guard 참조는 사라짐). repo 전체 grep으로 **T1-이후 기준** 참조를 다시 세어: 참조가 남으면 유지+사유 주석, 없으면 삭제. (L151-154·L349-351의 discovery-sim 테스트는 throwaway 설정에 자체 생성하므로 committed 엔트리와 무관 — 근거로 기록.)
- `Qwen3.6-35B-A3B-4bit-omlx`(Phase-0 replication arm)는 유지.

- [ ] **Step 3: 검증**

Run: `python3 -c "import yaml;d=yaml.safe_load(open('config/litellm_config.yaml'));names=[m['model_name'] for m in d['model_list']];print(names)" 2>/dev/null || ruby -ryaml -rjson -e 'd=YAML.load_file("config/litellm_config.yaml",aliases:true);puts d["model_list"].map{|m|m["model_name"]}.inspect'`
Expected: gpt-* 부재, 신규 2개 존재, codex-auto-review 존재. `grep -c "deepseek\|kimi-k2.6\|gemma" config/litellm_config.yaml` == 0 (kimi-k2.7-code는 별개 문자열).

---

### Task 3: Claude settings 교체

**Files:**
- Modify: `config/claude-litellm/settings.json` (전체 교체)

- [ ] **Step 1: 파일 내용을 다음으로 교체**

```json
{
  "mode": "proxy",
  "default": "opus",
  "directDefault": "opus",
  "proxyDefault": "opus",
  "directAliases": {
    "fable": "moonshotai/kimi-k2.7-code",
    "opus": "z-ai/glm-5.2",
    "sonnet": "xiaomi/mimo-v2.5",
    "haiku": "xiaomi/mimo-v2.5"
  },
  "directDisplayNames": {
    "fable": "Kimi-K2.7-Code (openrouter)",
    "opus": "GLM-5.2 (openrouter)",
    "sonnet": "Mimo-V2.5 (openrouter)",
    "haiku": "Mimo-V2.5 (openrouter)"
  },
  "subagentModel": "z-ai/glm-5.2",
  "aliases": {
    "fable": "Kimi-K2.7-Code-openrouter",
    "opus": "GLM-5.2-openrouter",
    "sonnet": "Mimo-V2.5-openrouter",
    "haiku": "Qwen3.6-27B-omlx"
  },
  "displayNames": {
    "fable": "Kimi-K2.7-Code (openrouter)",
    "opus": "GLM-5.2 (openrouter)",
    "sonnet": "Mimo-V2.5 (openrouter)",
    "haiku": "Qwen3.6-27B (omlx)"
  }
}
```

(direct haiku=Mimo 폴백·subagentModel=opus 동행은 스펙 §6.1 확정 사항.)

- [ ] **Step 2: 검증**

Run: `jq . config/claude-litellm/settings.json >/dev/null && jq -r '.aliases.fable, .directAliases.haiku, .subagentModel' config/claude-litellm/settings.json`
Expected: 유효 JSON, `Kimi-K2.7-Code-openrouter` / `xiaomi/mimo-v2.5` / `z-ai/glm-5.2`

---

### Task 4: Codex descriptor + alias 교체

**Files:**
- Modify: `config/ai-litellm/harnesses/codex.json`, `config/codex-litellm/settings.json`

- [ ] **Step 1: codex.json `models` 블록 교체**

```json
  "models": {
    "default": "GLM-5.2-openrouter",
    "catalogBaseSlug": "gpt-5.4-mini",
    "catalogEntries": [
      { "slug": "Kimi-K2.7-Code-openrouter", "displayName": "Kimi-K2.7-Code (openrouter)", "description": "MoonshotAI Kimi K2.7 Code via OpenRouter through LiteLLM.", "priority": 96 },
      { "slug": "GLM-5.2-openrouter", "displayName": "GLM-5.2 (openrouter)", "description": "Z.ai GLM 5.2 via OpenRouter through LiteLLM.", "priority": 95 },
      { "slug": "Mimo-V2.5-openrouter", "displayName": "Mimo-V2.5 (openrouter)", "description": "Xiaomi MiMo V2.5 via OpenRouter through LiteLLM.", "priority": 94 },
      { "slug": "Qwen3.6-27B-omlx", "displayName": "Qwen3.6-27B (omlx)", "description": "Local Qwen3.6 27B 4-bit served by oMLX through LiteLLM.", "priority": 90, "defaultReasoningLevel": "low" }
    ]
  },
```

(`catalogBaseSlug`는 번들 스키마 **템플릿**으로만 쓰인다 — 유지. T0 Step 4가 "review 카탈로그 의존 O/불명"이면 codex-auto-review 엔트리를 목록 끝에 추가: `{ "slug": "codex-auto-review", "displayName": "Codex Auto Review", "description": "Hidden review-model route (Kimi-K2.7-Code backend).", "priority": 29 }`.)

- [ ] **Step 2: adapterConfig의 stale 키 정리**

`"availabilityNux": { "gpt-5.5": 4 }` 블록 삭제 (대상 슬러그 소멸; 생성 엔트리는 어차피 null 주입).

- [ ] **Step 3: codex-litellm/settings.json aliases 교체**

```json
{
  "aliases": {
    "kimi": "Kimi-K2.7-Code-openrouter",
    "glm": "GLM-5.2-openrouter",
    "mimo": "Mimo-V2.5-openrouter",
    "qwen": "Qwen3.6-27B-omlx"
  }
}
```

- [ ] **Step 4: 검증**

Run: `jq . config/ai-litellm/harnesses/codex.json >/dev/null && jq -r '.models.default, (.models.catalogEntries|length)' config/ai-litellm/harnesses/codex.json && jq . config/codex-litellm/settings.json >/dev/null && echo OK`
Expected: `GLM-5.2-openrouter` / `4`(또는 5) / `OK`. `grep -c localCatalogEntries config/ai-litellm/harnesses/codex.json` == 0.

---

### Task 5: 카탈로그 생성기 재설계 (shell.zsh)

**Files:**
- Modify: `config/codex-litellm/shell.zsh` — `codex-litellm-refresh-catalog()`(L267-379 부근) + facade-우선 resolve 로직(L53 부근)

**Interfaces:**
- Consumes: T4의 `models.catalogEntries`; registry의 model_name 집합.
- Produces: 생성 카탈로그 = **보존 규칙**(번들 중 registry 라우트 있는 슬러그만 생존) + catalogEntries append. `ai_litellm_codex_catalog_context_map`(lib.zsh)은 무변경 — 슬러그가 실명이 되므로 자동으로 직결.

- [ ] **Step 1: ruby 빌더(L281-307) 교체**

`models.localCatalogEntries`+`local-` 자동 분기 로직을 제거하고: (a) `models.catalogEntries` 배열을 읽어 그대로 방출, (b) registry `model_list`의 model_name 집합을 함께 방출(JSON `{entries:[...], routes:[...]}`). displayName 미지정 엔트리는 `<이름 마지막 하이픈 앞> (<마지막 하이픈 뒤 소문자>)` 컨벤션으로 파생.

- [ ] **Step 2: node 병합기(L326-370) 교체**

- `catalog.models` 필터: `routes` 집합에 슬러그가 있는 번들 엔트리만 생존 (gpt-* 자동 탈락; `codex-auto-review`는 registry 라우트가 있으므로 자동 생존 — visibility:hide 그대로 복제됨).
- base 템플릿(catalogBaseSlug)은 **필터 전** 번들에서 찾는다 (gpt-5.4-mini는 필터로 죽지만 템플릿으로는 필요).
- `entries` append는 기존 로직 유지(슬러그/표시명/priority/defaultReasoningLevel/nux-null/tool-strip).
- context 스탬프 단계는 무변경.

- [ ] **Step 3: facade-우선 resolve 정리 (L53 부근)**

`Array(descriptor.dig("models","localCatalogEntries"))...preferred` 로직에서 descriptor 키를 `catalogEntries`로 갱신. "raw 백엔드 id 입력 시 같은 backend의 codex-safe facade 우선" 규칙은 실명 전환 후 "같은 backend의 registry model_name 우선"으로 자연 축소 — 관련 주석 갱신.

- [ ] **Step 4: 검증 (생성기 단독, 무과금)**

Run: `zsh -n config/codex-litellm/shell.zsh` 후, 렌더 전 검증은 불가(rendered-path 가드)이므로 ruby/node 조각을 픽스처로 단독 실행: 번들 목 JSON(gpt-5.4-mini+gpt-5.5+codex-auto-review)과 registry 목을 먹여 (a) gpt-5.5 탈락, (b) codex-auto-review 생존, (c) 실명 4엔트리 append를 단언. 실제 통합 검증은 T7의 check(throwaway 설치에서 catalog map 단언 L430)와 T10.

---

### Task 6: lib.zsh — codex facade 표면 제거 + P2 carry-over

**Files:**
- Modify: `config/ai-litellm/lib.zsh`

**Interfaces:**
- Consumes: facade 명령은 T1에서 check 참조가 이미 제거됨.
- Produces: facade-free lib. T7이 budget 재앵커.

- [ ] **Step 1: codex facade 명령 제거**

- `ai_litellm_codex_facade_json()`(L5809-5825)·`ai_litellm_codex_facade_set()`(L5827-~5880) 함수 삭제 (경계는 컬럼-0 `}` — 내부 ruby heredoc 주의).
- `ai_litellm_cmd_codex()` 함수와 디스패치 `codex)` 줄 삭제 (grep으로 위치 확인; codex 그룹은 facade 동사뿐이었음 — 다른 동사가 있으면 BLOCKED 보고).
- usage에서 codex facade 줄 삭제.
- **callee 재스윕**: 삭제한 함수들이 부르던 helper 중 다른 호출자가 없어지는 것이 있는지 grep으로 확인, 있으면 함께 삭제하고 보고서에 기록.

- [ ] **Step 2: P2 carry-over — 고아 3개 삭제**

`ai_litellm_harness_is_subcommand`(:1107-1112), `ai_litellm_harness_default_model`(:1114-1117), `ai_litellm_context_claude_reservations_ok`(:5234-부근, 컬럼-0 `}`까지). 각각 삭제 전 caller-count 0 재확인(정의 제외).

- [ ] **Step 3: P2 carry-over — status 폴리시 2건**

`ai_litellm_cmd_status`에서: (a) arg guard를 `(( $# > 1 ))`도 거부하도록 강화 —

```zsh
  if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--json" ]] }; then
    echo "Usage: ai-litellm status [--json]" >&2
    return 1
  fi
```

(기존 case 블록을 이것으로 교체); (b) 매핑 포매터의 `e.model` → `e.model ?? "unset"`.

- [ ] **Step 4: 검증**

Run: `zsh -n config/ai-litellm/lib.zsh && grep -c "facade\|ai_litellm_cmd_codex" config/ai-litellm/lib.zsh`
Expected: 문법 통과. grep은 0 — 단, `__FABRIC_HOME__`류 무관 매치가 있으면 제외하고 판정(있다면 보고서에 목록).

---

### Task 7: budget 재앵커 + sync 생성물 + 전체 check GREEN + 단일 커밋

**Files:**
- Modify: `scripts/verify_budget_consistency.py` (RANGE 상수)
- 없음(그 외) — 검증+커밋

- [ ] **Step 1: budget 슬라이스 재앵커** — P1/P2와 동일 절차 (T6 삭제로 시프트; NODE/RUBY_CAT은 삭제 위치(≥1107)보다 위 457-589라 불변, RUBY_MAT/RUBY_RES 재계산). loud-fail 확인→갱신→exit=0.

- [ ] **Step 2: 매트릭스 정합 확인** — ROWS는 합성 체제라 값 변경 불요(L2의 262142/262142는 "출력캡=윈도우" 체제 테스트로 존치). 27행 카운트 불변임을 실행 출력으로 확인만.

- [ ] **Step 3: 전체 check GREEN**

Run: `./scripts/check.zsh > /tmp/p3-check.log 2>&1; rc=$?; tail -20 /tmp/p3-check.log; echo "exit=$rc"`
Expected: T1의 새 단언들(resolver 실명, codex default GLM, fable 237568 핀, haiku=Qwen env, catalog map Qwen 131072) 포함 전부 ok, exit=0. 실패 시 해당 태스크로 복귀(단언 약화 금지), 커밋 금지.

- [ ] **Step 4: 단일 커밋**

```bash
git add -A
git commit -m "feat!: swap model lineup and move codex to real-name catalog entries

New tiers: fable=Kimi-K2.7-Code, opus=GLM-5.2, sonnet=Mimo-V2.5,
haiku=Qwen3.6-27B (local). The codex gpt-* facades are removed; the
generated catalog now mirrors the registry (bundled entries survive only
with a matching route — codex-auto-review stays, repointed to
Kimi-K2.7-Code) plus explicit real-name catalogEntries. The codex facade
command surface is retired. Also folds P2 carry-overs: three orphaned
helpers deleted, status arg guard tightened, mappings formatter
null-safety.

Spec: docs/superpowers/specs/2026-07-04-ai-litellm-refactor-design.md §6

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: 신규 클라우드 모델 자격검증 프로브 (BILLABLE 소액)

**Files:** 없음 (관측 기록만 — 결과는 보고서 + 필요시 observations 기록 명령)

- [ ] **Step 1: 실행 시점 확인** — 이 태스크는 **T10(sync·proxy 재시작) 완료 후에 실행**한다: 새 라우트는 재시작된 proxy에서만 서빙된다. (커밋 게이트가 아니라 lineup 품질 게이트 — 실패 시 alias 1줄 재조정이 후속 커밋으로 이어진다.)

- [ ] **Step 2: TRIV 프로브 (×2 모델)**

```bash
claude-litellm fable -p 'What is 7 times 6? Reply with only the number.' --no-session-persistence --tools ''
claude-litellm sonnet -p 'What is 7 times 6? Reply with only the number.' --no-session-persistence --tools ''
```

Expected: 둘 다 `42` (간결 응답, drift 없음).

- [ ] **Step 3: DOMAIN 프로브 (×2 모델, 아키텍처 가이드의 표준 문제)**

CS-스테이지 노이즈 문제(정답 ~15.6µV)를 fable/sonnet에 각 1회. 결과(정답 여부·토큰 규모)를 보고서에 기록. 실패해도 BLOCKED가 아니라 **판정 기록** — 라인업 재조정은 사용자 결정(alias 1줄).

---

### Task 9: 문서 스윕 + 커밋

**Files:**
- Modify: `README.md`, `docs/AI_AGENT_LITELLM_ARCHITECTURE.md`, `docs/DESIGN_RATIONALE.md`, `docs/APPLYING_MODELS_TO_HARNESSES.md`

- [ ] **Step 1: README** — tier/facade 표(L241-247 부근)를 새 라인업으로; "Codex-safe facade" 문단(L231-234)을 실명 카탈로그 규칙으로 재서술; 스모크 예시의 모델명 갱신 (`Gemma4-12B-omlx` 예시 → `Qwen3.6-27B-omlx`).
- [ ] **Step 2: ARCHITECTURE** — 결론의 facade 문구, `Codex Model Catalog` 절(보존 규칙+catalogEntries로 재서술), `모델 추가 절차` step 2/3(cloud 모델 = 실명 라우트+catalogEntries 1줄), reasoning/context 예시의 gpt-* → 실명, 새 dated 결정 로그 항목: `- codex 실명 전환·라인업 교체: 2026-07-04 gpt-* facade 제거(codex-auto-review만 유지, Kimi-K2.7-Code 재지정), 생성 카탈로그 = registry 거울(보존 규칙+catalogEntries), tier: fable=Kimi-K2.7-Code opus=GLM-5.2 sonnet=Mimo-V2.5 haiku=Qwen3.6-27B-omlx.` 기존 06-19/06-20 로그는 보존.
- [ ] **Step 3: RATIONALE** — §3의 두 facade 결정([기록] 항목들)에 goose식 대체 표기: 원문 유지 + 말미에 `**대체됨(2026-07-04)**: 원문이 예고한 재론 조건이 UX 실사용 근거로 발동 — 실명 이전 단행(스펙 §6). 카탈로그 제약(번들 스키마 템플릿·보존 규칙)은 생성기에 승계.` §1 tier 서술의 모델명 갱신. §10 전제 표의 codex facade 행 갱신.
- [ ] **Step 4: APPLYING_MODELS** — 워크드 예시(DeepSeek/Kimi2.6 기준)를 새 라인업 기준으로 갱신; §3 codex 레시피를 catalogEntries 방식으로 재작성.
- [ ] **Step 5: 검증+커밋** — `grep -rn "gpt-5\.\|DeepSeek-V4\|Kimi-K2\.6\|Gemma4" README.md docs/*.md`의 잔존이 dated 로그/대체 표기뿐임을 판정. 커밋: `docs: real-name codex catalog and new lineup across guides` (+ Co-Authored-By).

---

### Task 10: 머신 반영 (sync = proxy 재시작 포함) + 최종 게이트

**Files:** 없음 (운영)

**사전 조건: proxy 재시작은 활성 claude-litellm/codex-litellm 세션을 끊는다 — 컨트롤러가 실행 시작 전 사용자에게 이 승인을 이미 받았어야 한다.**

- [ ] **Step 1:** `./scripts/install.zsh 2>&1 | tail -5` — 패키지 갱신
- [ ] **Step 2:** `ai-litellm sync 2>&1 | tail -10` — 파생물(코덱스 카탈로그·config, claude 오버레이) 재생성 + **proxy 재시작** (기존 stale-config 문제도 이 시점에 해소)
- [ ] **Step 3:** 스모크: `ai-litellm status | head -18` (매핑에 새 4-tier), `ai-litellm doctor --proxy 2>&1 | tail -6` (config currency 포함 전부 ok), `codex-litellm --list | head -12` (실명 4+auto-review), `claude-litellm haiku -p 'Reply with exactly LOCAL_OK' --no-session-persistence --tools ''` (로컬 Qwen — 무과금)
- [ ] **Step 4:** 수용 기준(스펙 §6) 대조 기록: 스파이크 기록 ✓ / `codex-litellm --list` 실명만 ✓ / `codex-litellm glm exec … OK`(T0에서 GLM로 실증; 여기서 alias 경로로 1회 재확인 — BILLABLE 1문장) / haiku 로컬 응답 ✓ / doctor 전 배터리 green ✓ — 이후 T8(자격검증 프로브) 실행.

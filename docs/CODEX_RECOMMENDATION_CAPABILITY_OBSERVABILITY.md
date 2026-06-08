# 강력 권고 — Capability Observability: "추측 값은 source of truth에 남기지 않는다"

대상: 다음 Codex 세션. 이 문서는 *권고(recommendation)*이며, 우선순위·구체 액션·완성 기준을 담는다.
근거: 직전 model↔harness 상호작용 감사(실측 ~$0.02) + gateway 클램프 라이브 검증.
관련 문서: `docs/MODEL_HARNESS_CONTEXT_AUDIT_FOR_CODEX.md`(C1–C7 상세), `docs/CLAUDE_DYNAMIC_WORKFLOW_AUDIT_FOR_CODEX.md`(패키징 감사).

---

## 0. 한 줄 지령

**source of truth 안의 모든 token/capability 숫자는 "provider-authoritative(정본 재조회)" 또는 "locally-observed(프로브 관측)" 중 하나여야 한다. 손으로 추측한 값은 남기지 않는다. 그리고 confidence 컬럼이 그 둘 중 무엇인지 항상 말해야 한다.**

이 시스템은 이미 reasoning(`reasoning-observations.json`)과 output(boundary probe)에서 "추측→관측 승격" 규율을 갖고 있다. 남은 작업은 그 규율을 **입력 윈도우**와 **provider 선언 cap** 두 capability 차원으로 확장하는 것뿐이다.

---

## 1. 이미 완료·검증됨 (다시 하지 말 것)

직전 검증에서 **라이브로 통과 확인**된 부분. 회귀시키지 말 것:

- **3-stage token 모델 동작**: capability(`x-limits`) → harness reservation(`adapterConfig.outputReservation`) → **gateway C4 클램프**.
- **C4 gateway 클램프(`config/ai_litellm_callbacks/output_clamp.py`)**: `async_pre_call_deployment_hook`가 `max_tokens`와 `max_completion_tokens`를 **둘 다** 클램프함을 단위검증(`scripts/verify_litellm_token_clamp.py` → `hook_enforced_client_output_cap: true`) + 라이브 end-to-end(Kimi에 `max_tokens=262144`/`max_completion_tokens=262144` → 이전 400, 현재 **200**)로 확인. → **C2(codex 출력 노출)·C4 해소 완료.**
- `ai-litellm audit model-policy` 9 ok, proxy/context/reasoning doctor 0 fail.
- 보안 게이트 통과(평문 key 0, 전부 `os.environ/`).

→ 즉 **안전(safety)은 이미 이중(클램프 + pre-call)으로 완성**. 남은 건 전부 **정직성(honesty)·용량(capacity)** 문제이지 위험이 아니다.

---

## 2. 강력 권고: 남은 4건을 "관측으로 박제 / 정본으로 갱신 / 정책으로 문서화"

| # | 항목 | 현재 상태 | 권고 처리 | 우선순위 |
|---|---|---|---|---|
| **C1** | claude `opus`가 DeepSeek 1,048,576을 실제로 honor하는지 | matrix는 `effective_input=1,008,384`를 보여주나 **미관측(inferred)** | **관측으로 전환** + 결과를 정직하게 인코딩 | ★ 최우선 |
| **C6** | GLM anchor 202752 vs 관측 204800; 출력 cap 131072 미관측 | **추측 anchor** | OpenRouter 정본 재조회로 갱신 + **일반화** | ★ 고-ROI |
| **C7** | codex `apply_patch type:"custom"` | **미검증 interop 위험** | backend별 프로브 1회로 관측 결정 | 중 |
| **C3** | gemma 8192 vs 런타임 131072 (~94% 낭비) | 보수적 under-cap, `sliding_window=1024` caveat | 품질 프로브로 상향 **또는** "의도적 정책"으로 명시 문서화 | 하 |

### C1 — opus 1M: 추측을 관측으로 (최우선)
honesty-first 아키텍처에서 가장 나쁜 상태는 "matrix가 1,008,384를 보여주는데 사실인지 모른다"이다.
1. **바운드 라이브 프로브 1회**: >200K 토큰 프롬프트로 claude→gateway→DeepSeek 세션을 띄워, 200K 근처에서 compact하는지(클램프됨) 1M 근처까지 가는지(honor됨) 관측.
2. **결과를 정직하게 인코딩**:
   - honor → 주입한 1M 유지, matrix confidence를 `observed`로.
   - 클램프 → **1M을 강요하지 말 것.** matrix에 진짜 값(≈200K)을 표기하고, DeepSeek의 1M 강점은 **그걸 실제 쓰는 codex 표면(`gpt-5.5`)으로 라우팅**한다(capability는 전역 낭비가 아니라 claude 표면만 200K). 1M을 굳이 올리려 `CLAUDE_CODE_MAX_CONTEXT_TOKENS`+`DISABLE_COMPACT`를 쓰는 것은 auto-compaction을 끄므로 **비권장**.
3. files: `config/claude-litellm/settings.json`, `config/claude-litellm/shell.zsh`.
4. **금지**: 관측 없이 config로 1M을 "선언"만 하고 끝내는 것. 그건 추측을 source of truth에 남기는 것이다.

### C6 — GLM 정본 갱신 + 일반화 (가장 cheap·고-ROI)
1. 즉시: OpenRouter `/api/v1/models`에서 `z-ai/glm-5.1`의 실제 context_length + max_completion_tokens 재조회 → `config/litellm_config.yaml` `glm51` anchor 갱신(202752→실측, 출력 cap 확정) → `ai-litellm sync`.
2. **강력 권고(남은 작업 중 장기 ROI 1위) — 일반화**: `ai-litellm model refresh-capabilities`를 신설.
   - OpenRouter `/api/v1/models`(provider 정본)를 당겨 각 underlying의 `x-limits` anchor(context/max_output/supports_reasoning)를 **reconcile**하고, anchor와 provider 정본이 어긋나면 `audit model-policy`/`context doctor`가 **drift로 warn**.
   - 효과: "손으로 적은 anchor가 시간이 지나며 썩는다"는 **고장 클래스 전체를 제거**. capability 축이 provider에 대해 self-verify하게 됨.
   - confidence: refresh로 채운 값은 `provider`, 손으로 둔 값은 `local-config`로 표기.

### C7 — apply_patch interop: 추측 말고 관측 (중)
1. backend별(DeepSeek/Kimi/GLM) `apply_patch` 프로브 1회를 라이브 proxy로 — 400 없이 diff가 적용되는지 관측.
2. 400이 관측되면 `config/codex-litellm/shell.zsh` 카탈로그 refresh에서 비-OpenAI slug에 `apply_patch_tool_type="function"` 설정. 400이 없으면 현 상태가 정답임을 관측으로 확정(문서에 `observed-ok` 기록).
3. **금지**: 관측 없이 "혹시 몰라" 미리 바꾸는 것.

### C3 — gemma: tradeoff를 데이터 또는 문서로 마감 (하)
위험이 아니라 낭비 + 품질 caveat(`sliding_window=1024`). 둘 중 하나면 "완성":
- 30k+ 입력에서 출력 coherence 프로브 1회 후 중간값(~32768)으로 `gemma_local.max_input_tokens` 상향(`config/litellm_config.yaml`) → `ai-litellm sync`, **또는**
- 8192를 **"런타임 capability(131072) 미만의 의도적 quality-conservative policy cap"으로 명시 문서화**하여, 지금 "오류처럼 보이는" doctor warn을 "owned decision"으로 격하.

---

## 3. 구조 추가 권고 (완성형)

개인 셋업이므로 모든 걸 자동화할 필요는 없다. "추측이 남지 않는다"만 충족하면 된다. 그 관점에서 만들 가치가 있는 것은 **딱 둘**, 우선순위 순:

1. **`ai-litellm model refresh-capabilities`** (강력 권고) — C6의 일반화. provider drift가 미래 고장의 가장 흔한 원인이므로 ROI 최고. provider 정본 ↔ anchor reconcile + drift warn.
2. **입력-윈도우 observed 프로브** (`ai-litellm context probe`의 실측 확장) — C1의 일반화. graduated-size 프롬프트로 각 harness의 **실제 사용 가능한 입력 윈도우**를 관측해 `reasoning-observations.json`과 같은 캐시에 박제. 이걸 하면 context matrix의 **모든 셀이 "provider-정본 또는 observed"**가 되어 confidence 컬럼을 완전히 신뢰 가능.

`output` 클램프와 `reasoning` 관측은 이미 있으므로, 위 둘을 더하면 **capability 4축(input window / output cap / reasoning / drift)이 전부 정본-or-관측**으로 닫힌다.

---

## 4. "완성됐다"의 정의 (acceptance)

다음을 모두 만족하면 이 아키텍처는 honesty/capacity 축에서 완성이다:

1. `ai-litellm audit model-policy` / `context doctor` / `reasoning doctor`에 남은 **모든 warn이 셋 중 하나**다:
   (a) 관측으로 해소되어 confidence가 `observed`, (b) provider 재조회로 채워져 confidence가 `provider`, (c) "의도적 정책"으로 문서에 명시된 owned decision.
2. matrix/anchor 어디에도 **출처 불명의 추측 숫자가 없다**(특히 C1의 1,008,384, C6의 202752는 관측/정본으로 교체되거나 정직한 실제값으로 정정).
3. C1 결과가 "클램프"로 나오면 1M을 강요하지 않고 **정직하게 200K로 표기 + DeepSeek 장문은 codex로 라우팅**.
4. safety(클램프+pre-call)는 회귀 없이 유지 — 위 작업은 capability 표기/용량에 관한 것이지 클램프를 약화시키면 안 된다.

즉 목표는 **unknown unknown = 0**: 모든 gap이 "소유한 결정" 또는 "큐에 든 관측"이다.

---

## 5. 가드레일 (반드시 준수)

- **temp-copy로만 변이 테스트**: `export AI_LITELLM_CONFIG=<mktemp copy>` 등. `verify_litellm_token_clamp.py`도 temp-copy 대상. 라이브 파일 직접 편집 금지.
- **native 불가침**: `~/.claude`/`~/.codex`에 쓰지 말 것, native CLI 교체 금지.
- **`ai-litellm sync`는 proxy를 재기동**(라이브 세션 영향) — 의도적으로만.
- **프로브는 바운드**: C1/C7/C3 라이브 프로브는 각 1회 수준, 유료 호출 남발 금지. 비용 명시.
- **secret-clean**: 새 문서/코드에 `sk-`류 리터럴/Bearer 토큰 예시를 넣지 말 것(repo `scripts/check.zsh` 시크릿 스캐너가 막는다 — 직전에 실제로 걸렸다).
- 각 항목은 **관측/정본 근거를 남기고**, 추측으로 고치지 말 것. 모르면 "미검증"으로 표기.

---

## 6. 권장 실행 순서

1. **C1 프로브** → opus 1M honor/clamp 관측, 결과대로 인코딩(가장 큰 unknown 제거).
2. **C6 즉시 갱신 + `model refresh-capabilities` 신설**(드리프트 클래스 제거, 최고 ROI).
3. **C7 프로브** → 마지막 interop 위험 관측 결정.
4. **C3** → 품질 프로브 후 상향 또는 정책 문서화.
5. (여력 시) **입력-윈도우 observed 프로브**로 matrix confidence 완전 신뢰화.
6. 마무리: 위 acceptance 4조건 충족 확인, doctor 재실행, 문서 갱신(MODEL_HARNESS 문서의 C1/C2/C4/C6/C7 상태를 RESOLVED/OBSERVED로 정정).

---

## 7. 직전 검증(2026-06-08)에서 새로 드러난 항목 — 강력 권고

지난 라운드 Codex 작업을 실측 검증한 결과, **doctrine 구현은 우수**했다(`model refresh-capabilities` 신설 + 앵커 `x_*_confidence/source` 메타데이터 + warn의 `owned-policy` 라벨 + C2/C4/C5 라이브 클램프 확인). 그러나 **"완성(unknown unknown=0)"에는 아직 미달**이며, 아래 두 건이 다음 작업의 **최우선**이다. (F1 매트릭스 stale은 이미 정정 완료 — `MODEL_HARNESS_CONTEXT_AUDIT_FOR_CODEX.md`의 opus 행/요약/ledger를 "observed >200K; full 1M unprobed"로 갱신함.)

### F2 — 작동하는 비용 가드레일 부재 ★ 신규 최우선 (capacity가 아니라 운영 안전)
- **사실(관측):** C1 프로브 1회 = **$1.05905**. Codex가 `--max-budget-usd가 이 LiteLLM 경로에서 hard cap으로 작동하지 않음`을 확인. full 1M 프로브는 ~$5+, 폭주 agent 루프는 그 이상 — **enforced spend cap이 없다.**
- **왜 최우선인가:** 멀티모델 게이트웨이에서 비용 폭주는 token-window 폴리싱보다 더 실질적인 위험이다. 지금은 known gap인데 **미소유** 상태 → "unknown unknown=0" 위배.
- **권고(택1, 관측으로 검증):**
  - (a) **LiteLLM proxy 레벨 예산**: virtual key/team `max_budget` + `budget_duration`, 또는 per-request `max_budget`로 provider 직전 거부. 단 spend 추적이 DB를 요구하는지(현재 무DB 빌드) **먼저 검증**할 것 — 무DB면 (b).
  - (b) **pre-call hook 가드레일**: 기존 `config/ai_litellm_callbacks/output_clamp.py`와 같은 자리에 per-request 토큰/추정비용 상한을 두고 초과 시 reject. output_clamp가 이미 `async_pre_call_deployment_hook`을 검증된 형태로 쓰므로 재사용 가능.
  - (c) 최소한: cap이 불가하면 "이 경로에 enforced spend cap 없음 + 수동 가드레일(작은 프롬프트/`max_tokens` 명시/세션 모니터링)"을 **owned-limitation으로 문서화**하고 doctor가 그 사실을 알리게.
- **검증:** temp-copy config로 hook/budget을 켜고, 상한 초과 요청이 provider 도달 전에 거부되는지 관측(클램프 검증과 동일 패턴). 라이브 유료 호출 남발 금지.
- **files:** `config/litellm_config.yaml`(`general_settings`/`litellm_settings`), `config/ai_litellm_callbacks/`(가드레일 hook), 필요 시 `scripts/verify_*`.

### F3 — 입력-윈도우 observed 프로브 일반화 ★ C1을 원칙대로 닫는 유일한 길
- **사실:** 구조 권고 1순위(`refresh-capabilities`)는 이행됐으나 **2순위(입력-윈도우 observed 프로브)는 미이행**. C1은 손으로 1회 잰 일회성이라 matrix에서 opus를 원칙적으로 `observed`로 박을 메커니즘이 없다 → **full 1M honor가 영구 unknown으로 남는다.**
- **권고:** `ai-litellm context probe <surface>`를 **실측 확장** — graduated-size 프롬프트(예: 200K→400K→800K, F2의 비용 가드레일 적용)로 각 harness의 **실제 사용 가능한 입력 윈도우**를 관측하고, `reasoning-observations.json`과 같은 캐시(`context-observations.json`)에 인코딩. 그러면:
  - context matrix의 입력 `observed` 컬럼이 진짜가 되고 confidence가 완전히 신뢰 가능해진다.
  - C1(opus 1M)이 "절반 관측"에서 "observed로 인코딩됨"으로 닫힌다.
  - 새 모델/harness가 들어와도 동일 프로브로 입력 윈도우를 박을 수 있다(미래 일반화).
- **반드시 F2 선행:** 큰 입력 프로브는 비용이 크므로 F2(가드레일) 없이는 안전하게 못 돌린다. **F2 → F3 순서.**
- **files:** `config/ai-litellm/lib.zsh`(`ai_litellm_context_probe` 확장), 신규 `context-observations.json`, `context matrix`의 observed 컬럼 소스.

### 부수 권고 (경미)
- **관측을 폐기하지 말 것(F2.5):** GLM `204800` 관측을 `202752`(provider 정본)로 대체하면서 관측값을 어디에도 기록하지 않았다. OpenRouter는 provider를 multiplex하므로 둘 다 참일 수 있다. **enforce는 보수적 `min(declared, observed)`로 하되 둘 다 인코딩**(`x_input_observed`)해 관측을 잃지 말 것.
- **C7:** 현재 "observed; no code change"(+한계 명시)는 doctrine상 합격. Codex가 비-OpenAI patch tool mode를 노출하기 전까지 deletion 유지가 맞다 — 추가 작업 불필요, 단 그 한계를 owned-limitation으로 유지.

### 갱신된 완성 정의
§4의 acceptance 4조건에 더해: **(5) 모든 유료 경로에 enforced 또는 명시-문서화된 비용 가드레일이 있고(F2), (6) matrix의 입력 윈도우가 provider-정본 또는 encoded-observed이며 일회성 메모가 아니다(F3).** 이 둘까지 충족하면 honesty·capacity·운영안전 축이 모두 닫힌다.

---

## 8. Codex 적용 상태 (2026-06-08)

- **F2 implemented:** production callback `ai_litellm_callbacks.output_clamp.proxy_handler_instance`가 output clamp 이후 `x-gateway-cost-guardrail`을 적용한다. 기본값은 estimated input `200000`, estimated total `240000`, `chars_per_token=4`이다. 이는 billing DB budget이 아니라 provider dispatch 전 deterministic token-estimate reject이다.
- **F2 verified:** `scripts/verify_litellm_token_clamp.py`가 mock provider에서 상한 초과 요청의 `upstream_body=null`을 확인한다. production callback 검증은 400을 반환하고 provider에는 도달하지 않았다.
- **F3 implemented:** repo seed `config/ai-litellm/context-observations.json`와 local state `state/ai-litellm/context-observations.json`을 합쳐 `ai-litellm context observations`와 `context matrix`가 읽는다. C1 `>=211580`과 GLM `>=204800` lower-bound 관측이 encoded-observed로 보존된다.
- **F3 boundary:** full 1M honor는 아직 관측하지 않았다. matrix의 `>=211580`은 하한 증거이지 1M 확정값이 아니며, 추가 대형 probe는 `ai-litellm context probe record ...`로 명시 기록해야 한다.

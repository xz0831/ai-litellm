# P8: litellm 1.91.0 업그레이드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** litellm 핀을 1.81.14 → 1.91.0으로 올린다. 1.9x가 Anthropic `/v1/messages`+tools를 Responses API로 라우팅해 tool-calling을 깨는 회귀를 `litellm_settings.use_chat_completions_url_for_anthropic_messages: true` 한 줄로 무력화(실측 5/5 복구, 1.81.14 no-op 확인됨). clamp C4 훅은 1.91.0에서도 필요·동작(변화 없음). (사용자 확정: 실제 업그레이드.)

**Architecture:** config 플래그 추가(litellm_config + fidelity 스크립트 생성 config) + CI 핀 bump + docs 버전 갱신(현재-핀은 1.91.0, 역사 관측은 보존 + 새 dated 로그) + 두 verifier를 1.91.0에서 재실측. RED 부적합(버전 bump) — green 게이트는 (a) 두 verifier가 1.91.0 venv에서 통과, (b) check.zsh green(config가 여전히 로드).

**근거 (실측, 2026-07-05):** 격리 조사 — 트리거 `litellm/llms/anthropic/experimental_pass_through/messages/handler.py::_should_route_to_responses_api()`. 플래그 off(1.9x 기본)면 `custom_llm_provider=="openai"` 라우트가 `/v1/responses`로 감(우리 백엔드 미서빙 → 실 회귀, mock 아티팩트 아님). 플래그 on → `/v1/chat/completions`, fidelity 5/5. clamp `recommended_policy: async_pre_call_deployment_hook`(1.81.14와 동일). prisma-500은 미인증 경로 한정(정상 운영 무관). Python <3.14 요구(pipx는 3.13 사용).

## Global Constraints

- **역사 vs 현재 구분**(dated-log 보존 패턴): "2026-06-15 실측 1.81.14" 류 dated 관측은 **역사 증거로 보존**; 현재-핀/enforcement 참조(CI, "핀" 서술, premise-watch)만 1.91.0으로. 새 2026-07-05 dated 로그로 마이그레이션 사건 기록.
- 플래그는 1.81.14 no-op(확인됨) — 무조건 추가 안전.
- lib/config 편집 후 clean-room 스모크(해당 시). 검증 pipefail-safe. 커밋 green에서만. Co-Authored-By. 디렉토리 가드.
- **격리 venv 재사용**: `/private/tmp/claude-501/-Users-xz0831/083c3363-147f-4d03-b81e-174a39d0fca0/scratchpad/litellm191-venv`(python3.13, litellm[proxy]==1.91.0). 없으면 재생성.
- P7(fabric purge) 이미 머지됨 — base는 그 위. 실 머신은 아직 1.81.14/옛 경로(P8-T2에서 마이그레이션).

## Task 1: config 플래그 + CI 핀 + docs + 1.91.0 재실측 + 커밋

**Files:** `config/litellm_config.yaml`, `scripts/verify_tool_call_fidelity.py`, `.github/workflows/ci.yml`, `README.md`, `docs/AI_AGENT_LITELLM_ARCHITECTURE.md`, `docs/DESIGN_RATIONALE.md`

- [ ] **Step 1: litellm_config.yaml 플래그** — `litellm_settings:`(L148) 블록의 `callbacks: [...]` 줄 다음에 추가(같은 들여쓰기):
```yaml
  # 1.9x routes Anthropic /v1/messages + tools to the Responses API by default;
  # our chat-completions backends (OpenRouter/vLLM) do not serve /v1/responses.
  # Force the chat-completions path. No-op on <=1.81.14 (the flag did not exist).
  use_chat_completions_url_for_anthropic_messages: true
```
- [ ] **Step 2: fidelity 스크립트 생성 config 플래그** — `scripts/verify_tool_call_fidelity.py`의 config 템플릿(`litellm_settings:` L269 부근)에 같은 키를 추가(스크립트가 emit하는 yaml 문자열 안). 이게 있어야 CI `tool-fidelity` 잡이 1.91.0에서 5/5. (clamp 스크립트는 /v1/messages 경로를 안 타므로 불필요 — 단, 구현자가 clamp 스크립트도 확인해 필요하면 추가; 무해.)
- [ ] **Step 3: CI 핀 bump** — `.github/workflows/ci.yml` L43·L85의 `'litellm[proxy]==1.81.14'` → `'litellm[proxy]==1.91.0'` (둘 다). setup-python이 3.12라 <3.14 제약 충족.
- [ ] **Step 4: docs 현재-핀 갱신 (역사 보존)**
  - DESIGN_RATIONALE §8 표(L225): "CI `tool-fidelity` 잡 (litellm 1.81.14 핀)" → "1.91.0 핀".
  - DESIGN_RATIONALE §10 premise-watch(L285): "LiteLLM 1.81.14의 clamp 결함 | C4 커스텀 훅..." → "LiteLLM 1.91.0(2026-07-05 재실측): clamp 훅 여전히 필요·동작; tool-call은 `use_chat_completions_url_for_anthropic_messages: true` 필요(1.9x가 /v1/messages를 Responses API로 라우팅) | ..." (전제-감시 유지).
  - §4 tool-fidelity 서술(L155)의 "CI 잡 tool-fidelity가 litellm 1.81.14 핀으로" → 1.91.0. "2026-06-15 실측 1.81.14"는 **역사 보존**(그날 그 버전 테스트 사실).
  - §4 clamp 서술(L143)·ARCHITECTURE L312/L637의 "1.81.14 기준 관찰" → clamp 동작은 1.91.0에서도 동일하므로 "1.81.14→1.91.0에서 재확인" 취지로 갱신하되 원 관측은 보존.
  - README L339 "Current local result with LiteLLM 1.81.14: ..." → "1.91.0"(현재 핀).
- [ ] **Step 5: 새 dated 결정 로그** — ARCHITECTURE에 `## 2026-07-05 litellm 1.91.0 업그레이드 결정 로그`(~4불릿): 1.9x Responses-API 라우팅 회귀 + 트리거 위치, `use_chat_completions_url_for_anthropic_messages` 플래그(1.81.14 no-op 실측), clamp 훅 불변(재실측), python<3.14/pipx 3.13. DESIGN_RATIONALE §4 tool-fidelity 절에도 짧은 갱신 문단(1.91.0 재실측 + 플래그).
- [ ] **Step 6: 1.91.0 재실측 (격리 venv)**
```zsh
VENV=/private/tmp/claude-501/-Users-xz0831/083c3363-147f-4d03-b81e-174a39d0fca0/scratchpad/litellm191-venv
[ -x "$VENV/bin/litellm" ] || { python3.13 -m venv "$VENV" && "$VENV/bin/pip" install --quiet 'litellm[proxy]==1.91.0'; }
"$VENV/bin/litellm" --version   # 1.91.0
# fidelity (mock, no billable) — with the flag now in the script's config → 5/5:
"$VENV/bin/python" scripts/verify_tool_call_fidelity.py --litellm-bin "$VENV/bin/litellm" 2>&1 | tail -12
# clamp — hook still recommended:
LITELLM_BIN="$VENV/bin/litellm" "$VENV/bin/python" scripts/verify_litellm_token_clamp.py 2>&1 | tail -6
```
  Expected: fidelity `=> OK` 5/5; clamp `recommended_policy: async_pre_call_deployment_hook`. 어느 하나라도 실패 → BLOCKED(플래그 배치/누락 확인). **실행 중 :4000 proxy·pipx 1.81.14 무건드림** (격리 venv만).
- [ ] **Step 7: check.zsh green** — litellm_config에 키 하나 추가됐으므로 config 로드/구조 확인. `./scripts/check.zsh > /tmp/p8.log 2>&1; rc=$?; tail -20 /tmp/p8.log; echo "exit=$rc"`. (check.zsh는 litellm 버전 비의존 — 1.81.14로 돌지만 config 유효성·구조를 검증.) green 아니면 BLOCKED.
- [ ] **Step 8: 커밋**
```
feat: upgrade litellm pin 1.81.14 -> 1.91.0 (chat-completions flag for Anthropic messages)

1.9x routes Anthropic /v1/messages+tools to the Responses API by default,
which our chat-completions backends do not serve — breaking tool-calling.
Add litellm_settings.use_chat_completions_url_for_anthropic_messages: true
(a no-op on <=1.81.14, verified) to force the chat-completions path;
re-verified 5/5 tool-call fidelity on 1.91.0 and confirmed the C4 output-clamp
hook is still required and works. Bump the CI tool-fidelity/token-clamp pins
and the fidelity script's generated config; historical 1.81.14 findings kept
as dated evidence, new 2026-07-05 migration log added.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

## Task 2: 통합 머신 rollout (P7 경로 마이그레이션 + litellm 1.91.0)

**Files:** 없음 (운영). **proxy 재시작 포함 — 활성 세션 없음 확인됨(2026-07-05).** 한 번의 마이그레이션으로 (a) P7 경로 이전 + (b) litellm 1.91.0을 동시에.

- [ ] **Step 1: litellm 1.91.0 설치 (pipx, python3.13)** — `pipx install --force --python python3.13 'litellm[proxy]==1.91.0'` (또는 `pipx runpip litellm install ...` — 현재 pipx litellm venv가 3.13이므로 `pipx upgrade` 대신 명시 버전 재설치). 확인: `~/.local/bin/litellm --version` → 1.91.0.
- [ ] **Step 2: 옛 proxy 정지 + 옛 경로 제거** — 현재 실행 중 proxy는 옛 경로(`~/.local/share/ai-litellm-fabric`) 기반. 옛 pid를 안전 정지(pid 파일의 pid가 litellm 프로세스인지 `ps` 확인 후 `kill`), 포트 4000 해제 확인. 그다음 옛 dir `rm -rf ~/.local/share/ai-litellm-fabric` (keychain 시크릿 경로 독립 — 안전).
- [ ] **Step 3: 새 경로 설치** — `./scripts/install.zsh 2>&1 | tail -8` (prefix 기본이 이제 `~/.local/share/ai-litellm`; 새 토큰 `__AI_LITELLM_HOME__`으로 렌더, litellm_config에 플래그 포함).
- [ ] **Step 4: sync (새 proxy 기동, 1.91.0 + 플래그 + 새 경로)** — `ai-litellm sync 2>&1 | tail -10`. proxy가 1.91.0으로 4000에 기동.
- [ ] **Step 5: 검증**
  - `~/.local/bin/litellm --version` → 1.91.0; `ls ~/.local/share/ | grep ai-litellm`(새 것만, 옛 경로 부재).
  - `ai-litellm doctor --proxy 2>&1 | tail -6` → config currency 포함 전부 green.
  - `ai-litellm status | head -8` → 매핑 정상.
  - **tool-call end-to-end 스모크 (무과금 로컬)**: `claude-litellm haiku -p 'Use no tools; reply with exactly READY' --no-session-persistence --tools ''` 로 기본 왕복 확인. tool-calling 실경로 확인이 필요하면 로컬 Qwen(haiku)로 간단한 tool 유도(무과금) — 실패 시 플래그/렌더 확인.
- [ ] **Step 6: 수용 기준** — litellm 1.91.0 / 새 경로 단독 / doctor green / status·tool 왕복 정상 / 옛 경로·옛 proxy 제거. 기록.

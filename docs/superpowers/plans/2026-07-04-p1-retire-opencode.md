# P1: OpenCode 은퇴 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OpenCode harness 지원을 goose 은퇴(2026-06-28) 패턴 그대로 완전히 제거하고, 기존 설치본의 opencode 잔재를 install-시점 legacy cleanup으로 정리한다.

**Architecture:** 삭제 리팩터. check.zsh 기대값을 먼저 뒤집고(RED), lib.zsh 어댑터/생성기/닥터 분기 → 파일·인스톨러 → budget 차분테스트 라인 재앵커 순으로 제거한 뒤, 전체 check green 상태에서 단일 커밋한다(GREEN). 문서는 별도 커밋.

**Tech Stack:** zsh (lib.zsh, install/uninstall/check), 임베디드 node/ruby 블록, Python (verify_budget_consistency.py), JSON descriptor/schema.

**Spec:** `docs/superpowers/specs/2026-07-04-ai-litellm-refactor-design.md` §4

## Global Constraints

- 라인 번호는 커밋 `49426e9` 기준 앵커다. 어긋나면 **인용된 앵커 텍스트로 위치를 찾는다** (라인 번호 맹신 금지).
- native 디렉토리(`~/.claude`, `~/.codex`) 무접촉 — 기존 check가 단언하며, 이 계획은 그 단언을 건드리지 않는다.
- 문서의 **날짜 있는 결정 로그(2026-06-07/08/11 등)의 opencode 언급은 역사 기록이므로 보존한다**. 현재-상태 서술만 수정한다.
- goose legacy cleanup(`remove_retired_goose_support`)은 유지한다.
- 커밋은 `scripts/check.zsh` green 상태에서만 만든다 (Task 중간 상태는 커밋하지 않는다).
- 커밋 메시지 말미: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: 브랜치 생성 + check.zsh 기대값 뒤집기 (RED)

**Files:**
- Modify: `scripts/check.zsh:117`, `:121`, `:209`, `:614-617`, `:650`, `:665`

**Interfaces:**
- Produces: opencode-free 세계를 단언하는 check.zsh — Task 5의 green 게이트가 이 기대값으로 판정된다.

- [ ] **Step 1: 브랜치 생성**

```bash
cd /Users/xz0831/ai-litellm-fabric
git switch spec/2026-07-04-refactor && git switch -c refactor/p1-retire-opencode
```

- [ ] **Step 2: harness 목록 단언 축소 (L209)**

`scripts/check.zsh` L209에서 문자열 `claude,codex,opencode`를 찾아 다음으로 교체:

```
old: if(names!==\"claude,codex,opencode\")
new: if(names!==\"claude,codex\")
```

- [ ] **Step 3: rendered-path 가드 프로브 대상 교체 (L117, L121)**

opencode 경로 대신 codex 경로로 가드 테스트를 유지한다:

```
L117 old: if ai_litellm_assert_rendered_path "__FABRIC_HOME__/state/opencode-litellm" "test" 2>/dev/null; then
L117 new: if ai_litellm_assert_rendered_path "__FABRIC_HOME__/state/codex-litellm" "test" 2>/dev/null; then
L121 old: ai_litellm_assert_rendered_path "$prefix/state/opencode-litellm" "test"
L121 new: ai_litellm_assert_rendered_path "$prefix/state/codex-litellm" "test"
```

- [ ] **Step 4: opencode 렌더·권한 블록 삭제 (L614-617)**

`ai_litellm_render_opencode_config opencode` 호출과 그 뒤 `stat -f %Lp "$prefix/state/opencode-litellm/opencode.json"` 퍼미션 단언(= "600" 비교)을 포함한 블록 전체를 삭제한다.

- [ ] **Step 5: harness 루프 축소 (L650) + sync 출력 단언 삭제 (L665)**

```
L650 old: for harness in claude codex opencode; do
L650 new: for harness in claude codex; do
L665: [[ "$restricted_sync_output" == *"- opencode config"* ]]  ← 이 단언 줄(및 실패 메시지 짝) 삭제
```

- [ ] **Step 6: RED 확인**

Run: `zsh -n scripts/check.zsh && ./scripts/check.zsh 2>&1 | tail -20`
Expected: 문법 통과 후 실행 FAIL — `unexpected harnesses: claude,codex,opencode` (기대값은 뒤집혔는데 코드는 아직 opencode를 서빙하므로). 커밋하지 않는다.

---

### Task 2: lib.zsh에서 opencode 제거 (13개 사이트)

**Files:**
- Modify: `config/ai-litellm/lib.zsh` (아래 앵커 기준 13곳)

**Interfaces:**
- Consumes: 없음 (독립 삭제)
- Produces: opencode 무언급 lib.zsh — `grep -ci opencode` == 0. Task 4가 이 삭제로 밀린 라인을 재앵커한다.

- [ ] **Step 1: descriptor 검증기 node case 삭제 (L~820)**

앵커 `case "opencode-cli":` (node 블록 내부). 해당 `case`부터 `break;`까지 8줄 삭제:

```js
  case "opencode-cli":
    for (const key of ["home", "config", "configDir"]) requireString(paths, key, "paths");
    requireString(provider, "name", "provider");
    requireString(provider, "baseUrl", "provider");
    requireString(auth, "env", "provider.auth");
    requireString(models, "default", "models");
    requireString(adapterConfig, "providerNpm", "adapterConfig");
    break;
```

- [ ] **Step 2: 렌더 함수 삭제 (L1319-1385)**

`ai_litellm_render_opencode_config() {` 부터 짝이 되는 컬럼-0 `}` 까지 함수 전체 삭제 (내부에 ruby heredoc과 `https://opencode.ai/config.json` 문자열 포함 — 통째로).

- [ ] **Step 3: 런치 함수 삭제 (L1387-1456)**

`ai_litellm_launch_opencode() {` 부터 `ai_litellm_harness_exec_env "$harness" "${env_assignments[@]}" -- "$command" "${opencode_args[@]}"` 다음의 컬럼-0 `}` 까지 전체 삭제.

- [ ] **Step 4: 런치 디스패치 case 삭제 (L~1478)**

`ai_litellm_launch()` 내부 `case "$adapter" in`에서:

```zsh
    opencode-cli)
      ai_litellm_launch_opencode "$harness" "$@"
      ;;
```

3줄(케이스 브랜치) 삭제. `claude-code`/`codex-cli`/`*)` 브랜치는 유지.

- [ ] **Step 5: 닥터 헬퍼 함수 삭제 (L2723-2730)**

`ai_litellm_doctor_opencode_config_base_url() {` 부터 짝 `}` 까지 8줄 삭제.

- [ ] **Step 6: limit-sync 닥터의 opencode 검사 서브블록 삭제 (L2762-2786)**

`ai_litellm_doctor_limit_sync()` 내부, 앵커 `local opencode_config provider_name` 줄부터 시작해 `stale OpenCode config context` 경고를 담은 `if [[ -n "$mismatch" ]]` 블록을 닫는 `fi`, 그리고 그 바깥 `if [[ -n "$opencode_config" && -f "$opencode_config" ]]`를 닫는 `fi`까지 삭제. (codex catalog 검사 부분은 유지.)

- [ ] **Step 7: sync의 opencode 생성 블록 삭제 (L3197-3203)**

```zsh
  if ai_litellm_harness_descriptor opencode >/dev/null 2>&1; then
    echo "- opencode config"
    if (( ! dry_run )); then
      ai_litellm_render_opencode_config opencode || failed=1
    fi
  fi
```

블록 전체 삭제.

- [ ] **Step 8: 닥터 체크 2줄 삭제 (L3362, L3383)**

```zsh
  ai_litellm_doctor_check "opencode-litellm command syntax" zsh -n "$AI_LITELLM_BIN_DIR/opencode-litellm" || failed=1
  ai_litellm_doctor_check "OpenCode generated config follows ai-litellm base URL" ai_litellm_doctor_opencode_config_base_url || failed=1
```

각각 해당 줄 삭제.

- [ ] **Step 9: context matrix ruby adapter case 삭제 (L4374-4379)**

ruby 블록 내 `when "opencode-cli"` 부터 다음 `else` 직전까지:

```ruby
  when "opencode-cli"
    default = descriptor.dig("models", "default")
    add_row(rows, harness, "default(#{default})", default, descriptor, registry) if default
    small = descriptor.dig("models", "small")
    add_row(rows, harness, "small(#{small})", small, descriptor, registry) if small
```

5줄 삭제 (`else` 폴백은 유지).

- [ ] **Step 10: reasoning adapter 테이블 엔트리 삭제 (L4485-4501)**

node 테이블에서 `"opencode-cli": {` 부터 그 객체를 닫는 `}` 까지 삭제. **직전 엔트리(`"codex-cli": {...}`)의 뒤따르는 콤마를 함께 정리**해 JS 객체 리터럴이 유효하게 유지되는지 확인.

- [ ] **Step 11: context probe surface case 축소 (L5372)**

```
old: codex-litellm|claude-litellm|opencode-litellm)
new: codex-litellm|claude-litellm)
```

- [ ] **Step 12: output-cap 경고 함수 + 호출 삭제 (L5734-5751, L5892)**

`ai_litellm_context_warn_opencode_output_cap() {` 부터 짝 `}` 까지 전체 삭제, 그리고 호출부 한 줄 `ai_litellm_context_warn_opencode_output_cap` (L5892) 삭제.

- [ ] **Step 13: usage 텍스트 정리 (L6262)**

```
old:   Codex low|medium|high|xhigh   OpenCode auto|none|minimal|low|medium|high|max
new:   Codex low|medium|high|xhigh
```

- [ ] **Step 14: 잔존 검증**

Run: `zsh -n config/ai-litellm/lib.zsh && grep -ci opencode config/ai-litellm/lib.zsh`
Expected: 문법 통과, grep 카운트 `0`

---

### Task 3: 파일 삭제 + schema + 인스톨러 legacy cleanup

**Files:**
- Delete: `bin/opencode-litellm`, `config/ai-litellm/harnesses/opencode.json`
- Modify: `config/ai-litellm/harnesses/schema.json:28`, `scripts/install.zsh:23,297,307,329,340,409` + goose 블록 뒤
- Verify only: `scripts/uninstall.zsh` (opencode legacy 항목은 과거 설치본 제거용으로 **유지**)

**Interfaces:**
- Produces: `remove_retired_opencode_support` (install.zsh 내 함수, 정의 직후 1회 호출) — Task 7이 이 함수의 실효과를 이 머신에서 검증한다.

- [ ] **Step 1: 파일 삭제**

```bash
git rm bin/opencode-litellm config/ai-litellm/harnesses/opencode.json
```

- [ ] **Step 2: schema adapter enum에서 opencode-cli 제거**

`config/ai-litellm/harnesses/schema.json` L28 부근:

```
old:         "codex-cli",
             "opencode-cli"
new:         "codex-cli"
```

Run: `jq . config/ai-litellm/harnesses/schema.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 3: install.zsh 참조 제거 (5곳)**

- L23: 헤더 주석의 `~/.local/bin/opencode-litellm` 줄 삭제
- L297: require_file 목록에서 `"$repo_root/config/ai-litellm/harnesses/opencode.json" \` 줄 삭제
- L307·L409: 두 shim 루프에서 `opencode-litellm` 토큰 제거 →
  `for script in ai-litellm claude-litellm codex-litellm openrouter-key-status litellm-master-key-status fabric; do`
- L329·L340: 두 디렉토리 목록에서 `"$prefix/state/opencode-litellm"` 항목 삭제 (직전 항목의 `; do` / 세미콜론 구조 유지 주의)

- [ ] **Step 4: legacy cleanup 함수 추가**

`remove_retired_goose_support` 정의·호출 바로 아래에 추가:

```zsh
remove_retired_opencode_support() {
  run rm -f "$bin_dir/opencode-litellm"
  for backup in "$bin_dir/opencode-litellm".bak.*(N); do
    run rm -f "$backup"
  done
  run rm -f "$prefix/bin/opencode-litellm"
  run rm -f "$prefix/config/ai-litellm/harnesses/opencode.json"
  run rm -rf "$prefix/state/opencode-litellm"
}
remove_retired_opencode_support
```

- [ ] **Step 5: 검증**

Run: `zsh -n scripts/install.zsh && grep -n -i opencode scripts/install.zsh`
Expected: 문법 통과. grep 출력의 **모든** 줄이 `remove_retired_opencode_support` 함수 정의(및 그 직후 1회 호출) 블록 안에 있어야 한다 — 블록 밖 잔존은 0줄.

Run: `grep -n -i opencode scripts/uninstall.zsh`
Expected: L30·L39(제거 대상 안내 주석), L159(legacy shim 목록), L178(`~/.config/opencode-litellm`) — **전부 유지** (과거 설치본 정리용)

---

### Task 4: budget 차분테스트 라인 재앵커

**Files:**
- Modify: `scripts/verify_budget_consistency.py:49-55` (`RUBY_MAT_RANGE`, `RUBY_RES_RANGE`)

**Interfaces:**
- Consumes: Task 2가 lib.zsh에서 삭제한 줄 수만큼 밀린 라인 위치.
- Produces: green `verify_budget_consistency.py` — check.zsh(L27/L35)가 이를 실행한다.

- [ ] **Step 1: 현재 실패 확인 (loud-fail 설계 검증 겸)**

Run: `python3 scripts/verify_budget_consistency.py; echo "exit=$?"`
Expected: `SLICE-GUARD FAIL: lib.zsh slice RUBY_MAT ...` 류 메시지 + `exit=1`. (`NODE_RANGE`(457,523)·`RUBY_CAT_RANGE`(551,589)는 삭제 지점(L820~)보다 위라 영향 없음 — 가드가 조용히 통과하면 그대로 두 상수는 유지.)

- [ ] **Step 2: 새 라인 범위 계산**

두 슬라이스의 시작/끝을 앵커로 재탐색한다:

```bash
grep -n "positive_int" config/ai-litellm/lib.zsh | sed -n '2,4p'   # ruby matrix/doctor 블록의 시작 후보
grep -n "output_budget" config/ai-litellm/lib.zsh
```

기존 범위 폭(RUBY_MAT 62줄, RUBY_RES 66줄)과 주석(`# positive_int + output_budget`)을 기준으로 새 시작·끝 라인을 정해 `RUBY_MAT_RANGE`/`RUBY_RES_RANGE` 상수를 갱신한다. (Task 2 삭제 총량만큼 두 값 모두 위로 이동한다.)

- [ ] **Step 3: PASS 확인**

Run: `python3 scripts/verify_budget_consistency.py; echo "exit=$?"`
Expected: 슬라이스 가드 통과 + 27행 매트릭스 5구현 일치 + `exit=0`

---

### Task 5: 전체 check GREEN + 단일 커밋

**Files:**
- 없음 (검증 + 커밋만)

**Interfaces:**
- Consumes: Task 1-4의 모든 변경.

- [ ] **Step 1: 전체 check 실행**

Run: `./scripts/check.zsh 2>&1 | tail -30; echo "exit=$?"`
Expected: 전 단언 통과, `exit=0`. (mktemp HOME에 진짜 설치를 수행하므로 수 분 소요. 실패 시 실패 지점의 단언 메시지를 읽고 해당 Task로 되돌아간다 — 새 단언을 임의로 약화하지 않는다.)

- [ ] **Step 2: 커밋**

```bash
git add -A
git commit -m "feat!: retire opencode harness support

Remove the opencode adapter (launcher, config renderer, doctor checks,
context/reasoning surfaces), its shim, descriptor and schema entry.
Existing installs are pruned at install time via
remove_retired_opencode_support (goose-retirement pattern; state including
session sqlite is deleted as approved). Budget differential slices
re-anchored; check.zsh now asserts the claude+codex-only surface.

Spec: docs/superpowers/specs/2026-07-04-ai-litellm-refactor-design.md §4

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 문서 스윕 + 커밋

**Files:**
- Modify: `README.md`(6곳), `docs/AI_AGENT_LITELLM_ARCHITECTURE.md`(30곳), `docs/DESIGN_RATIONALE.md`(8곳), `docs/APPLYING_MODELS_TO_HARNESSES.md`(4곳)

**Interfaces:**
- Consumes: 코드 상태 (Task 5 커밋 완료본).

- [ ] **Step 1: README.md**

- L10 `opencode-litellm` 소개 불릿 삭제
- 설치 전제 문단(L92-93)에서 opencode 문장 삭제, 설치 산출물 목록의 `~/.local/bin/opencode-litellm`(L118) 삭제
- Token Budget Policy 절의 OpenCode 불릿(L309-310) 삭제
- 나머지는 `grep -n -i opencode README.md`로 확인 후 현재-상태 서술만 제거

- [ ] **Step 2: ARCHITECTURE**

- 결론의 실행 경로 목록에서 `opencode-litellm` 줄 삭제(6→5개) + mermaid의 `N`/`O` 노드·엣지 삭제
- Source Of Truth 표에서 OpenCode 3행(descriptor, generated config, shim) 삭제
- Harness 관리 절: OpenCode 문단, `harness info opencode`·`harness launch opencode …` 예시, OpenCode sqlite 팁 블록 삭제
- Reasoning 절: `harness reasoning set opencode high`/`unset opencode` 예시 줄과 OpenCode 서술 문장 삭제
- 토큰 한도 절: OpenCode 예약 문단·파생 표의 OpenCode 행 2개 삭제
- 로컬 모델 테스트 예시의 `opencode-litellm …` 줄 삭제, 모델 추가 절차 4단계의 "OpenCode config" 언급 제거
- **결정 로그(06-07/08/11)의 OpenCode 언급은 보존**, 2026-06-11 로그의 goose 항목 아래 형식을 따라 새 항목 추가:
  `- opencode: 2026-07-04 지원 종료. opencode는 자체 API/로컬 모델 연결이 일급 기능이라 래핑의 부가가치가 없다. descriptor·shim·어댑터는 제거했고, install/uninstall은 기존 설치본의 shim·descriptor·state만 legacy cleanup으로 삭제한다.`

- [ ] **Step 3: DESIGN_RATIONALE**

- §6 서문 "네 harness가 네 가지 다른 격리 전략" → 현역 2(claude/codex) + retired 2(goose/opencode) 반영해 재서술
- §6 opencode 불릿 → goose 형식의 한 줄: `- **opencode — retired 2026-07-04.** [기록] OPENCODE_CONFIG 파일 포인터 방식은 비파괴적이었으나, opencode 자체가 모델 연결을 일급 지원해 래핑의 존재 이유가 없다. legacy cleanup만 유지.`
- 나머지 6곳은 `grep -n -i opencode`로 찾아 현재형 서술만 수정 (반론·역사 인용은 유지)

- [ ] **Step 4: APPLYING_MODELS_TO_HARNESSES**

4곳 grep 후 OpenCode 레시피/워크드 예시 절 삭제 또는 "retired 2026-07-04" 표기 (절 구조가 Claude/Codex/OpenCode 병렬이면 OpenCode 절 전체 삭제).

- [ ] **Step 5: 잔존 검증 + 커밋**

Run: `grep -rn -i opencode README.md docs/*.md | grep -v -e "결정 로그" -e "retired" -e "지원 종료" -e "superpowers/"`
Expected: 출력 0줄 (결정 로그·은퇴 표기·과거 스펙/플랜 문서만 잔존 허용)

```bash
git add README.md docs/AI_AGENT_LITELLM_ARCHITECTURE.md docs/DESIGN_RATIONALE.md docs/APPLYING_MODELS_TO_HARNESSES.md
git commit -m "docs: retire opencode across guides (decision logs preserved)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 이 머신의 설치본 정리 + 최종 게이트

**Files:**
- 없음 (운영 검증)

**Interfaces:**
- Consumes: Task 3의 `remove_retired_opencode_support`.

- [ ] **Step 1: dry-run으로 계획 확인**

Run: `./scripts/install.zsh --dry-run 2>&1 | grep -i -e opencode -e "rm "`
Expected: `rm -f .../opencode-litellm`, `rm -rf .../state/opencode-litellm` 류의 legacy cleanup 액션이 계획에 표시됨

- [ ] **Step 2: 실제 설치 (legacy cleanup 실행)**

Run: `./scripts/install.zsh 2>&1 | tail -15`
Expected: 정상 완료. 이후 확인:

```bash
command -v opencode-litellm || echo "shim gone"
ls ~/.local/share/ai-litellm-fabric/state/opencode-litellm 2>&1
ls ~/.local/share/ai-litellm-fabric/config/ai-litellm/harnesses/
```

Expected: `shim gone` / `No such file or directory` / `claude.json codex.json schema.json`만

- [ ] **Step 3: 설치본 스모크**

Run: `ai-litellm harness list && ai-litellm doctor --proxy 2>&1 | tail -5`
Expected: harness 목록에 claude·codex만, proxy doctor 통과 (opencode 관련 체크 항목 자체가 없음)

- [ ] **Step 4: 수용 기준 대조 (스펙 §4)**

- check.zsh green ✓ (Task 5)
- `ai-litellm harness list`에 claude·codex만 ✓ (Step 3)
- 재설치 시 기존 opencode 설치물 정리 ✓ (Step 2)
- native 디렉토리 무접촉 ✓ (check 내장 단언)

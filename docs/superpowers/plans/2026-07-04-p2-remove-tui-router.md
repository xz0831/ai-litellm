# P2: TUI(fabric)+router 제거, `ai-litellm status` 신설 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fabric TUI(fabric_dash)·router_core·전용 venv·CI 잡을 완전히 제거하고, 그 관측 역할을 한 방 요약 명령 `ai-litellm status`(+`--json`)로 대체한다. P1 최종 리뷰의 carry-over 4건을 함께 처리한다.

**Architecture:** P1과 같은 삭제-리팩터 패턴 — check.zsh 기대값을 먼저 뒤집고(RED: 신설 status 단언), 파일 삭제 → lib.zsh 제거 → status 구현 → 인스톨러/CI 정리 → budget 재앵커 → 전체 check GREEN 단일 커밋 → 문서 커밋 → 머신 반영. `--json` read 표면은 유지(router `--json`만 그룹과 함께 소멸). status는 기존 read 함수/emitter의 **합성만** 한다(상태 재파생 금지).

**Tech Stack:** zsh (lib.zsh, install/check), 임베디드 node, Python 삭제(fabric_dash/router_core), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-07-04-ai-litellm-refactor-design.md` §5 + P1 최종리뷰 carry-over (원장 `.superpowers/sdd/p1-retire-opencode/progress.md`)

## Global Constraints

- 라인 번호는 커밋 `87d88f0` 기준 앵커다. 어긋나면 **인용된 앵커 텍스트로** 위치를 찾는다.
- native 디렉토리(`~/.claude`, `~/.codex`) 무접촉 — 기존 check 단언 유지.
- 문서의 **날짜 있는 결정 로그는 역사로 보존** (해당 subsystem 불릿의 goose/opencode식 in-place 은퇴 교체는 허용된 house style).
- `--json` read 표면(proxy/model/runtime/harness/reasoning/context/key)은 유지한다. router의 `--json`만 그룹과 함께 제거된다.
- goose/opencode legacy cleanup 유지.
- 커밋은 `scripts/check.zsh` green 상태에서만 만든다.
- **검증 명령은 pipefail-safe 관용구**(P1 carry-over): `./scripts/check.zsh > /tmp/p2-check.log 2>&1; rc=$?; tail -30 /tmp/p2-check.log; echo "exit=$rc"` — 파이프 뒤 `$?` 금지.
- 커밋 메시지 말미: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: check.zsh 기대값 뒤집기 (RED)

**Files:**
- Modify: `scripts/check.zsh:28-29`, `:65`, `:70`, `:77-86`, `:89-101`, `:695-701`

**Interfaces:**
- Produces: dash/router-free + status-존재를 단언하는 check.zsh. RED의 원천은 **신설 status 단언**(아직 미구현)이다.

- [ ] **Step 1: 브랜치 확인**

컨트롤러가 워크트리·브랜치(`refactor/p2-remove-tui-router`)를 준비한다. `git branch --show-current`로 확인만.

- [ ] **Step 2: router_core 컴파일/유닛테스트 훅 삭제 (L28-29)**

```zsh
python3 -m compileall -q "$repo_root/config/ai-litellm/router_core"
PYTHONPATH="$repo_root/config/ai-litellm" python3 -m unittest discover -s "$repo_root/config/ai-litellm/router_core/tests" -q
```

2줄 삭제.

- [ ] **Step 3: install 호출에서 SKIP_DASH_VENV 제거 (L65)**

```
old: AI_LITELLM_SKIP_DASH_VENV=1 LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-$$" HOME="$tmp_home" "$repo_root/scripts/install.zsh" >/dev/null
new: LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-$$" HOME="$tmp_home" "$repo_root/scripts/install.zsh" >/dev/null
```

- [ ] **Step 4: router_core 설치 산출물 단언 삭제 (L70)**

`test -f "$HOME/.local/share/ai-litellm-fabric/config/ai-litellm/router_core/__main__.py"` 1줄 삭제.

- [ ] **Step 5: fabric shim + dash venv 모듈 체크 블록 삭제 (L77-86)**

`[[ -x "$HOME/.local/bin/fabric" ]] || { echo "FAIL: fabric shim missing"; exit 1; }` 부터 `echo "note: skipping fabric_dash module check (dash venv/textual unavailable in check env)" >&2` 를 담은 if/else 블록 끝(`fi`)까지 삭제 (앵커: `tmp_venv=`, `fabric_dash --help`).

- [ ] **Step 6: router 표면 검사 블록 → status 검사로 교체 (L89-101)**

`"$HOME/.local/bin/ai-litellm" router schema --json >/dev/null` 부터 `grep -q "billing.confirmation_required" "$HOME/router-billable-refusal.json"` 까지(중간의 `router_refusal_rc` 처리 포함) 전체 삭제하고, 같은 자리에 다음을 넣는다:

```zsh
"$HOME/.local/bin/ai-litellm" status > "$HOME/status-text.out" 2>/dev/null
grep -q "harness model mappings:" "$HOME/status-text.out"
"$HOME/.local/bin/ai-litellm" status --json > "$HOME/status.json" 2>/dev/null
node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));for(const k of ["proxy","harnesses","runtimes","keys","models"]) if(!(k in o)){console.error("status --json missing key: "+k);process.exit(1)}' "$HOME/status.json"
echo "ok: status one-shot summary (text + json)"
```

- [ ] **Step 7: dash pytest 블록 삭제 (L695-701)**

`dash_venv_python=` 정의부터 `echo "note: skipping fabric_dash tests (textual/pytest not installed)" >&2` 를 담은 if/else 끝(`fi`)까지 삭제.

- [ ] **Step 8: RED 확인**

Run: `zsh -n scripts/check.zsh && { ./scripts/check.zsh > /tmp/p2-t1.log 2>&1; rc=$?; tail -8 /tmp/p2-t1.log; echo "exit=$rc"; }`
Expected: 문법 통과 후 실행 FAIL(`exit=1`) — 실패 지점은 신설 status 검사 영역(아직 `status`가 unknown command이므로 errexit 하에서 status 호출 줄 또는 직후 `grep -q "harness model mappings:"`에서 죽는다). 커밋하지 않는다.

---

### Task 2: 파일/디렉토리 삭제 + .gitignore 정리

**Files:**
- Delete: `config/ai-litellm/fabric_dash/`(전체), `config/ai-litellm/router_core/`(전체), `config/ai-litellm/conftest.py`, `bin/fabric`, `docs/FABRIC_DASHBOARD.md`
- Modify: `.gitignore` (1줄 삭제 — P1 carry-over)

**Interfaces:**
- Consumes: 없음. Produces: 이 삭제로 lib.zsh(T3)·install.zsh(T5)의 참조가 dangling이 됨 — 후속 태스크가 정리.

- [ ] **Step 1: git rm**

```bash
git rm -r config/ai-litellm/fabric_dash config/ai-litellm/router_core
git rm config/ai-litellm/conftest.py bin/fabric docs/FABRIC_DASHBOARD.md
```

- [ ] **Step 2: .gitignore에서 dead 패턴 삭제**

`opencode-dir/node_modules/` 줄 삭제 (P1에서 opencode 렌더러가 사라져 이 디렉토리를 만들 코드가 없음).

- [ ] **Step 3: 검증**

Run: `git status --short | head -30 && ls config/ai-litellm/`
Expected: D 항목들만 추가됨(+.gitignore M). `config/ai-litellm/`에 `fabric_dash`/`router_core`/`conftest.py` 부재, `harnesses/ lib.zsh settings.json context-observations.json` 등만 잔존. (`__pycache__`/`.pytest_cache` 잔재가 보이면 untracked이므로 `rm -rf`로 청소해도 됨 — git 추적 대상 아님.)

---

### Task 3: lib.zsh — dash/router 디스패치 + cmd_router + 고아 헬퍼 3개 제거

**Files:**
- Modify: `config/ai-litellm/lib.zsh:850-921`, `:965-988`, `:1280-1309`, `:5897-5905`, `:6019`, `:6021`, `:6049`, `:6053-6066`

**Interfaces:**
- Consumes: T2의 파일 삭제 (router_core 부재 → cmd_router가 dangling).
- Produces: dash/router/고아-free lib.zsh. **T4가 `ai_litellm_cmd_router`가 있던 자리(~L5897)에 `ai_litellm_cmd_status`를 넣는다** — 이 위치는 budget 슬라이스(RUBY_RES 끝 5490)보다 아래라 추가 시프트가 없다.

- [ ] **Step 1: 고아 헬퍼 3개 삭제 (P1 carry-over)**

각각 `함수명() {` 부터 짝이 되는 컬럼-0 `}` 까지 전체 삭제. 셋 다 repo 전체에서 호출자 0임이 P1 최종 리뷰에서 검증됨:

- `ai_litellm_harness_env_assignments() {` (L850-921 — L905의 }는 내장 node -e JS 문자열 내부 for-루프의 닫는 중괄호이므로 함수 끝이 아님; 진짜 컬럼-0 끝은 L921)
- `ai_litellm_harness_secret_value() {` (L965-988)
- `ai_litellm_harness_parse_model_selection() {` (L1280-1309 — L1311은 다음 함수 ai_litellm_launch의 시작)

삭제 후: `grep -c "ai_litellm_harness_env_assignments\|ai_litellm_harness_secret_value\|ai_litellm_harness_parse_model_selection" config/ai-litellm/lib.zsh` == 0

- [ ] **Step 2: ai_litellm_cmd_router 함수 삭제 (L5897-5905)**

```zsh
ai_litellm_cmd_router() {
  command -v python3 >/dev/null 2>&1 || {
    echo "ai-litellm router requires python3" >&2
    return 1
  }
  AI_LITELLM_ROUTER_BINARY="$AI_LITELLM_BIN_DIR/ai-litellm" \
  PYTHONPATH="$AI_LITELLM_CONFIG_HOME/ai-litellm${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m router_core "$@"
}
```

함수 전체 삭제. (뒤따르는 `ai_litellm_codex_facade_json`은 P4 전까지 유지 — 건드리지 않는다.)

- [ ] **Step 3: 디스패치에서 router/dash 제거 (L6049, L6053-6066)**

- `    router)       ai_litellm_cmd_router "$@" ;;` 1줄 삭제
- `    dash)` case 브랜치 전체(NOTE 주석 3줄 + venv 체크 + PYTHONPATH 실행 + `;;`) 삭제 — 앵커: `local fabric_py="$AI_LITELLM_STATE_HOME/dash-venv/bin/python"`

- [ ] **Step 4: usage 텍스트 정리 (L6019, L6021)**

```
삭제:   Router:        ai-litellm router schema|snapshot|plan|explain|execute --json [intent opts]
삭제:   Dash:          ai-litellm dash          Launch the fabric control-plane TUI (or run: fabric)
```

(`Capabilities:` 줄은 P4까지 유지.)

- [ ] **Step 5: 검증**

Run: `zsh -n config/ai-litellm/lib.zsh && grep -c "fabric_dash\|router_core\|dash-venv\|cmd_router" config/ai-litellm/lib.zsh`
Expected: 문법 통과, grep 카운트 `0`

---

### Task 4: `ai-litellm status` 구현

**Files:**
- Modify: `config/ai-litellm/lib.zsh` — T3 Step 2로 비워진 자리(~L5897, `ai_litellm_codex_facade_json() {` 바로 위)에 새 함수 추가 + 디스패치 2곳

**Interfaces:**
- Consumes: 기존 read 함수들(전부 lib.zsh에 실존, 라인은 87d88f0 기준): `ai_litellm_status`(:2076 텍스트)·`ai_litellm_status_json`(:2115)·`ai_litellm_harnesses_json`(:1264)·`ai_litellm_runtime_status`(:1641)·`ai_litellm_runtime_status_json`(:1704)·`ai_litellm_key_status`(:2374)·`ai_litellm_key_status_json`(:2399)·`ai_litellm_list_json`(:2163)·`ai_litellm_capabilities`(:3116)·`ai_litellm_harness_json`·`ai_litellm_cmd_harness`(alias get 경로).
- Produces: `ai_litellm_cmd_status [--json]` — T1의 check 단언(`harness model mappings:` 텍스트 마커, `--json`의 5키 `proxy/harnesses/runtimes/keys/models`)과 T7 문서·T8 스모크가 이 계약에 의존.

- [ ] **Step 1: 함수 추가**

`ai_litellm_codex_facade_json() {` 바로 위에 삽입:

```zsh
# One-shot control-plane summary. Composes EXISTING read surfaces only — no
# state re-derivation (same contract as --json). Degraded sections render as
# empty/not-running instead of aborting, so the command always exits 0
# (observability command; mirrors the empty-output honesty of the json API).
ai_litellm_cmd_status() {
  if [[ "${1:-}" == "--json" ]]; then
    node -e '
const parse = (s) => { try { return JSON.parse(s); } catch { return null; } };
const [proxy, harnesses, runtimes, keys, models] = process.argv.slice(1).map(parse);
process.stdout.write(JSON.stringify({ proxy, harnesses, runtimes, keys, models }) + "\n");
' "$(ai_litellm_status_json)" "$(ai_litellm_harnesses_json)" "$(ai_litellm_runtime_status_json)" "$(ai_litellm_key_status_json)" "$(ai_litellm_list_json)"
    return 0
  fi
  ai_litellm_status
  echo
  echo "harness model mappings:"
  ai_litellm_cmd_harness alias get claude 2>/dev/null | sed 's/^/  /'
  echo "  codex default: $(ai_litellm_harness_json codex models.default 2>/dev/null || printf 'unknown')"
  echo
  ai_litellm_runtime_status
  echo
  ai_litellm_key_status
  echo
  ai_litellm_capabilities
  return 0
}
```

구현 전 확인 1개: `ai_litellm_cmd_harness`의 alias 브랜치 실제 호출 형태(`alias get claude`)를 dispatch 코드에서 읽어 위 호출이 맞는지 확인하고, 어긋나면 **그 브랜치가 실제로 받는 인자 형태로 호출을 맞춘다**(출력 내용 자체는 기존 명령 출력 그대로 — 재구현 금지).

- [ ] **Step 2: 디스패치 재배정**

(a) canonical 그룹 첫 항목으로 추가 — `    proxy)        ai_litellm_cmd_proxy "$@" ;;` 바로 위:

```zsh
    status)       ai_litellm_cmd_status "$@" ;;
```

(b) deprecated flat alias 줄 삭제 (L6072였던 것, 앵커 텍스트로 찾기):

```zsh
    status|--status)             ai_litellm_deprecated status "proxy status"; ai_litellm_status ;;
```

(a)가 case문에서 (b)보다 먼저 매치되므로 (b)는 반드시 제거 — 남기면 dead code.

- [ ] **Step 3: usage 텍스트에 status 추가**

usage의 그룹 목록 첫 줄(Proxy 줄 위)에:

```
  Status:        ai-litellm status [--json]  Proxy/harness/runtime/key/capability one-shot summary
```

- [ ] **Step 4: 검증**

Run: `zsh -n config/ai-litellm/lib.zsh`
Expected: 통과. **checkout에서 직접 실행 금지**(assert_rendered_path 가드 — 렌더된 설치본 전용). 실동작 검증은 T6의 전체 check(throwaway 설치)와 T8(실머신)이 담당.

---

### Task 5: install.zsh + ci.yml 정리

**Files:**
- Modify: `scripts/install.zsh:305`, `:374-379`, `:381-385`, `:387-405`, 두 번째 shim 루프(~L407), goose/opencode 정리 함수들 뒤
- Modify: `.github/workflows/ci.yml` — `dash-tests:` 잡 전체 삭제
- Verify only: `scripts/uninstall.zsh` (L159 legacy shim 목록의 `fabric` 유지 — 과거 설치본 정리용)

**Interfaces:**
- Produces: `remove_retired_dash_router_support` (install-시점 legacy cleanup) — T8이 실효과 검증.

- [ ] **Step 1: shim 루프 2곳에서 fabric 제거**

L305와 두 번째 루프(~L407, 앵커 `for script in ai-litellm claude-litellm codex-litellm openrouter-key-status litellm-master-key-status fabric`):

```
old: for script in ai-litellm claude-litellm codex-litellm openrouter-key-status litellm-master-key-status fabric; do
new: for script in ai-litellm claude-litellm codex-litellm openrouter-key-status litellm-master-key-status; do
```

- [ ] **Step 2: fabric_dash/router_core 설치 루프 삭제 (L374-385)**

`for pyfile in "$repo_root"/config/ai-litellm/fabric_dash/**/*.py(N); do` 루프(+ 뒤따르는 `install_rendered ... app.tcss` 줄)와 `for pyfile in "$repo_root"/config/ai-litellm/router_core/**/*.py(N); do` 루프 전체 삭제.

- [ ] **Step 3: ensure_dash_venv 함수+호출 삭제 (L387-405)**

`ensure_dash_venv() {` 부터 짝 `}` 그리고 그 아래 호출줄 `ensure_dash_venv` 까지 삭제. 삭제 후 `grep -c "DASH_VENV\|dash-venv" scripts/install.zsh` 는 Step 4의 cleanup 함수 내부 언급만 남아야 함.

- [ ] **Step 4: legacy cleanup 함수 추가**

`remove_retired_opencode_support` 정의·호출 바로 아래에:

```zsh
remove_retired_dash_router_support() {
  run rm -f "$bin_dir/fabric"
  for backup in "$bin_dir/fabric".bak.*(N); do
    run rm -f "$backup"
  done
  run rm -f "$prefix/bin/fabric"
  run rm -rf "$prefix/config/ai-litellm/fabric_dash"
  run rm -rf "$prefix/config/ai-litellm/router_core"
  run rm -rf "$prefix/state/dash-venv"
}
remove_retired_dash_router_support
```

- [ ] **Step 5: ci.yml에서 dash-tests 잡 삭제**

`  dash-tests:` 키부터 그 잡의 마지막 스텝(`python -m pytest fabric_dash/tests/ -q`) 끝까지 — 파일 끝 또는 다음 최상위 잡 키 직전까지 삭제. `check`/`token-clamp`/`tool-fidelity` 잡은 유지.

- [ ] **Step 6: 검증**

Run: `zsh -n scripts/install.zsh && grep -n -i "fabric_dash\|router_core\|dash" scripts/install.zsh; python3 -c "import yaml,sys; d=yaml.safe_load(open('.github/workflows/ci.yml')); ks=list(d['jobs']); print(ks); sys.exit(0 if 'dash-tests' not in ks else 1)" 2>/dev/null || node -e "const s=require('fs').readFileSync('.github/workflows/ci.yml','utf8'); if(/^\s{2}dash-tests:/m.test(s)) {console.error('dash-tests still present'); process.exit(1)} console.log('ci ok')"`
Expected: install.zsh 문법 통과, grep 결과 전부 `remove_retired_dash_router_support` 블록 내부, ci 검사 통과(`dash-tests` 부재; PyYAML 없으면 node 폴백이 판정).

---

### Task 6: budget 재앵커 + 전체 check GREEN + 단일 커밋

**Files:**
- Modify: `scripts/verify_budget_consistency.py:49-55` (`RUBY_MAT_RANGE`/`RUBY_RES_RANGE` — T3의 고아 삭제 ~112줄+공백이 두 범위를 위로 밀었다; NODE/RUBY_CAT(457-589)은 삭제 지점(≥850)보다 위라 불변)

**Interfaces:**
- Consumes: T1-T5 전체.

- [ ] **Step 1: 슬라이스 RED 확인 후 재앵커**

Run: `python3 scripts/verify_budget_consistency.py > /tmp/p2-budget.log 2>&1; rc=$?; tail -5 /tmp/p2-budget.log; echo "exit=$rc"`
Expected: `SLICE-GUARD FAIL` + exit=1. P1 Task 4와 같은 방법으로 재계산: HEAD의 옛 슬라이스 첫/끝 줄(`git show HEAD:config/ai-litellm/lib.zsh | sed -n '4562p;4623p;5425p;5490p'`)을 현재 파일에서 재탐색(`grep -n "def positive_int"` — 마지막 두 발생이 두 슬라이스), 폭(61/65) 보존 확인 후 상수 갱신.

- [ ] **Step 2: budget GREEN**

Run: `python3 scripts/verify_budget_consistency.py > /tmp/p2-budget2.log 2>&1; rc=$?; tail -3 /tmp/p2-budget2.log; echo "exit=$rc"`
Expected: `OK: all five ... agree` + exit=0

- [ ] **Step 3: 전체 check GREEN**

Run: `./scripts/check.zsh > /tmp/p2-check.log 2>&1; rc=$?; tail -20 /tmp/p2-check.log; echo "exit=$rc"`
Expected: `ok: status one-shot summary (text + json)` 포함, 마지막 `ok`, exit=0. 실패 시 실패 단언을 읽고 해당 태스크로 복귀 — 단언 약화 금지, 커밋 금지.

- [ ] **Step 4: 단일 커밋**

```bash
git add -A
git commit -m "feat!: remove fabric TUI and router surface; add 'ai-litellm status'

Delete fabric_dash (15 modules + tests + tcss), router_core (+tests),
conftest, the fabric shim, the dash venv provisioning and the dash-tests CI
job. The observability role moves to 'ai-litellm status' (+--json), a pure
composition of the existing read surfaces. Existing installs are pruned at
install time via remove_retired_dash_router_support. Also removes the three
generic lib.zsh helpers orphaned by the opencode retirement (P1 final-review
carry-over) and the dead opencode-dir/node_modules/ gitignore pattern;
budget differential slices re-anchored.

Spec: docs/superpowers/specs/2026-07-04-ai-litellm-refactor-design.md §5

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: 문서 스윕 + 커밋

**Files:**
- Modify: `README.md`, `docs/AI_AGENT_LITELLM_ARCHITECTURE.md`, `docs/DESIGN_RATIONALE.md` (FABRIC_DASHBOARD.md는 T2에서 이미 삭제)

**Interfaces:**
- Consumes: T6 커밋 완료본.

- [ ] **Step 1: README.md**

- `## Dashboard` 섹션 전체 삭제 (fabric/dash-venv/FABRIC_DASHBOARD.md 링크 포함)
- 오케스트레이션 router 문단(anchor: "For orchestration, `ai-litellm router`" ~ "human-readable reason strings." + 코드펜스) 삭제
- `## Machine-readable output` 섹션: "the `fabric` dashboard" 표현 2곳을 스크립팅 계약 서술로 재작성 (표면 자체는 유지됨을 명시), `route list --json` 줄은 유지(P4에서 처리)
- First Run 절의 `ai-litellm status` 미언급 — 요약 명령 1줄 소개 추가: `ai-litellm status` (한 방 요약; `--json` 지원)
- 잔존 확인: `grep -n -i "fabric\b\|dash\|router" README.md` 결과에서 현재형 TUI/router 서술이 없는지 (repo명 `ai-litellm-fabric`·`AI_LITELLM_FABRIC_HOME`류 패키지 경로 언급은 P5 전까지 유지 — 건드리지 않는다)

- [ ] **Step 2: ARCHITECTURE**

- 결론(L28-30 부근)과 명령어 체계 블록에서 `router`·`dash` 줄 삭제, `ai-litellm status` 줄 추가
- `### fabric 대시보드` 절(L145-148) 삭제, `--json` read surface 절의 "이 표면이 fabric 대시보드가 소비하는 계약" 프레이밍을 "스크립팅/자동화용 계약"으로 재작성
- `## Router / 오케스트레이션` 절 전체 삭제
- 2026-06-20 결정 로그(대시보드/`--json`/도구 정비)는 **역사로 보존**, 그 로그의 대시보드 항목 뒤에 은퇴 문구를 덧붙이는 대신 **새 dated 항목 추가**: `- fabric 대시보드·router 표면: 2026-07-04 지원 종료. 관측 역할은 'ai-litellm status'(기존 read 표면 합성)로 대체; fabric_dash/router_core/전용 venv/dash-tests CI 잡 제거. --json read 계약은 스크립팅용으로 유지.` (기존 goose/opencode 항목과 같은 로그 리스트에)
- '출력 능력치 또는 policy ceiling' 불릿 재정초 (carry-over): OpenCode 예시가 빠져 공허해진 문장에 Codex-catalog 예시를 붙인다 — `예: codex 생성 카탈로그의 context_window는 capability가 아니라 safe input budget이며, capability-파생 값은 confidence 라벨과 함께 본다.` 취지로 주변 문체에 맞게.
- 운영 체크리스트에서 `ai-litellm capabilities` 앞에 `ai-litellm status` 추가(capabilities 제거는 P4)

- [ ] **Step 3: DESIGN_RATIONALE**

- §6a(fabric 대시보드) 절 전체를 goose식 retired 블록으로 교체: `## 6a. fabric 대시보드 — retired 2026-07-04` + 2-3문장(원래 명제 "TUI는 CLI의 관측" 인용, 카탈로그 관리라는 원목적을 달성하지 못했고 관측 역할은 status로 이관, 상세 설계는 git 히스토리(87d88f0 이전)에 보존) — 하위 결정 문단·반론 전체 삭제
- §8 표의 "대시보드 회귀" 행 삭제, "예약 수치 ... 5중 구현 lockstep" 행은 유지
- 서문·기타 현재형 dash/router 언급 grep 후 정리 (dated 인용 보존)

- [ ] **Step 4: 잔존 검증 + 커밋**

Run: `grep -rn -i "fabric_dash\|router_core\|dash-venv\|ai-litellm dash\|ai-litellm router" README.md docs/AI_AGENT_LITELLM_ARCHITECTURE.md docs/DESIGN_RATIONALE.md docs/APPLYING_MODELS_TO_HARNESSES.md`
Expected: 결과 전부 dated 결정 로그/은퇴 표기 문맥 (하나씩 판정해 보고서에 기록)

```bash
git add README.md docs/AI_AGENT_LITELLM_ARCHITECTURE.md docs/DESIGN_RATIONALE.md
git commit -m "docs: retire fabric dashboard and router surface across guides

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: 이 머신 설치 반영 + 최종 게이트

**Files:** 없음 (운영 검증)

**Interfaces:**
- Consumes: T5의 `remove_retired_dash_router_support`, T4의 status.

- [ ] **Step 1: dry-run**

Run: `./scripts/install.zsh --dry-run 2>&1 | grep -i -e fabric -e dash -e router -e "rm "`
Expected: `rm -f .../bin/fabric`, `rm -rf .../config/ai-litellm/fabric_dash`, `rm -rf .../config/ai-litellm/router_core`, `rm -rf .../state/dash-venv` 계획 표시

- [ ] **Step 2: 실제 설치 + 확인**

Run: `./scripts/install.zsh 2>&1 | tail -8`
이후:

```bash
[[ -x "$HOME/.local/bin/fabric" ]] || echo "fabric shim gone"
[[ -d "$HOME/.local/share/ai-litellm-fabric/state/dash-venv" ]] || echo "dash-venv gone"
[[ -d "$HOME/.local/share/ai-litellm-fabric/config/ai-litellm/fabric_dash" || -d "$HOME/.local/share/ai-litellm-fabric/config/ai-litellm/router_core" ]] || echo "packages gone"
ls "$HOME/.local/share/ai-litellm-fabric/config/ai-litellm/"
```

Expected: `fabric shim gone` / `dash-venv gone` / `packages gone` + 마지막 ls에 `harnesses lib.zsh settings.json context-observations.json`류만

- [ ] **Step 3: status 스모크 (설치본)**

Run: `~/.local/bin/ai-litellm status | head -20 && ~/.local/bin/ai-litellm status --json | node -e 'const c=[];process.stdin.on("data",d=>c.push(d)).on("end",()=>{const o=JSON.parse(c.join(""));console.log("keys:",Object.keys(o).join(","))})'`
Expected: 텍스트에 proxy 상태 + `harness model mappings:` 블록, JSON keys: `proxy,harnesses,runtimes,keys,models`

- [ ] **Step 4: 수용 기준 대조 (스펙 §5)**

- check.zsh green ✓ (T6)
- CI에서 dash-tests 잡 부재 ✓ (T5)
- `ai-litellm status`가 proxy·tier·key·runtime 요약 출력 ✓ (Step 3)
- `fabric`·`ai-litellm dash`·`ai-litellm router` 모두 부재 ✓ (Step 2 + T6 check)

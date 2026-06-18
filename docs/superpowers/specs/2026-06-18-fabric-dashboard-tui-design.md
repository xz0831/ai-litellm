# Design Spec — `fabric` 통합 관제 TUI 대시보드

Date: 2026-06-18
Status: Draft (브레인스토밍 합의안, 구현 계획 전)
Author: xz0831 + Claude (brainstorming session)

---

## 1. 목적 (Goals)

ai-litellm-fabric는 강력하지만 **명령 표면이 매우 크다**(`ai-litellm`의 13개 그룹 × 다수 verb + deprecated flat form + 5개 standalone 바이너리). 사람이 이 명령들을 일일이 기억하기 어렵고, 프록시/모델/라우트/런타임/예산/하니스 사이의 **관계와 현재 상태를 한눈에 파악하기 어렵다.**

이 프로젝트는 그 위에 얇은 **"관제층(control plane) TUI"** 를 추가한다. 단일 실행파일(`fabric`)로:

1. **본다(SEE):** 프록시 health, config 신선도, 모델/라우트/예산 매트릭스, 런타임 상태, 키 위치, doctor 결과, 라이브 로그를 한 화면에서.
2. **한다(DO):** 그 자리에서 안전하게 sync/restart/start/stop, 하니스 launch, doctor 실행 — 위험·과금 작업은 결과를 명시하는 확인 모달을 거쳐서.
3. **이해한다(RELATE):** 좌측 개념 트리가 proxy→runtime→model→route→harness→budget의 위계를 그대로 드러내 "관계 지도" 역할을 한다.

## 2. 비목적 (Non-Goals)

- **backend 로직 변경 없음.** `lib.zsh`의 동작은 한 줄도 바꾸지 않는다(아래 §4의 `--json` 출력 포매터 추가만 예외이며, 이는 비파괴·additive).
- **agent 사용성 변경 없음.** 기존 `ai-litellm`/`claude-litellm`/`codex-litellm`/… CLI는 그대로 동작한다. TUI는 그 위의 선택적 레이어다.
- **served surface(웹 서버) 없음.** 이 프로젝트의 "no served surface" ethos를 유지한다. (웹 대시보드는 명시적으로 v1 비목적; §11 참조.)
- **이번 감사에서 나온 CLI 정리(H4/H5/H6 등)는 이 spec의 범위 밖.** 별도 선택 트랙(§11)으로 둔다. v1은 순수 additive.
- TUI에서 config/registry 편집, reasoning set/unset, context probe 기록 같은 **mutating 편집 UI**는 v1 비목적.

## 3. 제약 (Constraints)

- **dependency-light ethos.** 새 런타임 언어를 도입하지 않는다. TUI는 이미 hard prereq인 Python으로 작성한다.
- **새 의존성은 `textual` 하나(선택적).** `litellm`이 "runtime-only, 없으면 note만"인 것과 동일한 패턴으로, `textual`은 `fabric`/`ai-litellm dash`를 **쓸 때만** 필요한 선택 의존성이다. preflight는 fatal로 막지 않고 actionable note를 낸다.
- **포터블.** 다른 Mac에 install.zsh로 깔리는 패키지의 일부로 동작한다(shim으로 설치).
- **single-user local machine** 전제는 기존과 동일(프록시는 `127.0.0.1:4000`).

## 4. 아키텍처

```
        Textual TUI (Python)                ← 이 프로젝트가 새로 만드는 유일한 코드
              │  subprocess 호출 + JSON 파싱 (직접 로직 없음)
              ▼
   ai-litellm <group> <verb> --json         ← 추가: "읽기" 명령에 --json 출력 포매터 (additive·비파괴)
   ai-litellm <group> <verb>                ← 액션은 기존 명령을 그대로 호출
              │
              ▼
        기존 lib.zsh  (로직 100% 불변)
              ▼
   LiteLLM 프록시 / state 파일 / Keychain / runtimes(oMLX)
```

**제1원칙: TUI는 상태를 재계산하지 않는다.** 모든 상태는 기존 CLI의 `--json` 출력으로 읽고, 모든 액션은 기존 CLI를 호출한다. 이렇게 해야 backend가 단일 진실 원천으로 남고, TUI가 lib.zsh 내부에 결합되지 않으며, `--json` 출력이 스크립팅에도 독립적으로 유용해진다.

**왜 `--json`인가(스크린 스크래핑 대신):** 기존 출력은 `printf "%-18s"` 단색 텍스트 테이블이라 파싱이 취약하다. 읽기 명령에 안정적 `--json`을 더하면 TUI가 견고해지고, 부수효과로 CLI 자체가 기계가독성을 얻는다.

### 4.1 `--json` API 계약 (additive)

다음 **읽기 전용** 명령에 `--json` 플래그를 추가한다(기존 텍스트 출력은 기본값으로 그대로 유지):

| 명령 | JSON 페이로드 (요지) |
|---|---|
| `proxy status --json` | `{health, pid, baseUrl, configCurrency: current\|stale\|unknown, configSha, startedAt, logPath, lock}` |
| `capabilities --json` | `{proxyHealth, dropParams, runtimes:[…]}` |
| `runtime status [name] --json` | `{name, baseUrl, apiBase, health, requiredModels:[{model, ok}], advertisedModels:[…]}` |
| `model list --json` | `[{name, backend}]` |
| `model limits [model] --json` | `[{model, context, output, effectiveInput, sources:{…}}]` |
| `route list/info [model] --json` | `[{modelName, providerModel, provider}]` |
| `context matrix [filter] --json` | per-surface budget rows |
| `reasoning matrix [model] --json` | `[{model, effort, dropRisk}]` |
| `context observations [filter] --json` | seed+live evidence rows |
| `key status --json` | `{openrouter:{source}, master:{source}}` |
| `harness list --json` / `harness info <name> --json` | `[{name, adapter, command, isolation, baseUrl, valid, cliInstalled}]` |
| `*doctor … --json` | `{checks:[{name, status: ok\|warn\|fail, detail}]}` |

- 각 `--json` 추가는 **출력 포매터 분기일 뿐** 계산 로직을 새로 짜지 않는다(이미 내부에서 구조화된 데이터를 텍스트로 찍는 지점에 JSON 분기 추가).
- 골든 테스트로 스키마를 고정한다(§10).
- 구현은 점진적으로 가능: TUI가 우선 필요로 하는 명령부터(`proxy status`, `model limits`, `harness list`, `*doctor`) 추가한다. JSON이 아직 없는 명령은 TUI가 "텍스트 보기"로 폴백(스크래핑 아님, 원문 그대로 표시)한다.

## 5. TUI 컴포넌트 (v1)

```
┌ ai-litellm fabric ───────────────  ● proxy: ok   ◆ config: STALE → sync   :4000   omlx ● ┐
│ Concepts          │  <선택된 개념의 본문 패널>                                            │
│  ▸ Proxy          │   Proxy: health/pid/sha + ┌ log (live tail) ┐                         │
│  ▸ Harnesses (4)  │   Models/Routes: DataTable(name→backend, context/output/eff, sources) │
│  ▸ Models/Routes  │   Budget&Policy: clamp·cost-guardrail 상태 + reasoning matrix(drop_risk)│
│  ▸ Runtimes       │   Harness: info + [Launch]                                            │
│  ▸ Budget&Policy  │   Runtimes: oMLX 상태 + discovered routes                             │
│  ▸ Keys           │   Keys: resolve 위치                                                  │
├───────────────────┴──────────────────────────────────────────────────────────────────┤
│ [s]ync [r]estart [d]octor(all) [l]aunch [p]robe [q]uit      ⚠ 위험·과금 = 확인 모달        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Header (status bar):** proxy health 점(green/amber/red), `config current/STALE→sync` 배지(가장 actionable한 신호), `host:port`, 런타임 상태 점. 라이브 자동갱신.
- **Left Tree (Concept map):** Proxy / Harnesses(claude·codex·goose·opencode) / Models·Routes / Runtimes / Budget&Policy / Keys. 선택 시 본문 패널이 contextual하게 바뀐다. 이 트리가 "관계 지도" 역할.
- **Main panel:** 트리 선택에 따른 뷰. 핵심 위젯: `DataTable`(limits/routes/reasoning matrix), `RichLog`(라이브 로그 tail), `Tree`/`Static`(harness info, keys).
- **Action bar (footer):** 키 바인딩 액션. 위험(`sync`/`restart`/`stop`)·과금(`probe`/cloud `launch`) 작업은 **확인 모달**이 결과를 명시("sync는 활성 LiteLLM 세션을 끊을 수 있음", "probe는 실제 과금 요청").
- **Launch flow:** Harness 선택 → [Launch] → 모델/tier picker → (cloud면 과금 경고) 확인 → 기존 `ai-litellm harness launch <name> [model]`을 exec.

### 5.1 자동갱신 정책

- **자동갱신 대상 = 읽기·무료만:** proxy health, config currency(stale 여부), runtime health, 로그 tail. 폴링 주기 기본 `~3–5s`(설정 가능).
- **무거운/과금 작업은 절대 자동 실행 안 함:** `*probe`, `route check`, `refresh-capabilities`, cloud `launch`는 사용자 명시 트리거 + 확인 모달에서만.

## 6. 안전 분류 (Safety classification)

TUI는 모든 액션을 다음 등급으로 분류해 시각 표시·확인 정책을 건다(인벤토리 감사 기준):

| 등급 | 예 | TUI 처리 |
|---|---|---|
| Safe (read-only) | `*status`, `*list`, `*matrix`, `key status`, `*doctor`(probe 플래그 없이) | 자유 실행, 자동갱신 가능 |
| Mutating (disk/config) | `key set`, `reasoning set/unset`, `refresh-capabilities --apply` | (대부분 v1 비목적) 명시 트리거 |
| Restart-causing | `proxy stop/restart`, `sync`(기본) | **확인 모달**: "활성 세션 중단 가능" |
| Billable / live | `route/model probe`, `route check`, `*probe`, cloud `harness launch` | **확인 모달**: "실제 과금" + 비용 힌트 |
| Destructive | `uninstall` | **이중 확인** 또는 v1에서 제외 |

추가로 노출할 안전망: gateway `x-gateway-cost-guardrail`(200K/240K)과 `x-gateway-output-clamp`(32000/8192/32768)를 "활성 정책"으로 Budget&Policy 패널에 표시.

## 7. v1 범위 (YAGNI)

**포함:**
- 읽기 패널 6종(Proxy/Harnesses/Models·Routes/Runtimes/Budget&Policy/Keys) + 라이브 header/log.
- 안전 액션: `sync`(+dry-run/no-restart), `restart`, `start`, `stop`, `doctor(all)`, `harness launch` — 등급별 확인 모달.
- 안전 분류 + 과금/재시작 경고.

**제외(나중 버전):**
- TUI에서 config/registry 편집, `reasoning set/unset` UI, `key set` UI, `context probe record` UI.
- 멀티 런타임 관리, 테마 확장(라이트/다크 외), 웹 export.
- 과금 probe의 인터랙티브 실행(트리거만 두되 강한 확인).

## 8. 패키징 / 설치 / 호출

- **두 진입점:** standalone `fabric` 바이너리 → 내부적으로 `ai-litellm dash` 서브커맨드를 호출. 둘 다 패키지 shim으로 설치.
  - `bin/fabric` (thin shim, 기존 `bin/*` 패턴과 동일: nvm/FABRIC_HOME bootstrap 후 `ai-litellm dash` 호출).
  - `ai-litellm dash` dispatch를 `lib.zsh` 디스패처에 추가(새 그룹 1개) → `python3 -m <tui_module>` 실행.
- **TUI 코드 위치:** `config/ai-litellm/dash/` (Python 패키지). install.zsh가 다른 rendered 파일과 함께 prefix로 설치.
- **의존성:** `textual`은 선택 의존성. install.zsh preflight는 `litellm`과 동일하게 "없으면 note(설치 명령 안내), fatal 아님". `fabric` 실행 시 `textual` 미존재면 actionable loud-fail(`python3 -m pip install textual`).
- **install.zsh / README / check.zsh** 갱신: 새 shim 1개(`bin/fabric`)만 등록(`ai-litellm dash`는 기존 `ai-litellm` shim의 서브커맨드라 별도 shim 불요), README에 사용법, check.zsh에 `fabric` shim 존재·`zsh -n`·`--json` 골든 단언 추가.

## 9. 에러 처리

- 프록시 다운 → 해당 패널이 "프록시 미기동 — [start]"로 actionable 표시(빈 화면/스택트레이스 금지).
- native CLI 부재(예: codex 미설치) → 해당 harness 항목 회색 + "native codex 필요" 힌트, launch 비활성.
- `--json` 파싱 실패 → 패널에 loud 에러 라인 + 원문 텍스트 폴백, **절대 silent 아님**.
- 액션 실패(비-0 종료) → 모달에 stderr 표시, 상태 재조회.

## 10. 테스트 전략

- **`--json` 포매터:** check.zsh(또는 python) 골든 테스트로 각 명령의 JSON 스키마/키 고정. 실제 provider 호출 없이 mock/로컬 상태로.
- **TUI 로직:** Textual `Pilot`(headless) 유닛테스트 — 상태모델, 안전 등급 분류, 확인 모달 게이팅(과금/재시작 액션이 확인 없이 실행되지 않음을 단언), `--json` 파싱.
- **격리:** 테스트는 mock CLI JSON을 주입, **실제 과금/네트워크 호출 0**. 기존 `verify_*.py`·check.zsh 철학과 일치.
- TUI는 backend를 안 건드리므로 기존 check.zsh 경계 단언(native dir 비생성 등)에 영향 없음.

## 11. 향후 / 별도 트랙

- **CLI 정리(별도, 선택):** 이번 복잡도 감사의 실행가치 높은 항목 — usage 라벨↔명령 불일치(H4), 통합 `ai-litellm doctor`(H5), route-probe 동의어 정리(H6), `model info`≠`route info`(M21), uninstall 약한 재구현·Keychain 하드코딩(M14/M15), 죽은 fallback loud-fail(M16/M17), 에이전트용 스크래치 문서 2개 삭제(M23). TUI v1과 독립적으로 진행 가능하나, `--json` 작업과 같은 파일을 만지므로 함께 묶으면 효율적일 수 있음(선택).
- **예산 수식 3중 구현 차등 테스트(H1/H2/H3):** 매직넘버 핀(221950/3277)을 "세 구현에 같은 입력→같은 출력" 차등 테스트로 격상. TUI와 무관한 별도 하드닝.
- **웹 대시보드(v2+, 선택):** 관계 그래프·차트가 필요해지면 로컬 웹으로 승급. 이 경우에만 `frontend-design`/`claude-design` 스킬이 완전히 적용됨. ethos(no served surface) 역행이므로 명시적 결정 필요.
- **claude-design 보조 스킬:** TUI 상태 색체계엔 `design:accessibility-review`(대비/색맹 안전), doctor 메시지·메뉴 문구엔 `ux-copy`가 시각 디자인보다 유용.

## 12. 미해결 / 결정 필요

- `--json` 스키마의 정확한 키 네이밍(camelCase vs snake_case) — 구현 계획에서 확정.
- 자동갱신 기본 주기 값.
- `fabric`가 인자 없이 뜨면 대시보드, 인자 있으면 패스스루할지(예: `fabric proxy status`=`ai-litellm proxy status`) 여부 — UX 편의이나 v1 필수 아님.

---

*이 spec은 2026-06-18 브레인스토밍 합의안이다. 다음 단계는 writing-plans로 구현 계획 수립.*

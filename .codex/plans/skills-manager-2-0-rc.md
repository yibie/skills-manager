# Skills Manager 2.0 RC — Work Plan

> [!IMPORTANT]
> **Archived on 2026-08-05.** This is the execution plan that led to the
> 2.0.0 unsigned internal RC published on 2026-08-04; it is not an active task
> list. The unchecked criteria below preserve the original planning record.
> Use [README](../../README.md), [CHANGELOG](../../CHANGELOG.md), and the
> [2.0.0 release guide](../../docs/releases/2.0.0.md) for current status.

## TL;DR

- **What you will get:** a locally verified macOS 2.0 release candidate with
  safe Collection state, retryable lifecycle takeover, an upgrade/identity
  contract, real-window UI evidence, and honest release gates.
- **Approach:** freeze the existing safety work first, then land four small
  follow-up changes in dependency order.
- **Will not do:** TUI parity, cloud/project automation, Inspector restoration,
  App Store automation, new dependencies, or credential fabrication.
- **Decisions:** `Info.plist` is the version authority; trusted provenance is
  identity authority; overlapping links are protected by a small scan rather
  than persisted reference counts; unsigned output is internal RC only.

## RALPLAN-DR

### Principles

1. Freeze a verified, auditable safety baseline before new work.
2. Keep one version and identity contract.
3. Report state near the object; never manufacture success.
4. Prefer reconstructable diagnostics and a bounded scan over new persistence.
5. Treat real macOS interaction and release honesty as RC gates.

### Decision drivers

1. Protect user-owned local skill data.
2. Make each change independently reversible and verifiable.
3. Prevent unsigned or mismatched output from being presented as formal 2.0.

### Options considered

- **Sequential five-change convergence (chosen):** safest with the current
  large working copy and the clearest rollback boundaries.
- **Parallel file-domain work:** faster but rejected because `ContentView`,
  `SkillStore`, and `InstallService` are shared semantic boundaries.
- **Service fixes only:** rejected because repository policy makes live-window
  UI and formal distribution behavior completion gates.

### Pre-mortem

1. Baseline and new fixes blur together. Mitigation: verify, `jj describe`,
   and `jj new` before follow-up implementation.
2. Upgrade, UI, and release invent different identities/versions. Mitigation:
   land the shared contract before diagnostics and fixtures.
3. Snapshots and an unsigned ZIP create false RC confidence. Mitigation: real
   window evidence and a release workflow that cannot publish without gates.

## ADR

### Decision

Ship macOS as the formal 2.0 surface and converge on five sequential Jujutsu
changes: safety baseline, version/identity contract, diagnostics/recovery,
real-window UI gate, and release/RC documentation.

### Drivers

- current working-copy safety fixes are valuable but not yet frozen;
- the primary risk is local-data lifecycle correctness;
- the TUI shares disk state but does not share the Collection model;
- signing credentials and external beta users are outside local authority.

### Alternatives rejected

- name/display-name identity: ambiguous and already caused same-name errors;
- a second version config: creates drift instead of preventing it;
- persistent link reference counts: unnecessary for current Collection scale;
- TUI parity: broadens 2.0 without strengthening the macOS promise;
- unsigned formal release: fails the distribution trust boundary.

### Consequences

- an O(n²) Collection scan is accepted for the current scale and should carry a
  `ponytail:` ceiling comment;
- legacy IDs remain readable but are not the forward identity authority;
- VoiceOver, signing/notarization, and external beta evidence can remain honest
  external gates while local repository readiness is completed.

### Follow-ups

- replace the overlap scan only if measured Collection scale makes it material;
- consider on-demand update detection after the identity/commit contract;
- reconsider TUI convergence as a separate product initiative.

## Dependency graph

| Task | Depends on | Blocks |
|---|---|---|
| 1. Freeze safety baseline | None | 2–5 |
| 2. Version and identity contract | 1 | 3–5 |
| 3. Diagnostics and recovery | 2 | 4–5 |
| 4. Real macOS UI gate | 3 | 5 |
| 5. Release/CI/docs gate | 4 | RC handoff |

## Execution waves

```text
Wave 0: Task 1
Wave 1: Task 2
Wave 2: Task 3
Wave 3: Task 4
Wave 4: Task 5 + independent final review
```

## Tasks

### 1. Freeze the current safety baseline

- **Files:** current working-copy files only.
- **Agent:** `executor` for regression repair if required; `verifier` for the
  four baseline commands.
- **Acceptance:** tests, analyze, Release build, and TUI build pass; current
  change receives a Lore description; `jj new` creates the follow-up change;
  no bookmark or push.
- **QA:** commands in `.omx/plans/test-spec-skills-manager-2-0.md`.
- **Lore intent:** `Freeze current security fixes as the 2.0 RC baseline`.

### 2. Land the version and stable-identity contract

- **Files:** `SkillsManager/Info.plist`, existing Skill/provenance and
  persistence helpers, focused tests, version-check script/workflow input.
- **Agent:** `executor`, followed by `code-reviewer`.
- **Acceptance:** tag validation reads `Info.plist`; trusted normalized
  sourceURL+skillID is stable; manual canonical fallback works; legacy ID reads
  remain compatible; v1.x fixture upgrade is idempotent.
- **QA:** focused identity/migration/version tests, then full macOS suite.
- **Lore intent:** `Anchor upgrades and release checks on one identity contract`.

### 3. Close Collection diagnostics and takeover recovery

- **Files:** `CollectionSupport`, `ActivationService`, `SkillStore`,
  `ContentView`, Collection views, `InstallService`, focused tests.
- **Agent:** two bounded `executor` lanes may work in parallel only when file
  ownership is split between Collection and takeover files; leader integrates
  shared tests and owns final verification.
- **Acceptance:** missing-only never records mounted intent; shared links are
  protected by scanning other mounted Collections; reload reconstructs
  actionable reasons; takeover crash fixtures converge or diagnose
  idempotently without losing backups.
- **QA:** all focused cases in the test spec, then full suite and analyze.
- **Lore intent:** `Keep collection and takeover recovery explicit without reference counts`.

### 4. Pass the real macOS interaction gate

- **Files:** only UI/a11y fixes discovered by the prescribed matrix plus the
  evidence record.
- **Agent:** `designer` or `executor` for fixes, `verifier` for evidence.
- **Skills:** `visual-verdict` when comparing screenshots after each visual
  edit; project UI documents remain authoritative.
- **Acceptance:** real app launched; fixed data/window/system matrix exercised;
  screenshots stored; keyboard and accessibility outcomes recorded; untested
  VoiceOver is marked external/manual.
- **QA:** UI unit tests plus live-window checklist. Snapshot-only evidence fails.
- **Lore intent:** `Gate the 2.0 RC on real macOS interaction evidence`.

### 5. Make the RC release path honest and reproducible

- **Files:** `.github/workflows`, `SkillsManager/Info.plist`, README/release and
  migration docs, RC verification record.
- **Agent:** `executor` for workflow/docs, `verifier` and `security-reviewer`
  for final release review.
- **Acceptance:** CI runs baseline commands; mismatched tag fails; unsigned
  output is internal RC only; no credentials means no publish/tag push/signing/
  notarization; tested/not-tested/external gates are complete.
- **QA:** local CI-equivalent commands, workflow syntax inspection, full suite,
  Release build, TUI build, final `jj status` and diff check.
- **Lore intent:** `Gate the 2.0 RC without treating unsigned output as final`.

## Agent roster and staffing

Available useful native roles: `planner`, `architect`, `critic`, `explore`,
`executor`, `debugger`, `test-engineer`, `designer`, `security-reviewer`,
`code-reviewer`, and `verifier`.

- Ralph-style sequential execution: one `executor` owns each task; use
  `test-engineer` for fixtures and `verifier` after every change.
- Parallel work is safe only inside Task 3 with disjoint ownership:
  Collection files vs `InstallService` takeover files.
- Suggested effort: executor/architect high, verifier/test-engineer high,
  UI designer high, lightweight exploration low.
- Native App launch hint: use the current root session plus bounded subagents.
  A real `omx team`/`$team` launch requires an attached tmux OMX CLI session
  and is intentionally not attempted from this surface.

## Team verification path

1. Focused regression test in each task.
2. Full macOS tests after every behavioral task.
3. Static analysis and Release build after Tasks 1, 3, and 5.
4. TUI build after Tasks 1 and 5.
5. Independent code review after Tasks 2–3.
6. Live-window evidence after Task 4.
7. Independent release/security verification before RC handoff.

## Success criteria

- [ ] Five changes are individually described and reversible.
- [ ] Full automated verification is green.
- [ ] Real-window UI evidence is recorded.
- [ ] No known missing-only, overlap, reload, or takeover false-success path.
- [ ] Version/tag mismatch is rejected.
- [ ] Unsigned/not-notarized output cannot be mistaken for formal release.
- [ ] External beta/signing/publish gates remain explicitly open until real.

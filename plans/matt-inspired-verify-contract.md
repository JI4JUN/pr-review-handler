# Plan: Matt-inspired verify + fix-contract for pr-review-handler

> **Implementation repo (SoT):** `~/Documents/Western/personal/pr-review-handler`  
> **Canonical skill path:** `skills/pr-review-handler/`  
> **Do not edit:** consumer copies (e.g. AI-Media-Studio `.pi/skills/…`)

## Context

### Problem

Triage already checks the reviewer's premise, but the **evidence model is soft**:

- Verdict is only `valid-fix | valid-nofix | invalid` — no forced **claim_check** or **code_path**
- "Is this in the PR diff?" is prose guidance, not a hard field / gate
- `suggested_fix` is free text — Implementation has no **acceptance checklist** or **out_of_scope**
- Unclear threads collapse into `invalid` + `"unclear — needs human review"` without a structured "need from user" row
- Replies post as the PR author with **no AI-assisted marker**
- No durable place for team **review stances** (recurring bot nags the team always declines)

These gaps match failure modes Matt Pocock's skills address (`/triage` claim verify, `AGENT-BRIEF` durability, `/code-review` Standards∥Spec axes) — without adopting his issue-tracker state machine (wrong product surface).

### Intended outcome

Keep the existing pipeline (Phase 0→5, parallel triage, serial fix, dual checkpoints). Harden:

1. **Claim verification** before any `valid-fix`
2. **PR-diff ownership** as a first-class signal
3. **Fix contract** (behavior + AC + OOS) for Implementation
4. Optional **AI disclaimer** on replies
5. Optional **review stances** file (later slice)

### Non-goals

- Do **not** import Matt's five-state issue triage / labels / `.out-of-scope/` as-is
- Do **not** pull in `/improve-codebase-architecture`, full `/grilling`, or AFK `/implement`
- Do **not** force tests on every review fix (keep orchestrator verify + `acceptance: none` for pi-subagents)
- Do **not** edit consumer installs — only the pr-review-handler monorepo SoT

## Approach

Single source of truth:

```
skills/pr-review-handler/
  SKILL.md
  agents/triage-agent.md
  agents/implementation-agent.md
```

`scripts/sync-skill.mjs` already **generates** Pi project agents from those specs → changing specs is enough for both inline embed and `pr-review-handler.triage` / `.implementation`.

Ship as **minor** version (contract additive + gates). Recommend **v1.4.0**.

| Slice | Name | Risk | In 1.4.0? |
|-------|------|------|-----------|
| **A** | Claim evidence + in_pr_diff + Checkpoint columns | Low | Yes |
| **B** | Fix contract (AC + OOS) + Implementation completion gate | Low–med | Yes |
| **C** | Reply AI disclaimer + out-of-PR stock phrase | Low | Yes |
| **D** | Optional `review-stances` + progressive disclosure | Med | Follow-up |

**Recommended first release: A + B + C together.** **D** separate.

Inspiration mapping (do not vendor Matt's files):

| Matt idea | Adaptation here |
|-----------|-----------------|
| Verify claim → confirmed / failed / insufficient + code path | `claim_check` + `evidence` on triage YAML |
| PR = claim on attached code | `in_pr_diff` + scope default for baseline-only code |
| Agent Brief durability / AC / OOS | **fix contract** on `valid-fix` |
| Standards ∥ Spec axes | optional `axis` field (no second sub-agent) |
| AI triage disclaimer | reply footer; human still approves at Checkpoint 2 |
| `.out-of-scope/` | later: consumer-repo `docs/agents/review-stances.md` (Slice D) |

## Files to modify

### Must (Slices A–C) — under `~/Documents/Western/personal/pr-review-handler`

| File | Change |
|------|--------|
| `skills/pr-review-handler/agents/triage-agent.md` | Steps 3–4 + YAML: claim_check, evidence, axis, fix contract |
| `skills/pr-review-handler/agents/implementation-agent.md` | Input schema + complete AC; respect OOS |
| `skills/pr-review-handler/SKILL.md` | Checkpoint 1 columns; Phase 2 payload; Phase 3 disclaimer; gates; Key Principles |
| `README.md` / `README.zh.md` | Short verdict/evidence note |
| `packages/core/package.json` | `1.3.2` → `1.4.0` |
| `packages/pi/package.json` | `1.3.2` → `1.4.0` |

### Generated / no hand-edit

| Path | How |
|------|-----|
| `packages/*/skills/**` | `npm run sync` after skill edit |
| Consumer `.agents/pr-review-handler/*.md` | `/pi-pr-review-handler-sync` after upgrade |

### Slice D only (optional later)

| File | Change |
|------|--------|
| `skills/pr-review-handler/REPLY-PATTERNS.md` | Move long EN/中文 examples out of SKILL.md |
| `skills/pr-review-handler/VERIFY.md` | Claim matrix + in_pr_diff rules |
| `skills/pr-review-handler/SKILL.md` | Pointers + optional stances path |
| Root README | Document `docs/agents/review-stances.md` convention |

## Reuse

| Existing piece | Path | Use |
|----------------|------|-----|
| Pipeline / checkpoints | `SKILL.md` | Extend tables & payloads only |
| Premise + pr_diff_context | `triage-agent.md` | Formalize into claim_check |
| completeness / correctness / coherence | `implementation-agent.md` | Bind completeness to AC list |
| Project agent codegen | `scripts/sync-skill.mjs` | Re-run only; no logic change |
| Pi sync command | `packages/pi/extensions/sync-agents.ts` | Unchanged |
| Dedup / review-level / GraphQL resolve | `SKILL.md` | Keep as-is |

## Schema (target)

### Triage YAML (A + B)

```yaml
thread_id: <id>
path: <file:line>
reviewer: <name>
summary: <one-line concern>
verdict: valid-fix | valid-nofix | invalid
claim_check: confirmed | failed | insufficient   # required
axis: standards | spec | both | n/a                # preferred, not hard-fail
reason: <one sentence>
evidence:                                         # required
  code_path: <symbol / control-flow; required if confirmed>
  in_pr_diff: true | false | unknown
  already_handled: <if invalid because pre-existing handling>
  missing: <if insufficient>
affected_files: [...]
# valid-fix only — fix contract:
suggested_fix: <behavioral; symbols over bare line numbers>
acceptance:
  - <checkable criterion>   # 2–4 items
out_of_scope: []            # explicit non-goals
```

### Hard gates

| Rule | Where |
|------|--------|
| `valid-fix` ⇒ `claim_check: confirmed` + non-empty `code_path` | triage-agent + Checkpoint 1 |
| `insufficient` ⇒ never auto `valid-fix`; show Need from user | triage + SKILL |
| `in_pr_diff: false` + non-critical nit ⇒ default `valid-nofix` (or OOS), not silent fix | triage steps |
| Implementation done ⇒ every acceptance item done or in `concerns` | implementation-agent |
| Do not implement `out_of_scope` | implementation constraints |

Backward compat: missing new fields at Checkpoint 1 ⇒ treat as **insufficient** / human fill — do not invent `valid-fix`.

### Checkpoint 1 table

| # | File:Line | Reviewer | Summary | Claim | In PR? | Axis | Verdict | Affected |
|---|-----------|----------|---------|-------|--------|------|---------|----------|

`insufficient` rows add **Need from user** (`evidence.missing`).

### Phase 2 payload

Pass `acceptance` + `out_of_scope` + behavioral `suggested_fix` + existing `prior_changes`.

### Phase 3 (C)

- Default **on** footer (Checkpoint 2 may strip):

  `> _(AI-assisted reply — approved in pr-review-handler checkpoint)_`

- `in_pr_diff: false` + nofix stock phrase:

  - EN: "Agreed this is worth tracking, but it's outside this PR's diff — happy to take it in a follow-up."
  - 中文: 「同意值得跟进，但不在本 PR diff 内；建议单独开 issue / 后续 PR。」

## Steps

### Slice A — Claim evidence

- [x] **A1.** `triage-agent.md` §3 → **Verify the claim** (confirmed / failed / insufficient); `code_path` required on confirmed
- [x] **A2.** `in_pr_diff` rule + default scope when false
- [x] **A3.** YAML + Constraints: `valid-fix` only if confirmed + code_path
- [x] **A4.** Unclear → `claim_check: insufficient` + `evidence.missing` (keep 3 verdicts; claim_check carries nuance)
- [x] **A5.** Optional `axis` guidance (standards vs spec)
- [x] **A6.** `SKILL.md` Checkpoint 1 table + collect-verdict gates
- [x] **A7.** Key Principles: claim must be confirmed with code_path

### Slice B — Fix contract

- [x] **B1.** `valid-fix` requires `acceptance` (2–4) + `out_of_scope` (may be `[]`)
- [x] **B2.** `suggested_fix` behavioral / symbol-oriented
- [x] **B3.** `implementation-agent.md`: new input; completeness = AC; forbid OOS; unmet AC → `concerns`
- [x] **B4.** `SKILL.md` Phase 2 template includes acceptance / out_of_scope
- [x] **B5.** Phase 5: optional `regression-gap` note if concerns say no test (no forced tests)

### Slice C — Reply hygiene

- [x] **C1.** AI-assisted footer (default on)
- [x] **C2.** Out-of-PR stock phrases EN/中文
- [x] **C3.** Key Principles bullet on AI reply transparency

### Release glue

- [x] **R1.** Bump core + pi → `1.4.0`
- [x] **R2.** `npm run sync` — generated agents contain new schema
- [x] **R3.** README.md + README.zh.md short evidence section
- [x] **R4.** Release notes / changelog on publish

### Slice D — follow-up (not default 1.4.0)

- [ ] **D1.** `REPLY-PATTERNS.md` / `VERIFY.md` progressive disclosure
- [ ] **D2.** Optional `docs/agents/review-stances.md` if present
- [ ] **D3.** Document stance format + human confirm on match

## Leading words (embed in prose)

| Word | Meaning |
|------|---------|
| **claim** | Reviewer's asserted premise |
| **code_path** | Concrete symbol/flow proving the claim |
| **fix contract** | suggested_fix + acceptance + out_of_scope |
| **minimal fix** | Smallest diff satisfying acceptance only |
| **checkpoint** | Human gate |
| **ground-truth diff** | Replies describe `git diff`, not intent |

## Verification

### Static

- [ ] `npm run sync` exits 0 (in pr-review-handler monorepo)
- [ ] Generated pi/core skill trees include `claim_check` and `acceptance`
- [ ] Checkpoint example rows in SKILL.md updated

### Manual dry-run (after local install / sync)

1. Confirmed + in PR → valid-fix + AC → fix checks AC
2. Failed claim → no Phase 2
3. Insufficient → Need from user; no auto-fix
4. in_pr_diff false nit → valid-nofix + stock phrase
5. OOS pressure → implementation `concerns`, no silent scope creep
6. User strips disclaimer at Checkpoint 2 → footer absent

### Regression

- [ ] Dedup, review-level feedback, GraphQL resolve, pi `acceptance: { level: "none" }` unchanged except payload extensions
- [ ] Inline fallback still embeds updated specs

## Version & publish

1. Edit SoT under `~/Documents/Western/personal/pr-review-handler`
2. `npm run sync`
3. Publish `1.4.0` core + pi
4. Consumers: upgrade + `/pi-pr-review-handler-sync`

## Open decisions (defaults if approved as-is)

| # | Topic | Default |
|---|--------|---------|
| 1 | A+B+C in one 1.4.0 vs A-only | **A+B+C** |
| 2 | 4th verdict vs claim_check only | **claim_check only** (3 verdicts) |
| 3 | AI disclaimer default | **On** |
| 4 | Slice D in same release | **No** |
| 5 | `axis` required? | **Preferred, not hard-fail** |

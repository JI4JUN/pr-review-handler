# Changelog

## 1.4.0

### Claim verification and fix contract

Inspired by verification / agent-brief discipline (claim evidence, durable acceptance), without adopting an issue-tracker state machine.

**Triage agent**

- Required `claim_check`: `confirmed` | `failed` | `insufficient`
- Required `evidence`: `code_path`, `in_pr_diff`, `already_handled`, `missing`
- Preferred `axis`: `standards` | `spec` | `both` | `n/a`
- `valid-fix` hard gate: only when `confirmed` + non-empty `code_path`
- **Fix contract** on `valid-fix`: behavioral `suggested_fix`, `acceptance` (2–4), `out_of_scope`
- Baseline-only nits (`in_pr_diff: false`) default away from silent `valid-fix`

**Implementation agent**

- Consumes fix contract; completeness judged against `acceptance`
- Must not implement `out_of_scope`
- May note `regression-gap` in concerns (no forced tests)

**Orchestrator (SKILL.md)**

- Checkpoint 1 table: Claim / In PR? / Axis columns; Need from user for insufficient
- Collect-verdict gates before Checkpoint 1
- Phase 2 payload passes acceptance + out_of_scope
- Phase 3: AI-assisted reply footer (default on); out-of-PR stock phrases EN/中文
- Phase 5: surface regression-gap notes
- Key Principles: claim+code_path, fix contract, AI transparency, checkpoints as gates

**Docs**

- Root and package READMEs (EN/中文) describe evidence fields and fix contract

### Unchanged

- Pipeline phases, dedup, review-level feedback, GraphQL resolve
- Pi `acceptance: { level: "none" }` for subagent dispatch
- `/pi-pr-review-handler-sync` extension

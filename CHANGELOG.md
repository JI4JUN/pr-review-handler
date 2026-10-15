# Changelog

## 1.6.1

### Anti-ping-pong defenses & repository convention gating

- **Repository Conventions First**:
  - Triage and Implementation agents are instructed to read `AGENTS.md` / `CLAUDE.md` at the repository root first as the authoritative law of the codebase.
  - Enforced Three Constitutional Pushback Gates:
    - *Impossible Scenarios*: Reject defensive overkill for hypothetical inputs (e.g. throwing Proxies, astronomical error chains) when repo conventions mandate simplicity.
    - *Pre-existing Baseline*: Defend surgical PR boundaries against adjacent baseline code smell.
    - *Premature Abstraction*: Reject unrequested helper modules and multi-file refactoring.
- **Blast Radius Lock & In-Place Minimal Fixes**:
  - Strictly forbid creating new files or modules during review fix rounds. Fixes must be in-place and minimal.
  - Forbid absolute guarantees and global promises in code comments (e.g. `// never raises`) that invite semantic contradiction checks.
- **Diff Shrink Invariant**:
  - In review rounds $\ge 2$, bias toward `valid-nofix` for non-critical feedback to guarantee PR convergence.
- **Pure English normalization**:
  - Eradicated all Chinese trigger phrases, internal strings, and templates from skill and agent files.

## 1.6.0

### Modular architecture, precision triage & root-cause implementation

- **Modular skill layout & Progressive disclosure**:
  - `SKILL.md` trimmed from 540 lines to ~190 lines (-64% context load).
  - Standalone scripts in `scripts/`: `fetch-threads.sh` (GraphQL querying, diff hunks, deduplication, bot advisory extraction) and `resolve-threads.sh` (GraphQL thread resolution).
  - Standalone references in `references/`: `reply-templates.md` (bilingual templates & AI footer) and `review-taxonomies.md` (intent classification & checkpoint presentation).
  - Bot summary parsing: collapsed low-severity review findings (e.g. OpenCodeReview, CodeRabbit) are parsed into optional `advisory_items` at Checkpoint 1.
- **Precision Triage**:
  - Replaced procedural gate prose with a four-quadrant Decision Matrix and 4 Hard Negative Invariants (`No code_path no fix`, `Moved code is not a new bug`, `Discussion is not an action item`, `Never guess`).
  - Compact conditional YAML schema: omitted fix contract for non-fix verdicts (-65% generation tokens).
- **Architect-grade Implementation**:
  - Eliminated symptom-suppressing "patchwork" fix directives.
  - Enforced four core principles: Root-Cause over Band-Aid, Contract Bounded, Reference Closure (grep all callers), and Project Conventions First (`AGENTS.md`/`CLAUDE.md`).
- **Massive token efficiency**:
  - Runtime Phase 0 output token dump reduced by ~99% (writes directly to `/tmp/pr-context.json`).
  - Overall agent prompt and output tokens reduced by 50%–60%.

## 1.5.3

### Pi subagent async dispatch for ambient MCP extensions

- Explicitly require `async: true` when dispatching `pr-review-handler.triage` and `pr-review-handler.implementation` via Pi's `subagent` tool.
- Prevents child agents from running as foreground children that fail to load parent ambient extensions (`mcp:codegraph`).

## 1.5.2

### discussion_r link dedup

- Thread dedup gains a third rule: comments containing a `discussion_r<id>` link cluster with the thread that link points to.
- Re-raised findings that moved to a new line after code changes no longer surface as duplicate threads in triage.

## 1.5.1

### Shared-CWD parallel repair

- Proven-independent fixes now run concurrently in the current working directory instead of isolated Git worktrees.
- Parallel writers may edit only declared disjoint files and symbols; they cannot perform Git operations.
- Orchestrator inspects combined wave diff, then rolls back and reruns the whole wave serially if it finds overlap, dependency drift, or unexpected changes.

## 1.5.0

### Dependency-aware repair orchestration

- Added Phase 1.5 repair dependency analysis after triage confirmation.
- Triage now emits modified/referenced symbols, change kinds, and dependency risks for every `valid-fix`.
- Dependent or uncertain repairs run serially in graph order; only proven-independent groups run in isolated Git worktrees.
- Parallel worktree repairs use wave checkpoints, deterministic patch integration, full-wave rollback, and serial fallback on conflicts or newly discovered overlap.
- Implementation agents receive predecessor context and candidate repair manifests, then report structured dependency findings.
- Final repair history still squashes temporary checkpoints into one `fix(review)` commit.
- Synced Pi-agent guidance and all root/package READMEs; Pi projects use `/pi-pr-review-handler-sync` rather than Phase 0 auto-creation.

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

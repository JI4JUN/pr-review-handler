---
name: pr-review-handler
description: >
  Systematically process GitHub PR review comments: triage for validity,
  fix code, and post replies. Use whenever the user mentions PR reviews,
  code review feedback, reviewer comments, or wants to respond to review
  threads on a pull request. Triggers include: "handle reviews",
  "respond to PR comments", "fix review feedback", "reply to reviewer",
  "看看 PR 评论", "回一下 review", "处理 review 意见",
  "reviewer 说的那个问题", or any mention of dealing with PR review
  comments. Also triggers when the user pastes a PR link with unresolved
  conversations, mentions a reviewer by name in the context of their PR,
  or describes the situation: "someone left comments on my PR",
  "帮我看看那些人提的意见", "CI 过了但 review 还没回".
metadata:
  starchild:
    emoji: "🔍"
    skillKey: pr-review-handler
    requires:
      bins: [gh, git]
user-invocable: true
---

# PR Review Handler

Orchestrate specialized agents to process PR review comments:

```
Phase 0: Setup → Phase 1: Triage (parallel) → Checkpoint 1 (user confirmation)
         → Phase 1.5: Dependency Graph → Phase 2: Fix (dependency-aware waves)
         → Phase 3: Reply → Checkpoint 2 (user review) → Phase 4: Post & Push → Phase 5: Report
```

Checkpoints: after Phase 1 (user confirms verdicts) and after Phase 3 (user approves replies).

---

## Agent Roles & Dispatch

| Role | Responsibility | Parallelizable |
| :--- | :--- | :--- |
| **Triage Agent** (`agents/triage-agent.md`) | Read-only claim verification (evidence + code_path), emit fix contract | ✅ Yes (read-only) |
| **Implementation Agent** (`agents/implementation-agent.md`) | Apply root-cause minimal fix against fix contract; trace references | ⚠️ Parallel only after independence proof |
| **Orchestrator** (Current session) | State machine, wave Git checkpoints, reply drafting, and post/push | N/A |

### Dispatch Platform Mapping

Agent specs live in `agents/` relative to this skill.
- **Pi with `subagent`**: Run `/pi-pr-review-handler-sync` before dispatch. Use `pr-review-handler.triage` (Phase 1) and `pr-review-handler.implementation` (Phase 2). Pass `async: true` (ensures child extension/MCP loading) and `acceptance: { level: "none", reason: "orchestrator manages its own verification format" }`. Prompt = input data ONLY.
- **Claude Code / Cursor / Other CLI**: Embed agent spec (`agents/triage-agent.md` or `agents/implementation-agent.md`) into task prompt alongside input data.
- **Fallback (inline)**: If subtasks are unavailable or thread count $\le 2$, execute agent steps inline.

---

## Phase 0: Setup

1. **Context Fetch & Branch Guard**:
   Run the context-fetching script:
   ```bash
   bash skills/pr-review-handler/scripts/fetch-threads.sh [PR_NUMBER_OR_URL]
   ```
   This extracts unresolved threads, diff hunks, and PR metadata to `/tmp/pr-context.json`.

   **Enforce Branch Guard**:
   - Check current branch: `CURRENT_BRANCH=$(git branch --show-current)`.
   - Inspect `pr.head_branch` in `/tmp/pr-context.json`. If `CURRENT_BRANCH` does not match `pr.head_branch`:
     ```bash
     git fetch origin && git checkout "<head_branch>"
     ```
   - Require clean tree: `git status --porcelain`. Never apply fixes on `main` or a dirty branch.

2. On Pi, verify project agents exist (`test -f .agents/pr-review-handler/triage.md && test -f .agents/pr-review-handler/implementation.md`). If missing, advise running `/pi-pr-review-handler-sync` and fall back inline.
---

## Phase 1: Triage (Parallel Dispatch)

Read `/tmp/pr-context.json`. Thread count rules:
- $\ge 3$ threads: parallel subtasks (1 per thread). If $> 15$, batch by file (8–10 per batch).
- $\le 2$ threads: execute inline.

Dispatch each thread with:
```yaml
thread_id: <comment ID>
path: <file:line>
reviewer: <name>
comments: [<comment texts>]
pr_diff_context: <diff hunk from /tmp/pr-context.json>
```

### Triage Gates (Orchestrator Enforced)
- `verdict: valid-fix` **REQUIRES** `claim_check: confirmed` AND non-empty `evidence.code_path` AND 2–4 checkable `acceptance` items.
- If claim is about base-branch code (`in_pr_diff: false`), default to `valid-nofix` unless it is a critical vulnerability.
- `claim_check: insufficient` $\rightarrow$ surface **Need from user** (`evidence.missing`). Reference `references/review-taxonomies.md` for borderline taxonomy.

### Checkpoint 1: User Confirmation
Present findings in three tables (see `references/review-taxonomies.md` for details):
1. **Inline Review Threads** (`#`, `File:Line`, `Reviewer`, `Summary`, `Claim`, `In PR?`, `Verdict`, `Affected`).
2. **Review-Level Feedback** (Choose: *Ignore* / *Reply only* / *Needs code change*).
3. **Bot Advisory Items (Optional / Opt-in)** (Defaults to *Ignore*; user can select items to convert into Implementation tasks).

**Quick Exits**: If all verdicts are `invalid` or `valid-nofix`, skip Phase 2 and jump to Phase 3.

---

## Phase 1.5: Repair Dependency Analysis

Construct a directed graph (DAG) for all confirmed fixes:
1. Compare `affected_files`, `modified_symbols`, and `referenced_symbols`.
2. Add edge $A \rightarrow B$ if $A$ modifies symbols $B$ references, if $A$ is a provider/type producer and $B$ is a consumer, or if file sets overlap.
3. **Cannot prove independent means serial.**
4. Topologically sort graph into independent waves. Fixes within a wave must have strictly disjoint file and symbol sets.

---

## Phase 2: Implementation (Wave Execution)

1. Ensure working tree is clean: `git status --porcelain`. Record `REPAIR_BASE=$(git rev-parse HEAD)`.
2. Execute wave by wave:
   - Record `WAVE_BASE=$(git rev-parse HEAD)`.
   - Dispatch Implementation Agents (`agents/implementation-agent.md`) for the wave.
   - **Constraint**: Child agents edit only declared `affected_files` and must **NEVER** run git write commands (`git add`, `commit`, `checkout`, `push`).
   - If an agent reports `dependency_findings` or file overlap occurs:
     ```bash
     git reset --hard "$WAVE_BASE" && git clean -fd
     ```
     Roll back and rerun that wave serially.
   - On wave success:
     ```bash
     git add -A && git commit -m "chore(review): temporary repair checkpoint"
     ```

3. **After all fixes**:
   Squash temporary checkpoints into one local commit:
   ```bash
   git reset --soft "$REPAIR_BASE"
   git add -A
   git commit -m "fix(review): address {N} review threads"
   ```
4. **Verification**: Inspect project configuration and execute dynamic checks (e.g. `npx tsc --noEmit`, `npm test`, `cargo check`, `ruff check .`, `go build ./...`). If checks fail, fix the error and amend commit.

---

## Phase 3: Reply Drafting (Orchestrator Inline)

Read `references/reply-templates.md` for bilingual examples, tone, and the AI disclosure footer.
- Use `git diff origin/{branch}...HEAD` as ground truth (describe what actually changed, not planned changes).
- Classify into: `valid-fix (succeeded)`, `valid-fix (failed/deferred)`, `valid-nofix`, `invalid`.

### Checkpoint 2: User Review
Present drafted replies. User can approve all, edit individual replies, or toggle the AI footer.

---

## Phase 4: Post & Push

1. Post replies to GitHub:
   ```bash
   gh api -X POST repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies -f body='<reply>'
   ```
2. Resolve threads via helper script:
   ```bash
   bash skills/pr-review-handler/scripts/resolve-threads.sh {pr_number} {resolved_comment_ids...}
   ```
3. Push to remote:
   ```bash
   git push origin HEAD
   ```

---

## Phase 5: Report

Output final metrics:
```text
✅ Triage: N/N threads processed
✅ Fixes: M/K valid-fix threads applied and pushed
   ❌ Failed: {thread} — {reason}
   ⚠️ regression-gap: {thread} — behavior change noted (if any)
✅ Replies: P/P threads posted
✅ Resolved: Q/P conversations resolved
```

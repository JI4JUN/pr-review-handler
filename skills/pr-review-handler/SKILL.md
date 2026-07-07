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
---

# PR Review Handler

Orchestrate specialized agents to process PR review comments:

```
Phase 0: Setup → Phase 1: Triage (parallel) → Phase 2: Fix (serial)
         → Phase 3: Reply → Phase 4: Post & Push → Phase 5: Report
```

Checkpoints: after Phase 1 (user confirms verdicts) and after Phase 3 (user approves replies).

## Agent Definitions

### Roles

| Role | Responsibility | Parallelizable |
|------|---------------|----------------|
| Triage Agent | Verify comment validity, classify verdict | ✅ Yes (read-only) |
| Implementation Agent | Apply minimal code fix for one thread | ❌ No (writes files) |
| Reply drafting | Orchestrator drafts inline (no separate agent) | N/A |

### Platform mapping

Agent specs live in `agents/` relative to this skill (`agents/triage-agent.md`, `agents/implementation-agent.md`). Every platform uses the same specs — what differs is the dispatch mechanism.

| Platform | Dispatch mechanism |
|----------|-------------------|
| Pi | `pr-review-handler.triage` / `pr-review-handler.implementation` project agents via `subagent` tool (auto-created in Phase 0), else inline |
| Claude Code | Task tool |
| Cursor | background agent |
| Gemini CLI / OpenCode / others | native subtask mechanism if available |
| No subtask available | inline (read the spec, execute the steps yourself) |

**Dispatch pattern**: read the relevant agent spec, embed its instructions into the task prompt along with the thread-specific input data (thread info for triage, verdict data for implementation), and launch one subtask per thread. Triage is read-only so subtasks run in parallel; implementation writes files so it runs serially.

**Pi dispatch**: Pi uses the `subagent` tool (from the optional `pi-subagents` package) with project-level agents registered in `.agents/pr-review-handler/`. Phase 0 auto-creates these from templates shipped in the skill package. Once registered, dispatch with agent name `pr-review-handler.triage` (Phase 1) or `pr-review-handler.implementation` (Phase 2) — the task prompt contains only the input data, since the agent carries its own system prompt. If `pi-subagents` is not installed (no `subagent` tool), fall back to inline execution.

**Inline fallback**: if no `subagent` tool (Pi) or no subtask mechanism (other platforms), read each spec and execute its steps yourself, one thread at a time.

## Phase 0: Setup

### Identify the PR

```bash
gh pr list --state open --json number,title,url,headRefName
```

Match against current branch (`git branch --show-current`). Use user-supplied PR if specified. Checkout PR branch if needed.

```bash
git fetch origin
```

### Fetch unresolved review threads

**Preferred: GraphQL** (filters resolved threads):

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 10) {
              nodes {
                databaseId
                body
                path
                line
                author { login }
              }
            }
          }
        }
      }
    }
  }
' -f owner={owner} -f repo={repo} -F pr={pr_number}
```

Filter `isResolved: false`. Include full thread (not just top-level) — follow-up replies often contain the real concern.

**Deduplicate threads before triage.** Automated reviewers (React Doctor, claude[bot], etc.) often post the same concern multiple times across different reviews, and human reviewers may re-comment after a push. Before dispatching Triage Agents, cluster threads by `(path, line)` and collapse those whose top-level comment bodies share the same core concern (match on the first sentence or the rule identifier like `react-doctor/prefer-useReducer`). Keep one representative thread per cluster, but record all `databaseId`s — Phase 4 posts the reply to **every** original thread in the cluster so no reviewer comment is left unanswered. Report the dedup result to the user (e.g. "8 threads → 3 unique concerns") so the Checkpoint 1 table stays readable.

**Fallback: REST** (when GraphQL unavailable):

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq 'group_by([.path, (.original_commit_id // "HEAD")]) | map({
    thread_id: .[0].id, path: .[0].path,
    comments: [.[] | {id, body, user: .user.login, line, in_reply_to_id}]
  })'
```

REST cannot detect resolved threads — ask user to confirm which threads need attention.

### Fetch review-level feedback

Review-level feedback (summary comments without line references) is separate from thread comments. Always fetch:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --jq 'sort_by(.submitted_at) | reverse | .[:5] | .[] | {id, state, user: .user.login, body}'
```

Present any non-empty review bodies in Checkpoint 1 (Phase 1) as a
separate **Review-level feedback** section. These are summary comments
without line references, so they do not go through the Triage Agent
automatically — the user decides how to handle each one (ignore / reply
only / needs code change). If the user marks one as needing a code change,
convert it into an Implementation task with `path: <overall PR>` and no
specific line; the Implementation Agent then works from the review body
text and the PR diff.

### Fetch PR diff

Triage needs to see what the PR actually changed — without it, the agent cannot
distinguish a problem the PR introduced from one that already existed in the
base branch.

```bash
gh pr diff {pr_number} > /tmp/pr-{pr_number}.diff
```

Cache the diff to a temp file. When dispatching each Triage Agent in Phase 1,
pass only the hunks relevant to that thread's `path` as `pr_diff_context`. If
the total diff is small (< 500 lines), pass the full diff to every agent for
broader context.

### Ensure project agents (Pi only)

If you have a `subagent` tool (Pi with pi-subagents installed), ensure project agents are registered before Phase 1 dispatch.

Check that both project agent files exist:

```bash
test -f .agents/pr-review-handler/triage.md && test -f .agents/pr-review-handler/implementation.md
```

- **Both exist** → continue to Phase 1 (subagent dispatch)
- **Either missing** → notify user: "Project agents not found at `.agents/pr-review-handler/`. Run `/pi-pr-review-handler-sync` to sync them. Continuing inline for this run." → fall back to inline execution (read `agents/triage-agent.md` spec and execute inline)

Do NOT auto-cp or auto-sync. Syncing is the user's responsibility via the `/pi-pr-review-handler-sync` command (a Pi extension bundled with the `@trashcodermaker/pi-pr-review-handler` package).

## Phase 1: Triage (parallel dispatch)

### Dispatch strategy

Triage is read-only — safe to parallelize.

- **Pi with `subagent` tool**: Use `pr-review-handler.triage` project agent. Spawn one per thread in PARALLEL mode. Pass `acceptance: { level: "none", reason: "triage is read-only verdict classification — no files changed, no tests, no commands; pr-review-handler manages its own output format" }`. Task prompt = input data ONLY (agent carries its own system prompt).
  - **Why `level: "none"`**: pi-subagents infers `checked` for any task whose text contains words like "fix" (reviewer comments often do), and `checked` requires non-empty `tests-added` + `commands-run` evidence that a read-only triage agent cannot produce. A bare `acceptance: "attested"` is silently ignored — an explicit level can only *raise* above the inferred level, never lower it. Only `{ level: "none", reason }` disables the gate.
- **Other platforms with subtask tool** (Task tool / background agent): embed `agents/triage-agent.md` spec into the task prompt + input data. Spawn one subtask per thread in parallel.
- **No subtask mechanism**: run inline, one thread at a time.

Thread-count rules:

- **≥3 threads + subtask available** → parallel, one agent per thread
- **≤2 threads** → inline regardless (overhead not worth it)
- **>15 threads** → batch by file path, 8–10 threads per batch, dispatch one batch at a time (serial batches, parallel within each batch). Collect verdicts across batches before Checkpoint 1.

### Dispatch

For each unresolved thread, dispatch the Triage Agent with this task data:

```
thread_id: <comment ID>
path: <file:line>
reviewer: <reviewer username>
comments:
  - <top-level comment text>
  - <reply 1, if any>
  - <reply 2, if any>
pr_diff_context: <diff hunks for {path} from /tmp/pr-{pr_number}.diff, or full diff if PR is small>
```

Embed the Triage Agent spec (`agents/triage-agent.md`) into the task prompt so the subtask has the full role instructions and output format, then append the thread-specific data above. Collect structured verdicts from all agents.

### Checkpoint 1: User confirmation

Present thread verdicts as a summary table:

| # | File:Line | Reviewer | Summary | Verdict | Affected Files |
|---|-----------|----------|---------|---------|----------------|
| 1 | src/auth/login.ts:42 | alice | Missing null check | valid-fix | login.ts, types.ts |
| 2 | src/ui/Button.tsx:18 | bob | Rename for clarity | valid-fix | Button.tsx |
| 3 | src/api/handler.ts:99 | alice | Add rate limiting | invalid | — |

Then present the **Review-level feedback** section (summary comments
without line references, fetched in Phase 0):

| # | Reviewer | State | Body (excerpt) |
|---|----------|-------|----------------|
| R1 | alice | CHANGES_REQUESTED | "Overall solid, but the auth module needs a refactor — see thread #1" |
| R2 | bob | COMMENTED | "Please add tests for the token expiry edge case" |

For each review-level item, ask the user to choose:

- **Ignore** — no action needed (e.g. summary of already-addressed threads)
- **Reply only** — draft a clarification in Phase 3, no code change
- **Needs code change** — convert to an Implementation task: `path: <overall PR>`, no line, `summary: <review body>`, `affected_files: <user-specified or all PR files>`, `suggested_fix: <user describes>`. Dispatch in Phase 2.

User can adjust thread verdicts or skip threads. Proceed with confirmed plan.

### Quick exits

- **All invalid**: skip Phase 2, go to Phase 3 for reply drafting
- **All valid-nofix**: skip Phase 2, go to Phase 3
- **User rejects all**: end workflow

## Phase 2: Implementation (serial dispatch)

### Fix ordering

1. **User-specified order** from Phase 1 confirmation
2. **Otherwise dependency-first**: types → implementation → callers → tests
3. **Same level**: PR order

### Dispatch

For each `valid-fix` thread, dispatch the Implementation Agent with this task data:

```
thread_id: <comment ID>
path: <file:line>
reviewer: <name>
summary: <what the reviewer wants>
verdict: valid-fix
affected_files:
  - <file1>
  - <file2>
suggested_fix: <what to change>
prior_changes: <list of previous fixes in this PR, if any>
```

Embed the Implementation Agent spec (`agents/implementation-agent.md`) into the task prompt so the subtask has the full role instructions, then append the verdict data above.

**Pi dispatch**: Use `pr-review-handler.implementation` project agent, SINGLE mode — one subtask per fix, awaited in turn (serial). Pass `acceptance: { level: "none", reason: "review fixes are often small and add no tests; the implementation agent runs no commands by design; the orchestrator runs its own project-type-detected verification after all fixes" }`. Task prompt = verdict data ONLY. Pass `prior_changes` by collecting each completed subtask's output and appending it to the next subtask's input.

- **Why `level: "none"`**: the implementation task contains "fix", so pi-subagents infers `checked`, which requires non-empty `tests-added` + `commands-run` evidence. Review fixes usually add no tests and the agent runs no commands (no tsc/lint — the orchestrator does), so `checked` always rejects. `acceptance: "attested"` does NOT work — an explicit level cannot lower below the inferred `checked`; only `{ level: "none", reason }` disables the gate.

**Other platforms**: embed `agents/implementation-agent.md` spec into the task prompt + verdict data, dispatch via your subtask tool (serial).

**No subtask mechanism**: execute the Implementation Agent spec inline, one thread at a time.

### After all fixes

Once all Implementation Agents have completed, commit all changes as one:

```bash
git add -A
git commit -m "fix(review): address {N} review threads"
```

If no changes were made (all agents skipped), skip to Phase 3.

Then run the project's type checker or equivalent verification. Detect the
project type and run the matching command — do not assume TypeScript:

| Project marker | Command |
| --- | --- |
| `tsconfig.json` | `npx tsc --noEmit` |
| `package.json` (no tsconfig) | `npm run lint --if-present` and `npm test --if-present` |
| `pyproject.toml` / `setup.py` | `ruff check .` then `mypy .` (if configured) |
| `go.mod` | `go build ./...` |
| `Cargo.toml` | `cargo check` |
| none recognized | skip; tell user to run the project's check manually |

If the check fails:

- `git reset --soft HEAD~1` to unstage the commit (keep changes in working tree)
- Identify the failing fix (check error file paths against `affected_files` from triage verdicts)
- Fix the error
- Re-commit
- Re-run the check until clean

Also check:

- Orphan references to removed/renamed symbols (`grep -r`)
- Translation keys in all message files if `t()` calls were added

### Never push during this phase

The commit stays local. Push happens once in Phase 4.

## Phase 3: Reply (orchestrator drafts inline)

The orchestrator drafts replies directly — no separate agent needed. This phase has full access to all pipeline context.

Gather:

- **Original thread data**: all comments from Phase 0
- **Triage verdicts**: all structured verdicts from Phase 1
- **Actual changes**: `git diff origin/{branch}...HEAD`
- **Failure records**: which fixes failed and why (from Phase 2)

Draft one reply per thread, using `git diff origin/{branch}...HEAD` as ground truth (not planned changes):

**valid-fix (succeeded)**: describe what was changed, referencing the reviewer's concern. If the fix differs from what the reviewer suggested, explain why.

Examples:

> Good (EN): "Added the null check at line 42 as you suggested — `user` can indeed be undefined when the session expires."
>
> Good (中文): "已在 42 行加了空值判断，session 过期时 `user` 确实可能为 undefined。"
>
> Good (EN, diverged from suggestion): "Your point about rate limiting is valid. Instead of a fixed window I used a token bucket in `rateLimit.ts` — it handles burst traffic better and the existing tests cover it."

**valid-fix (failed)**: acknowledge the concern was valid. Explain why the fix couldn't be applied (type conflict, dependency issue). Suggest next steps if possible ("will address in a follow-up PR"). Don't be apologetic — just factual.

Examples:

> Good (EN): "You're right that this should be typed more strictly, but the `User` interface is shared with the legacy auth module which expects `any`. I'll extract a `StrictUser` type in a follow-up PR to avoid breaking that module here."
>
> Good (中文): "这里确实该用更严格的类型，但 `User` 接口被旧 auth 模块共用且依赖 `any`。我会在后续 PR 里拆出 `StrictUser` 类型，避免这里改动波及该模块。"

**valid-nofix**: acknowledge the concern is valid. Explain why no code change is needed. Provide clarification if the reviewer misunderstood the code.

Examples:

> Good (EN): "Fair point on the naming — `handleX` is a bit vague. It's part of the public API documented in `docs/api.md`, so renaming would be a breaking change. I'll add a deprecation alias in the next major."
>
> Good (中文): "命名确实不够清晰，不过 `handleX` 是 `docs/api.md` 里记录的公开 API，重命名属于破坏性变更，下个大版本会加弃用别名。"

**invalid**: explain clearly why the premise doesn't apply. Reference specific code that already handles the concern. Acknowledge the reviewer's intent ("I see why you'd think X, but..."). Be respectful but direct — don't hedge if the concern is genuinely wrong.

Examples:

> Good (EN): "I see why you'd think the count could overflow here, but `items` is already capped at `MAX_ITEMS` (line 15) before this loop runs, so `i` stays well within `Number.MAX_SAFE_INTEGER`."
>
> Good (中文): "能理解你担心这里 count 溢出，但进入循环前 `items` 已在 15 行被 `MAX_ITEMS` 截断，`i` 始终远小于 `Number.MAX_SAFE_INTEGER`。"

### Reply guidelines

- Match the reviewer's language (Chinese reviewer → Chinese reply)
- Match tone (casual → casual, formal → formal)
- Be concise: 1-3 sentences ideal
- Don't over-explain — reviewer is a peer, trust they understand code
- Never be defensive — state facts, acknowledge intent

### Checkpoint 2: User review

Present all reply drafts. User can:

- Approve all
- Edit individual replies
- Reject specific replies
- Add context to replies

## Phase 4: Post & Push

Post approved replies. The reply endpoint requires `-X POST` and the PR number in the path:

```bash
gh api -X POST repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies \
  -f body='The response text'
```

Reply to the top-level comment of each thread (the one with `databaseId`, not a reply). The `{pr_number}` is the PR number (e.g. `561`), and `{comment_id}` is the `databaseId` from Phase 0. Note: the path is `pulls/{pr_number}/comments/...`, **not** `pulls/comments/...` — the latter returns 404.

### Resolve conversations

After posting replies, automatically resolve every thread that received a reply (regardless of verdict — the reviewer can reopen if needed). This simulates clicking the "Resolve conversation" button on the PR page.

GitHub's REST API cannot resolve threads; use the GraphQL API.

1. Fetch all review thread node IDs (the thread `id` is NOT the same as a comment `databaseId`):

```bash
gh api graphql -f query='query($owner:String!,$name:String!,$pr:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{
          id
          isResolved
          comments(first:100){nodes{databaseId}}
        }
      }
    }
  }
}' -F owner=$OWNER -F name=$REPO -F pr=$PR_NUMBER
```

1. For each thread that received a reply, match by the original comment's `databaseId` (recorded in Phase 0). If `isResolved == false`, resolve it:

```bash
gh api graphql -f query='mutation($id:ID!){
  resolveReviewThread(input:{threadId:$id}){
    thread{isResolved}
  }
}' -F id=$THREAD_ID
```

Skip threads already resolved. Record each resolve outcome (thread id + success/skip) for the Phase 5 report.

Push the commit:

```bash
git push origin HEAD
```

Ask user if they want to:

- **Request re-review**: `gh api repos/{owner}/{repo}/pulls/{pr_number}/requested_reviewers -f reviewers='["username"]'`
- **Dismiss resolved reviews**: `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews/{review_id}/dismissals -f message='Addressed'`

## Phase 5: Report

Output final summary:

```
✅ Triage: N/N threads processed
✅ Fixes: M/K valid-fix threads applied (committed locally, pushed)
   ❌ Failed: {thread} — {reason}
✅ Replies: P/P threads drafted and posted
✅ Resolved: Q/P conversations resolved (R skipped — already resolved)
```

## Pipeline Failure Rules

| Scenario | Action |
|----------|--------|
| Triage: all agents fail | Stop pipeline. Report to user. Cannot proceed without verdicts. |
| Triage: some agents fail | Skip failed threads. Continue with successful verdicts. Note in final report. |
| Implementation: all agents fail | Skip Phase 2. Phase 3 only drafts replies for invalid/nofix threads. |
| Implementation: some agents fail | Skip failed fixes. Mark in failure records for Phase 3. |
| Reply drafting fails | Should not happen — orchestrator drafts inline. |

## Error Handling

| Error | Action |
|-------|--------|
| `gh` not installed / not authenticated | Tell user to install GitHub CLI and `gh auth login` |
| API rate limit | Wait for `X-RateLimit-Reset`, retry |
| PR closed/merged | Warn user — replies have no effect |
| GraphQL unsupported | Fall back to REST with resolved-thread caveat |
| Type check fails after all fixes | Fix before posting replies |

## Key Principles

These apply across all agents and phases:

- **Trace all references after removals.** Deleting a function, type field, or import creates orphans in callers, tests, and type usages. Search the entire codebase for the symbol. This is the #1 cause of "fixed the review but broke the build."
- **Don't guess on ambiguous threads.** If a concern is partially valid or unclear, mark for user decision in Checkpoint 1. A wrong reply is worse than no reply.

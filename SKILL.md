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

Each role maps to a different agent depending on the platform. Agent specs for reference are in `agents/` relative to this skill.

| Role | Pi | Claude Code | Cursor | No-agent fallback |
|------|-----|-------------|--------|-------------------|
| Triage | `pr-review.triage` | Task tool | background agent | inline (read spec, execute yourself) |
| Implementation | `pr-review.implementation` | Task tool | background agent | inline (read spec, execute yourself) |
| Reply | inline (orchestrator) | inline | inline | inline |

**Pi users**: runtime agents are registered in `.agents/agents/pr-review/` at the project root. They include full system prompts, tool constraints, and output format — dispatch with task prompt containing only the input data (thread info, verdict data).

**Other platforms**: read the agent specs in `agents/` relative to this skill (`agents/triage-agent.md`, `agents/implementation-agent.md`), embed the instructions into the task prompt, and dispatch using your available subtask mechanism. If no subtask mechanism exists, execute inline.

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

**Fallback: REST** (when GraphQL unavailable):

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq 'group_by(.path, .original_commit_id) | map({
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

Include any non-empty review bodies alongside the thread data when presenting to the user in Phase 2.

## Phase 1: Triage (parallel dispatch)

### Dispatch strategy

Triage is read-only — safe to parallelize.

- **≥3 threads + parallel capability**: spawn one Triage Agent per thread simultaneously
- **≤2 threads or no parallel capability**: run inline, same logic

If unsure about parallel capability, default to inline.

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
```

The agent already has its role instructions and output format built in. Do not embed role instructions in the task prompt — only pass the thread-specific data above.

Collect structured verdicts from all agents.

### Checkpoint 1: User confirmation

Present verdicts as a summary table:

| # | File:Line | Reviewer | Summary | Verdict | Affected Files |
|---|-----------|----------|---------|---------|----------------|
| 1 | src/auth/login.ts:42 | alice | Missing null check | valid-fix | login.ts, types.ts |
| 2 | src/ui/Button.tsx:18 | bob | Rename for clarity | valid-fix | Button.tsx |
| 3 | src/api/handler.ts:99 | alice | Add rate limiting | invalid | — |

User can adjust verdicts or skip threads. Proceed with confirmed plan.

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

The agent already has its role instructions and output format built in. Pass only the verdict data above.

After each agent completes:

```bash
git add -A
git commit -m "fix(review): {thread summary}"
```

If commit is empty (agent made no changes), skip.

### After all fixes

```bash
npx tsc --noEmit
```

If tsc fails:

- Identify which commit introduced the error (`git bisect` or check error file paths)
- `git revert --no-commit {commit}` → fix the error → recommit
- Re-run tsc until clean

Also check:

- Orphan references to removed/renamed symbols (`grep -r`)
- Translation keys in all message files if `t()` calls were added

### Never push during this phase

All commits stay local. Push happens once in Phase 4.

## Phase 3: Reply (orchestrator drafts inline)

The orchestrator drafts replies directly — no separate agent needed. This phase has full access to all pipeline context.

Gather:

- **Original thread data**: all comments from Phase 0
- **Triage verdicts**: all structured verdicts from Phase 1
- **Actual changes**: `git diff origin/{branch}...HEAD`
- **Failure records**: which fixes failed and why (from Phase 2)

Draft one reply per thread, using `git diff origin/{branch}...HEAD` as ground truth (not planned changes):

**valid-fix (succeeded)**: describe what was changed, referencing the reviewer's concern. If the fix differs from what the reviewer suggested, explain why.

**valid-fix (failed)**: acknowledge the concern was valid. Explain why the fix couldn't be applied (type conflict, dependency issue). Suggest next steps if possible ("will address in a follow-up PR"). Don't be apologetic — just factual.

**valid-nofix**: acknowledge the concern is valid. Explain why no code change is needed. Provide clarification if the reviewer misunderstood the code.

**invalid**: explain clearly why the premise doesn't apply. Reference specific code that already handles the concern. Acknowledge the reviewer's intent ("I see why you'd think X, but..."). Be respectful but direct — don't hedge if the concern is genuinely wrong.

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

Post approved replies:

```bash
gh api repos/{owner}/{repo}/pulls/comments/{comment_id}/replies \
  -f body='The response text'
```

Reply to the top-level comment of each thread (the one with `databaseId`, not a reply).

Push all commits:

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
| tsc fails after all fixes | Fix before posting replies |

## Key Principles

These apply across all agents and phases:

- **Trace all references after removals.** Deleting a function, type field, or import creates orphans in callers, tests, and type usages. Search the entire codebase for the symbol. This is the #1 cause of "fixed the review but broke the build."
- **Don't guess on ambiguous threads.** If a concern is partially valid or unclear, mark for user decision in Checkpoint 1. A wrong reply is worse than no reply.

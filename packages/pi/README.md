# @trashcodermaker/pi-pr-review-handler

> Pi package — systematically process GitHub PR review comments: triage, fix, reply.

[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pi-pr-review-handler?style=flat-square)](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](https://github.com/JI4JUN/pr-review-handler/blob/main/LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/JI4JUN/pr-review-handler/publish.yml?style=flat-square&label=Build)](https://github.com/JI4JUN/pr-review-handler/actions)

This is the **Pi-specific package**. Pi auto-discovers the skill after install.

Looking for the **generic package** for other agent harnesses (Claude Code, Cursor, Gemini CLI, OpenCode, …)? See [`@trashcodermaker/pr-review-handler`](https://www.npmjs.com/package/@trashcodermaker/pr-review-handler).

## Overview

Code review is part of every healthy PR workflow, but turning review threads into actual fixes and thoughtful replies can be tedious and error-prone.

**PR Review Handler** automates that workflow. It fetches unresolved GitHub PR review threads, evaluates each comment for validity, applies minimal code fixes, drafts replies that match the reviewer's language and tone, and optionally pushes changes and requests re-review.

## Install

```bash
pi install npm:@trashcodermaker/pi-pr-review-handler
```

Pi auto-discovers the skill under `skills/pr-review-handler/`.

### Syncing project agents

Project agents (`.agents/pr-review-handler/{triage,implementation}.md`) are generated artifacts synced from this package. Use the `/pi-pr-review-handler-sync` command to sync:

- **First run**: creates `.agents/pr-review-handler/` with latest templates
- **After upgrade**: overwrites with latest templates (also cleans stale `.agents/agents/pr-review-handler/` from v1.2.3)
- **Does NOT touch** `.agents/agents/pr-review/` (manual, if present)

The command is a Pi extension bundled with this package — `pi install` auto-loads it. No SKILL.md auto-cp; syncing is explicit and user-triggered.

## What you get

```
node_modules/@trashcodermaker/pi-pr-review-handler/
└── skills/
    └── pi-pr-review-handler/
        ├── SKILL.md              # the skill instructions
        └── agents/
            ├── triage-agent.md          # spec (inline mode)
            ├── implementation-agent.md  # spec
            └── pr-review-handler/       # project agent templates (pi-subagents)
                ├── triage.md
                └── implementation.md
```

## Recommended companion tools

### pi-subagents (recommended)

Pi has no native subtask mechanism. With [`pi-subagents`](https://github.com/nicobailon/pi-subagents) installed, the skill auto-creates project agents and dispatches them via the `subagent` tool (parallel triage, serial implementation). Without it, runs inline.

```bash
pi install npm:pi-subagents
```

The skill auto-creates project agents (`pr-review-handler.triage`, `pr-review-handler.implementation`) in Phase 0 and dispatches them via the `subagent` tool.

### CodeGraph (optional, enhances agent quality)

The Triage and Implementation agents reference `mcp:codegraph` in their tool list. [CodeGraph](https://github.com/colbymchenry/codegraph) is a semantic code intelligence MCP server — symbol lookup, call-edge traversal, and blast-radius analysis beyond `grep`.

**Why**: triage uses it to find all callers accurately (`affected_files`); implementation traces references that grep might miss.

**Install**: see the [CodeGraph repo](https://github.com/colbymchenry/codegraph). `codegraph install` auto-configures Claude Code, Cursor, Codex, etc. — for Pi, add the CodeGraph MCP server to your Pi MCP configuration manually. Falls back to `grep`/`find` if not installed.

## How it works

The handler runs a multi-phase pipeline. Each phase has a clear responsibility, and the flow stops at checkpoints where human confirmation is requested.

```
Phase 0: Setup
Phase 1: Triage        ← parallel, read-only
Phase 2: Fix           ← serial, minimal changes
Phase 3: Reply         ← orchestrator drafts inline
Phase 4: Post & Push
Phase 5: Report
```

### Phase 0: Setup

Identifies the target PR from the current branch or an explicit PR link, fetches unresolved review threads, and fetches review-level feedback. This phase prepares everything needed for triage without modifying code.

### Phase 1: Triage

Reads code, PR diff context, and each review thread; **verifies the claim** (`confirmed` / `failed` / `insufficient` + `code_path` / `in_pr_diff`); classifies as:

- `valid-fix` — claim confirmed with `code_path`; needs code change (includes **fix contract**: acceptance + out_of_scope)
- `valid-nofix` — merit, but no code change on this PR
- `invalid` — claim failed, already handled, or harmful fix

`valid-fix` is gated on confirmed + code_path. Unclear → `insufficient` + Need from user at Checkpoint 1.

With [`pi-subagents`](https://github.com/nicobailon/pi-subagents) installed, triage runs in parallel — one `pr-review-handler.triage` project agent per thread. Without it, runs inline.

> [!TIP]
> Triage is intentionally conservative. If a comment is unclear, set `claim_check: insufficient` and `invalid` with reason `unclear — needs human review`.

### Phase 2: Fix

For each `valid-fix` thread, the implementation agent applies a **minimal fix** against the triage fix contract (acceptance only; never out_of_scope). Traces references first; updates callers/tests on signature changes.

All fixes are committed as a single commit, but **never pushed** during this phase.

After all fixes, the pipeline runs the project's type checker or equivalent verification (auto-detected: `tsc` for TypeScript, `ruff`/`mypy` for Python, `go build` for Go, `cargo check` for Rust, etc.). If it fails, the pipeline does `git reset --soft` to unstage the commit, fixes the issue, and recommits before continuing.

### Phase 3: Reply

The orchestrator drafts one reply per thread based on:

- Original thread data
- Triage verdicts
- Actual diff: `git diff origin/{branch}...HEAD`
- Failure records from Phase 2

Replies match language/tone, stay concise, never defensive. Default **AI-assisted** footer (strippable at Checkpoint 2). Out-of-PR nits use a stock scope phrase.

### Phase 4: Post & Push

Approved replies are posted to GitHub. Every thread that received a reply is then auto-resolved via the GraphQL `resolveReviewThread` mutation (simulates clicking "Resolve conversation" on the PR page). Finally, the single review-fix commit is pushed.

Optionally, the handler can also:

- Request re-review from the original reviewers
- Dismiss resolved review threads with an "Addressed" message

### Phase 5: Report

A concise summary is printed at the end:

```
✅ Triage: N/N threads processed
✅ Fixes: M/K valid-fix threads applied (committed locally, pushed)
   ❌ Failed: {thread} — {reason}
✅ Replies: P/P threads drafted and posted
✅ Resolved: Q/P conversations resolved (R skipped — already resolved)
```

## Usage

Once installed, invoke it from your Pi session with natural language:

- "帮我处理这个 PR 的 review：<https://github.com/owner/repo/pull/123>"
- "回复 reviewer 的评论"
- "看看 PR 里那些 unresolved threads"
- "review 提的问题要修一下"
- "CI 过了，但 review 还没回"
- "handle the reviews on my PR"
- "someone left comments on my PR"

Or trigger the skill directly:

```
/skill:pr-review-handler
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- A Git working tree clean enough to create review-fix commits
- A project with a type checker or linter (TypeScript, Python, Go, Rust, etc.) for the post-fix verification — auto-detected, skipped if none recognized

## Supported platforms

| Platform | Support |
| --- | --- |
| Pi | ✅ This package. Uses `pr-review-handler.triage` / `pr-review-handler.implementation` project agents via [`pi-subagents`](https://github.com/nicobailon/pi-subagents) (auto-created in Phase 0); inline fallback if not installed. |
| Other harnesses (Claude Code, Cursor, Gemini CLI, OpenCode, …) | ✅ Use [`@trashcodermaker/pr-review-handler`](https://www.npmjs.com/package/@trashcodermaker/pr-review-handler) instead |

## License

MIT

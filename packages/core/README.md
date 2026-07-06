# @trashcodermaker/pr-review-handler

> Systematically process GitHub PR review comments: triage for validity, fix code, and post replies.

[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pr-review-handler?style=flat-square)](https://www.npmjs.com/package/@trashcodermaker/pr-review-handler)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](https://github.com/JI4JUN/pr-review-handler/blob/main/LICENSE)
[![Build](https://img.shields.io/github/actions/workflow/status/JI4JUN/pr-review-handler/publish.yml?style=flat-square&label=Build)](https://github.com/JI4JUN/pr-review-handler/actions)

This is the **generic npm package** — an agent skill usable from any agent harness: Pi, Claude Code, Cursor, Gemini CLI, OpenCode, and others.

Looking for the **Pi-specific package**? See [`@trashcodermaker/pi-pr-review-handler`](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler).

## Overview

Code review is part of every healthy PR workflow, but turning review threads into actual fixes and thoughtful replies can be tedious and error-prone.

**PR Review Handler** automates that workflow. It fetches unresolved GitHub PR review threads, evaluates each comment for validity, applies minimal code fixes, drafts replies that match the reviewer's language and tone, and optionally pushes changes and requests re-review.

The skill is agent-agnostic: it ships agent specs in `agents/` and works with any agent harness that can run subtasks (Pi, Claude Code, Cursor, Gemini CLI, OpenCode, …) or inline as a fallback.

## Install

```bash
npm install @trashcodermaker/pr-review-handler
```

## What you get

```
node_modules/@trashcodermaker/pr-review-handler/
└── skills/
    └── pr-review-handler/
        ├── SKILL.md              # the skill instructions
        └── agents/
            ├── triage-agent.md          # spec (inline mode)
            ├── implementation-agent.md  # spec
            └── pr-review-handler/       # project agent templates (pi-subagents)
                ├── triage.md
                └── implementation.md
```

Point your agent at `node_modules/@trashcodermaker/pr-review-handler/skills/pr-review-handler/SKILL.md`, or copy the `skills/pr-review-handler/` directory into your agent's skill discovery path.

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

Reads the referenced code and each review thread, then classifies every comment as:

- `valid-fix` — a real issue that requires code changes
- `valid-nofix` — the concern is valid, but no code change is needed
- `invalid` — the premise doesn't apply to current code, or the suggested fix would be harmful

On Pi with pi-subagents, triage runs in parallel via `pr-review-handler.triage` project agents. On other harnesses (Claude Code Task tool, Cursor background agent), runs via the harness's subtask mechanism. Falls back to inline if no subtask mechanism.

> [!TIP]
> Triage is intentionally conservative. If a comment is unclear, mark it `invalid` with the reason `unclear — needs human review`.

### Phase 2: Fix

For each `valid-fix` thread, a specialized implementation agent applies the smallest possible change that satisfies the review. The agent traces references first, updates callers and tests when signatures change, and avoids unrelated cleanup or refactors.

All fixes are committed as a single commit, but **never pushed** during this phase.

After all fixes, the pipeline runs the project's type checker or equivalent verification (auto-detected: `tsc` for TypeScript, `ruff`/`mypy` for Python, `go build` for Go, `cargo check` for Rust, etc.). If it fails, the pipeline does `git reset --soft` to unstage the commit, fixes the issue, and recommits before continuing.

### Phase 3: Reply

The orchestrator drafts one reply per thread based on:

- Original thread data
- Triage verdicts
- Actual diff: `git diff origin/{branch}...HEAD`
- Failure records from Phase 2

Replies are matched to the reviewer's language and tone, kept concise, and never defensive.

### Phase 4: Post & Push

Approved replies are posted to GitHub, and the single review-fix commit is pushed.

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
```

## Usage

When installed as a skill, invoke it from your agent with natural language. Examples:

- "帮我处理这个 PR 的 review：<https://github.com/owner/repo/pull/123>"
- "回复 reviewer 的评论"
- "看看 PR 里那些 unresolved threads"
- "review 提的问题要修一下"
- "CI 过了，但 review 还没回"
- "someone left comments on my PR"
- "帮我看看那些人提的意见"

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- A Git working tree clean enough to create review-fix commits
- A project with a type checker or linter (TypeScript, Python, Go, Rust, etc.) for the post-fix verification — auto-detected, skipped if none recognized

## Supported platforms

| Platform | Support |
| --- | --- |
| npm / Node.js | ✅ Install `@trashcodermaker/pr-review-handler` as a published package |
| Pi | ✅ Install [`@trashcodermaker/pi-pr-review-handler`](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler) via `pi install`. With [`pi-subagents`](https://github.com/nicobailon/pi-subagents), uses `pr-review-handler.triage`/`pr-review-handler.implementation` project agents (auto-created); otherwise inline. |
| Claude Code | ✅ Task-based agent dispatch, or `npx skills add JI4JUN/pr-review-handler --skill pr-review-handler` |
| Cursor | ✅ Background agent dispatch |
| Gemini CLI / OpenCode / others | ✅ Native subtask mechanism, or inline fallback |

## License

MIT

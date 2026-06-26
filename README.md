# PR Review Handler

> Systematically process GitHub PR review comments: triage for validity, fix code, and post replies.

[![Build Status](https://img.shields.io/github/actions/workflow/status/JI4JUN/pr-review-handler/ci.yml?style=flat-square&label=Build)](https://github.com/JI4JUN/pr-review-handler/actions)
[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pi-pr-review-handler?style=flat-square)](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

⭐ If you like this project, star it on GitHub — it helps a lot!

[Overview](#overview) • [Getting started](#getting-started) • [How it works](#how-it-works) • [Usage](#usage) • [Requirements](#requirements) • [Supported platforms](#supported-platforms)

[中文版](./README.zh.md)

## Overview

Code review is part of every healthy PR workflow, but turning review threads into actual fixes and thoughtful replies can be tedious and error-prone.

**PR Review Handler** automates that workflow. It fetches unresolved GitHub PR review threads, evaluates each comment for validity, applies minimal code fixes, drafts replies that match the reviewer's language and tone, and optionally pushes changes and requests re-review.

It can be used as an npm package, a Pi package, a Pi skill, or embedded into other agent environments. The project ships agent specifications in `agents/` so each platform can run the pipeline with its own task/dispatch mechanism.

## Getting started

### Install as an npm package

```bash
npm install @trashcodermaker/pi-pr-review-handler
```

### Install as a Pi package

```bash
pi install @trashcodermaker/pi-pr-review-handler
```

### Install from skill.sh

```bash
npx skills add JI4JUN/pr-review-handler
```

### From source

```bash
git clone https://github.com/JI4JUN/pr-review-handler.git
cd pr-review-handler
npm install
```

> [!IMPORTANT]
> Ensure GitHub CLI (`gh`) is installed and authenticated before using this skill or package. Most commands depend on it to read PR data and post replies.

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

If there are many threads and the platform supports parallel agents, triage runs in parallel for speed.

> [!TIP]
> Triage is intentionally conservative. If a comment is unclear, mark it `invalid` with the reason `unclear — needs human review`.

### Phase 2: Fix

For each `valid-fix` thread, a specialized implementation agent applies the smallest possible change that satisfies the review. The agent traces references first, updates callers and tests when signatures change, and avoids unrelated cleanup or refactors.

All fixes are committed locally, but **never pushed** during this phase.

After all fixes:

```bash
npx tsc --noEmit
```

If type checking fails, the pipeline identifies the offending commit, reverts it, fixes the issue, and recommits before continuing.

### Phase 3: Reply

The orchestrator drafts one reply per thread based on:

- Original thread data
- Triage verdicts
- Actual diff: `git diff origin/{branch}...HEAD`
- Failure records from Phase 2

Replies are matched to the reviewer's language and tone, kept concise, and never defensive.

### Phase 4: Post & Push

Approved replies are posted to GitHub, and all local review-fix commits are pushed in one step.

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

### In an agent

When installed as a skill, invoke it from your agent with natural language. Examples:

- "帮我处理这个 PR 的 review：<https://github.com/owner/repo/pull/123>"
- "回复 reviewer 的评论"
- "看看 PR 里那些 unresolved threads"
- "review 提的问题要修一下"
- "CI 过了，但 review 还没回"
- "someone left comments on my PR"
- "帮我看看那些人提的意见"

### From the command line

If you want to drive the workflow manually, you can use the GitHub CLI commands directly. The skill and package primarily wrap these operations into an agent-friendly pipeline.

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- A Git working tree clean enough to create review-fix commits
- Node.js / TypeScript project if you want the final `tsc --noEmit` check

## Supported platforms

| Platform | Support |
| --- | --- |
| npm / Node.js | ✅ Install as a published package |
| Pi | ✅ Supported as a package and as a skill |
| Claude Code | ✅ Task-based agent dispatch |
| Cursor | ✅ Background agent dispatch |
| Other agent clients | ✅ Inline fallback using the agent specs in `agents/` |

## Notes

- Agent specs are provided in `agents/` for reuse across platforms.
- When a platform supports parallel agents, triage can run in parallel; otherwise it runs inline.
- There are two checkpoints where execution pauses for confirmation: after triage verdicts, and before posting replies.
- Pushes only happen once, after replies are approved.
- The implementation phase is serial by default to avoid conflicting file changes.

# PR Review Handler

> Systematically process GitHub PR review comments: triage for validity, fix code, and post replies.

📦 **Repository**: <https://github.com/JI4JUN/pr-review-handler>

[![Build Status](https://img.shields.io/github/actions/workflow/status/JI4JUN/pr-review-handler/publish.yml?style=flat-square&label=Build)](https://github.com/JI4JUN/pr-review-handler/actions)
[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pr-review-handler?style=flat-square&label=%40trashcodermaker%2Fpr-review-handler)](https://www.npmjs.com/package/@trashcodermaker/pr-review-handler)
[![npm version](https://img.shields.io/npm/v/@trashcodermaker/pi-pr-review-handler?style=flat-square&label=%40trashcodermaker%2Fpi-pr-review-handler)](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

⭐ If you like this project, [star it on GitHub](https://github.com/JI4JUN/pr-review-handler) — it helps a lot!

[Overview](#overview) • [Packages](#packages) • [Getting started](#getting-started) • [How it works](#how-it-works) • [Repository structure](#repository-structure) • [Requirements](#requirements) • [Supported platforms](#supported-platforms)

[中文版](./README.zh.md)

## Overview

Code review is part of every healthy PR workflow, but turning review threads into actual fixes and thoughtful replies can be tedious and error-prone.

**PR Review Handler** automates that workflow. It fetches unresolved GitHub PR review threads, evaluates each comment for validity, applies minimal code fixes, drafts replies that match the reviewer's language and tone, and optionally pushes changes and requests re-review.

The skill is agent-agnostic: it ships agent specs in `agents/` and works with any agent harness that can run subtasks (Pi, Claude Code, Cursor, Gemini CLI, OpenCode, …) or inline as a fallback.

## Packages

This repository is a monorepo that publishes two npm packages from a single
source of truth (`skills/pr-review-handler/`). Both ship identical skill
content; they differ only in the published skill name and npm keywords so
each audience can find the one meant for it.

| Package | npm name | Skill name | Install command | Audience |
| --- | --- | --- | --- | --- |
| Core | `@trashcodermaker/pr-review-handler` | `pr-review-handler` | `npm install @trashcodermaker/pr-review-handler` | Any agent harness |
| Pi | `@trashcodermaker/pi-pr-review-handler` | `pi-pr-review-handler` | `pi install npm:@trashcodermaker/pi-pr-review-handler` | Pi users |

Use the **Core** package unless you install skills through Pi. The **Pi**
package exists so Pi users can discover and install it via `pi install` and
the Pi package gallery (`pi-package` keyword).

> [!NOTE]
> The Pi package ships its skill as **`pi-pr-review-handler`** (not
> `pr-review-handler`) so it can coexist with a `skills.sh` / `npx skills add`
> install of the Core skill in the same project without a name collision.
> Invoke it as `/skill:pi-pr-review-handler`.

## Getting started

### Install as an npm package (any agent)

```bash
npm install @trashcodermaker/pr-review-handler
```

### Install as a Pi package

```bash
pi install npm:@trashcodermaker/pi-pr-review-handler
```

The skill registers as **`pi-pr-review-handler`** (invoke with
`/skill:pi-pr-review-handler`). This differs from the Core / `skills.sh`
skill name (`pr-review-handler`) so the two can be installed side-by-side
in the same environment without a Pi skill-name collision.

> **Pi users**: Run `/pi-pr-review-handler-sync` to sync project agents
> after install or upgrade. See
> [packages/pi/README.md](packages/pi/README.md) for details.

> [!IMPORTANT]
> **Upgrading from ≤ 1.1.3?** Older versions shipped the skill as
> `pr-review-handler/` inside this package. npm does not always remove
> files that existed in a previous version but are absent from the new
> tarball, so a stale `skills/pr-review-handler/` directory may survive an
> upgrade and re-introduce the name collision. After upgrading, remove it
> manually if present:
>
> ```bash
> rm -rf ~/.pi/agent/npm/node_modules/@trashcodermaker/pi-pr-review-handler/skills/pr-review-handler
> ```
>
> Or simply uninstall and reinstall:
>
> ```bash
> pi uninstall @trashcodermaker/pi-pr-review-handler
> pi install npm:@trashcodermaker/pi-pr-review-handler
> ```

### Install via skills CLI (any agent harness)

```bash
npx skills add JI4JUN/pr-review-handler --skill pr-review-handler
```

This clones the repo and copies the skill into your agent's skills directory,
including the `agents/` specs.

### From source

```bash
git clone https://github.com/JI4JUN/pr-review-handler.git
cd pr-review-handler
npm install
```

> [!IMPORTANT]
> Ensure GitHub CLI (`gh`) is installed and authenticated before using this
> skill. Most commands depend on it to read PR data and post replies.

## How it works

The handler runs a multi-phase pipeline. Each phase has a clear
responsibility, and the flow stops at checkpoints where human confirmation is
requested.

```
Phase 0: Setup
Phase 1: Triage        ← parallel, read-only
Phase 1.5: Dependencies ← build repair dependency graph
Phase 2: Fix           ← serial for dependencies; isolated parallel for proven-independent groups
Phase 3: Reply         ← orchestrator drafts inline
Phase 4: Post & Push
Phase 5: Report
```

### Phase 0: Setup

Identifies the target PR from the current branch or an explicit PR link,
fetches unresolved review threads, and fetches review-level feedback. This
phase prepares everything needed for triage without modifying code.

### Phase 1: Triage

Reads the referenced code, PR diff context, and each review thread, then
**verifies the reviewer's claim** and classifies every comment as:

- `valid-fix` — claim **confirmed** with a concrete `code_path`; needs a code change
- `valid-nofix` — claim has merit, but no code change on this PR
- `invalid` — claim failed, already handled, or harmful suggested fix

Each verdict also carries evidence fields used at Checkpoint 1:

| Field | Purpose |
| --- | --- |
| `claim_check` | `confirmed` \| `failed` \| `insufficient` |
| `evidence.code_path` | Symbol/control-flow proving a confirmed claim (required for `valid-fix`) |
| `evidence.in_pr_diff` | Whether the concern is in this PR's diff |
| `axis` | `standards` \| `spec` \| `both` \| `n/a` |
| **fix contract** (valid-fix) | `suggested_fix` + `acceptance` (2–4 checkable items) + `out_of_scope` |

`valid-fix` is gated: no confirmed claim + code path → no automatic fix. Unclear threads use `claim_check: insufficient` and surface **Need from user** at Checkpoint 1.

On Pi with pi-subagents, triage runs in parallel via `pr-review-handler.triage` project agents. On other harnesses, runs via the harness's subtask mechanism. Falls back to inline if no subtask mechanism.

> [!TIP]
> Triage is intentionally conservative. If a comment is unclear, set
> `claim_check: insufficient` and `invalid` with reason `unclear — needs human review`.

### Phase 1.5: Repair dependencies

After confirmation, orchestrator compares each fix contract's affected files, modified/referenced symbols, change kinds, call chains, and uncertainty. Any overlap or relation not proven independent becomes a dependency.

### Phase 2: Fix

Dependent repairs run serially in graph order. Only proven-independent groups run concurrently, each in isolated clean Git worktree; patches are inspected and integrated before later waves. Setup failure, patch conflict, or newly discovered overlap falls back to serial execution. Each implementation agent still follows triage fix contract and applies only minimal accepted change.

All integrated fixes are committed as a single commit, but **never pushed** during this phase.

After all fixes, the pipeline runs the project's type checker or equivalent verification (auto-detected: `tsc` for TypeScript, `ruff`/`mypy` for Python, `go build` for Go, `cargo check` for Rust, etc.). If it fails, the pipeline does `git reset --soft` to unstage the commit, fixes the issue, and recommits before continuing.

### Phase 3: Reply

The orchestrator drafts one reply per thread based on:

- Original thread data
- Triage verdicts
- Actual diff: `git diff origin/{branch}...HEAD`
- Failure records from Phase 2

Replies are matched to the reviewer's language and tone, kept concise, and
never defensive. By default each reply includes a short **AI-assisted**
footer (strippable at Checkpoint 2). Out-of-PR nits get a stock scope-boundary phrase.

### Phase 4: Post & Push

Approved replies are posted to GitHub. Every thread that received a reply is
then auto-resolved via the GraphQL `resolveReviewThread` mutation (simulates
clicking "Resolve conversation" on the PR page). Finally, the single
review-fix commit is pushed.

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

## Repository structure

```
pr-review-handler/
├── skills/
│   └── pr-review-handler/      # canonical skill (single source of truth)
│       ├── SKILL.md
│       └── agents/             # triage + implementation agent specs
├── packages/
│   ├── core/                   # → npm: @trashcodermaker/pr-review-handler
│   └── pi/                     # → npm: @trashcodermaker/pi-pr-review-handler
├── scripts/
│   └── sync-skill.mjs          # copies the skill into each package at publish
├── package.json                # workspaces root
└── .github/workflows/publish.yml
```

Both packages publish from `packages/<name>/`. The `prepublishOnly` script
runs `sync-skill.mjs` to copy `skills/pr-review-handler/` into the package
before npm packs it, so the skill content is never duplicated in source
control.

### Publishing

Publishing is driven by tags (or `workflow_dispatch`):

- `core-v1.1.0` → publishes `packages/core`
- `pi-v1.1.0` → publishes `packages/pi`

Locally:

```bash
npm run publish:core    # or npm run publish:pi
```

## Usage

### In an agent

When installed as a skill, invoke it from your agent with natural language.
Examples:

- "帮我处理这个 PR 的 review：<https://github.com/owner/repo/pull/123>"
- "回复 reviewer 的评论"
- "看看 PR 里那些 unresolved threads"
- "review 提的问题要修一下"
- "CI 过了，但 review 还没回"
- "someone left comments on my PR"
- "帮我看看那些人提的意见"

### From the command line

If you want to drive the workflow manually, you can use the GitHub CLI
commands directly. The skill and package primarily wrap these operations
into an agent-friendly pipeline.

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- A Git working tree clean enough to create review-fix commits
- A project with a type checker or linter (TypeScript, Python, Go, Rust, etc.) for the post-fix verification — auto-detected, skipped if none recognized

## Supported platforms

| Platform | Support |
| --- | --- |
| npm / Node.js | ✅ Install `@trashcodermaker/pr-review-handler` as a published package |
| Pi | ✅ Install `@trashcodermaker/pi-pr-review-handler` via `pi install`. For subtask-based dispatch (fresh context per thread), install the [`pi-subagents`](https://github.com/nicobailon/pi-subagents) extension (`pi install npm:pi-subagents`); otherwise the skill runs inline. |
| Claude Code | ✅ Task-based agent dispatch, or `npx skills add` |
| Cursor | ✅ Background agent dispatch |
| Gemini CLI / OpenCode / others | ✅ Native subtask mechanism, or inline fallback |
| skills CLI | ✅ `npx skills add JI4JUN/pr-review-handler --skill pr-review-handler` |

## Recommended companion tools

### CodeGraph (optional, enhances triage & implementation)

The Triage and Implementation project agents reference `mcp:codegraph` in their tool list. [CodeGraph](https://github.com/colbymchenry/codegraph) is a semantic code intelligence MCP server — it provides symbol lookup, call-edge traversal, and blast-radius analysis that goes beyond `grep` (handles dynamic dispatch, polymorphism, etc.).

**Why**: when triaging, CodeGraph helps the agent find all callers of a symbol accurately (for `affected_files`). When implementing, it traces references that grep might miss.

**Install**: see the [CodeGraph repo](https://github.com/colbymchenry/codegraph). After installing the CLI (`curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh`), run `codegraph install` to wire it into your agent, then `codegraph init` in each project.

**Pi users**: CodeGraph's `install` command auto-configures Claude Code, Cursor, Codex, and others, but not Pi. Add the CodeGraph MCP server to your Pi MCP configuration manually. If CodeGraph is not installed, the agents fall back to `grep`/`find` — the skill still works, just with less precise reference discovery.

## Notes

- Agent specs are provided in `agents/` for reuse across platforms.
- On Pi with pi-subagents, triage runs in parallel via `pr-review-handler.triage` project agents; on other harnesses, via their subtask mechanism; otherwise inline.
- There are two checkpoints where execution pauses for confirmation: after
  triage verdicts, and before posting replies.
- Pushes only happen once, after replies are approved.
- The implementation phase is serial by default to avoid conflicting file
  changes.

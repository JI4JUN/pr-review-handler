# @trashcodermaker/pr-review-handler

> Systematically process GitHub PR review comments: triage for validity, fix code, and post replies.

This is the **generic npm package** — an agent skill usable from any agent harness: Pi, Claude Code, Cursor, Gemini CLI, OpenCode, and others.

Looking for the **Pi-specific package**? See [`@trashcodermaker/pi-pr-review-handler`](https://www.npmjs.com/package/@trashcodermaker/pi-pr-review-handler).

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
            ├── triage-agent.md
            └── implementation-agent.md
```

Point your agent at `node_modules/@trashcodermaker/pr-review-handler/skills/pr-review-handler/SKILL.md`, or copy the `skills/pr-review-handler/` directory into your agent's skill discovery path.

## How it works

The skill runs a multi-phase pipeline with two human checkpoints:

```
Phase 0: Setup → Phase 1: Triage (parallel, read-only) → Phase 2: Fix (serial)
         → Phase 3: Reply → Phase 4: Post & Push → Phase 5: Report
```

Each phase has a clear responsibility. Triage classifies every review comment as `valid-fix`, `valid-nofix`, or `invalid`. Implementation applies minimal surgical fixes. The orchestrator drafts replies that match the reviewer's language and tone.

Full documentation: <https://github.com/JI4JUN/pr-review-handler#readme>

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- A Git working tree clean enough to create review-fix commits
- Node.js / TypeScript project if you want the final `tsc --noEmit` check

## License

MIT

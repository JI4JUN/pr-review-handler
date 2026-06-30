# @trashcodermaker/pi-pr-review-handler

> Pi package — systematically process GitHub PR review comments: triage, fix, reply.

Install with Pi:

```bash
pi install npm:@trashcodermaker/pi-pr-review-handler
```

Pi auto-discovers the skill under `skills/pr-review-handler/`. Once installed, invoke it from your Pi session with natural language like "handle the reviews on my PR" or `/skill:pr-review-handler`.

## What it does

Fetches unresolved GitHub PR review threads, evaluates each comment for validity, applies minimal code fixes, drafts replies that match the reviewer's language and tone, and optionally pushes changes and requests re-review.

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- A Git working tree clean enough to create review-fix commits
- Node.js / TypeScript project if you want the final `tsc --noEmit` check

## How it works

```
Phase 0: Setup → Phase 1: Triage (parallel) → Phase 2: Fix (serial)
         → Phase 3: Reply → Phase 4: Post & Push → Phase 5: Report
```

Checkpoints pause for confirmation after triage verdicts and before posting replies.

## Other platforms

This is the Pi-scoped package. If you use Claude Code, Cursor, Gemini CLI, OpenCode, or another harness, install the generic package instead:

```bash
npm install @trashcodermaker/pr-review-handler
```

Or grab the skill directly:

```bash
npx skills add JI4JUN/pr-review-handler --skill pr-review-handler
```

## License

MIT

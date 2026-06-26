# pr-review-handler

Systematically process GitHub PR review comments: triage for validity, fix code, and post replies.

## Install

```bash
npx skills add JI4JUN/pr-review-handler
```

```bash
pi install npm:@JI4JUN/pi-pr-review-handler
```

## What it does

- Fetches unresolved PR review threads
- Triages comments in parallel
- Applies minimal code fixes
- Drafts replies in the reviewer's language
- Pushes and requests re-review

## Requirements

- GitHub CLI (`gh`) authenticated
- Node.js / TypeScript project (for `tsc` check)

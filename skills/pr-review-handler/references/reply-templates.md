# Review Reply Guidelines & Templates

This reference defines reply tone, templates, and formatting rules for Phase 3 (Reply Drafting).

## Principles

1. **Ground truth diff**: Describe what `git diff origin/{branch}...HEAD` actually changed, not planned fixes.
2. **Language matching**: Match reviewer language (reply in the language used by the reviewer).
3. **Concise & peer-to-peer**: 1–3 sentences ideal. Trust reviewer understands code. Avoid defensive hedging.
4. **AI disclosure**: Keep the AI footer unless the user strips it at Checkpoint 2.

---

## Verdict Templates

### 1. `valid-fix` (Fix Applied)

#### As Suggested
- "Added the null check at line 42 as suggested — `user` can indeed be undefined when the session expires."

#### Diverged / Architectural Fix
- "Your point about rate limiting is valid. Instead of a fixed window, implemented a token bucket in `rateLimit.ts` — handles burst traffic better and existing tests cover it."

---

### 2. `valid-fix` (Failed / Deferred)
Acknowledge validity factually. State blockers without apologizing.

- "Good catch that this should be strictly typed. However, `User` is shared with the legacy auth module which expects `any`. Extracted an issue/follow-up to isolate `StrictUser` without ballooning this PR."

---

### 3. `valid-nofix` (Valid Concern, No Code Change)

#### Intentional Tradeoff / Breaking Change
- "Fair point on the naming — `handleX` is vague. But it is part of the public API documented in `docs/api.md`, so renaming would be a breaking change. Added a deprecation notice for next major."

#### Out of PR Diff Scope / Pre-existing Code
- "Agreed this is worth tracking, but it lives in unchanged base code outside this PR's diff. Deferring to a follow-up PR to preserve surgical PR boundaries."

#### Repository Convention Pushback (Surgical Changes)
- "Per repository conventions (`AGENTS.md` / `CLAUDE.md`: *Don't improve adjacent code; touch only what you must*), this is pre-existing baseline behavior outside this PR's scope. Deferring to a separate issue to prevent PR scope creep."

---

### 4. `invalid` (Refuted with Evidence)
Acknowledge intent, show invariant / code path proving why the issue cannot occur.

#### Invariant / Guard Exists
- "I see why you'd anticipate an overflow here, but `items` is already capped at `MAX_ITEMS` at line 15 before this loop runs, so `i` stays within safe bounds."

#### Repository Convention Pushback (Impossible Scenarios)
- "Per repository conventions (`AGENTS.md` / `CLAUDE.md`: *Simplicity first: No error handling for impossible scenarios*), error chains in this path are generated exclusively by internal runtime built-ins. Guarding against theoretical adversarial Proxies is out of model for this service."

---
## AI-Assisted Footer

Append to all reply bodies unless user explicitly opts out:

```markdown
> _(AI-assisted reply — approved in pr-review-handler checkpoint)_
```

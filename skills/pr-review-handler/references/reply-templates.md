# Review Reply Guidelines & Templates

This reference defines reply tone, bilingual templates, and formatting rules for Phase 3 (Reply Drafting).

## Principles

1. **Ground truth diff**: Describe what `git diff origin/{branch}...HEAD` actually changed, not planned fixes.
2. **Language matching**: Match reviewer language (Chinese $\rightarrow$ Chinese, English $\rightarrow$ English).
3. **Concise & peer-to-peer**: 1–3 sentences ideal. Trust reviewer understands code. Avoid defensive hedging.
4. **AI disclosure**: Keep the AI footer unless the user strips it at Checkpoint 2.

---

## Verdict Templates

### 1. `valid-fix` (Fix Applied)

#### As Suggested
- **EN**: "Added the null check at line 42 as suggested — `user` can indeed be undefined when the session expires."
- **ZH**: "已在 42 行补充空值校验，session 过期时 `user` 确实可能为 undefined。"

#### Diverged / Architectural Fix
- **EN**: "Your point about rate limiting is valid. Instead of a fixed window, implemented a token bucket in `rateLimit.ts` — handles burst traffic better and existing tests cover it."
- **ZH**: "限流建议很准。相比固定窗口，改在 `rateLimit.ts` 采用了令牌桶算法，能更好应对突发流量，已有单测已覆盖。"

---

### 2. `valid-fix` (Failed / Deferred)
Acknowledge validity factually. State blockers without apologizing.

- **EN**: "Good catch that this should be strictly typed. However, `User` is shared with the legacy auth module which expects `any`. Extracted an issue/follow-up to isolate `StrictUser` without ballooning this PR."
- **ZH**: "确实应该做严格类型收窄。不过 `User` 接口目前被旧版 auth 模块共用且依赖 `any`。为避免 PR 改动扩散，已记录后续重构独立跟进。"

---

### 3. `valid-nofix` (Valid Concern, No Code Change)

#### Intentional Tradeoff / Breaking Change
- **EN**: "Fair point on the naming — `handleX` is vague. But it is part of the public API documented in `docs/api.md`, so renaming would be a breaking change. Added a deprecation notice for next major."
- **ZH**: "命名确实不够直观。不过 `handleX` 属于已公开的 API，直接重命名属于 breaking change，已计划在下一个大版本中平滑废弃。"

#### Out of PR Diff Scope
- **EN**: "Agreed this is worth tracking, but it lives in unchanged base code outside this PR's diff. Happy to address in a follow-up PR."
- **ZH**: "同意这是个好建议，但这属于原基线已有代码，不在本次 PR diff 范围内；建议单独提 PR 优化。"

---

### 4. `invalid` (Refuted with Evidence)
Acknowledge intent, show invariant / code path proving why the issue cannot occur.

- **EN**: "I see why you'd anticipate an overflow here, but `items` is already capped at `MAX_ITEMS` at line 15 before this loop runs, so `i` stays within safe bounds."
- **ZH**: "能理解你对溢出的担忧，不过进入循环前在 15 行 `items` 已被 `MAX_ITEMS` 截断，`i` 在此上下文中始终处于安全范围内。"

---

## AI-Assisted Footer

Append to all reply bodies unless user explicitly opts out:

```markdown
> _(AI-assisted reply — approved in pr-review-handler checkpoint)_
```

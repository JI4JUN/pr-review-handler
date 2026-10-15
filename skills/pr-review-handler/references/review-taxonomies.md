# Review Taxonomies & Decision Framework

This reference defines verification axes, reviewer intent taxonomy, and triage evaluation rules.

## 1. Reviewer Intent Taxonomy

| Category | Typical Indicators | Handling Strategy |
| :--- | :--- | :--- |
| **Defect / Spec Bug** | Points to crash, data loss, logic error, regression | Mandatory verification. If confirmed with `code_path`, classify as `valid-fix`. |
| **Convention / Nit** | Naming, format, lint smell, typing cleanliness | Check `AGENTS.md` or repo standards. If `in_pr_diff: true` and rule exists $\rightarrow$ `valid-fix`. If baseline or subjective $\rightarrow$ `valid-nofix`. |
| **Architecture / Discussion** | "Have you considered X?", "Alternative approach could be..." | Reviewer seeks discussion. Default to `valid-nofix` with technical trade-off explanation; escalate to user if redesign is needed. |
| **Clarification / Question** | "Why do we need this?", "What happens if...?" | Pure inquiry. Classify as `valid-nofix`, draft clear factual reply in Phase 3. |

---

## 2. Claim Verification & Falsification Checklist

A reviewer claim is a hypothesis. Before assigning `valid-fix`, test for falsification:

1. **Upstream Invariants**: Is the invalid state physically prevented upstream (e.g., schema parsing, type assertion, router middleware)?
2. **Execution Reachability**: Is the branch dead or conditioned out in production runtime?
3. **Diff Ownership (`in_pr_diff`)**:
   - `true`: Line or enclosing block was added/modified by this PR.
   - `false`: Line belongs to base branch; PR only indented or touched adjacent lines. (Default to `valid-nofix` unless critical security flaw).

---

## 3. Checkpoint 1 Presentation Schema

### Table 1: Inline Review Threads (Core / Mandatory)
| # | File:Line | Reviewer | Summary | Claim | In PR? | Axis | Verdict | Affected |
|---|-----------|----------|---------|-------|--------|------|---------|----------|
| 1 | auth/login.ts:42 | alice | Missing null check | confirmed | true | spec | valid-fix | login.ts |
| 2 | ui/Button.tsx:18 | bob | Rename for clarity | confirmed | false | standards | valid-nofix | — |

*Note: Any row with `claim_check: insufficient` must display `Need from user`.*

### Table 2: Review-Level Feedback (Human Summaries)
| # | Reviewer | State | Body (Excerpt) | Action |
|---|----------|-------|----------------|--------|
| R1 | alice | CHANGES_REQUESTED | "Overall solid, but auth module needs refactor" | [Ignore / Reply only / Needs code change] |

### Table 3: Bot Advisory Items (Optional / Opt-in)
*Extracted from bot summaries (e.g. OpenCodeReview, CodeRabbit). Defaults to Ignore.*
| # | File:Line | Source | Category | Summary | User Action |
|---|-----------|--------|----------|---------|-------------|
| A1 | model-chip.tsx:112 | OpenCodeReview | maintainability (low) | Duplicate inline button classes | [Ignore (Default) / Adopt fix] |

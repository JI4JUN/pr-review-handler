#!/usr/bin/env bash
# fetch-threads.sh — Fetch unresolved review threads, review summaries, and bot advisories for a PR.
# Output is saved to /tmp/pr-<number>-context.json and /tmp/pr-context.json.
# Usage:
#   fetch-threads.sh [PR_NUMBER_OR_URL]

set -euo pipefail

TARGET="${1:-}"

# 1. Resolve PR target
if [[ -z "$TARGET" ]]; then
  # Auto-detect from current branch
  PR_JSON=$(gh pr view --json number,url,headRefName,baseRefName,headRepository,headRepositoryOwner 2>/dev/null || true)
  if [[ -z "$PR_JSON" || "$PR_JSON" == "{}" ]]; then
    echo "Error: No PR found for current branch. Please specify a PR number or URL: fetch-threads.sh <pr>" >&2
    exit 1
  fi
elif [[ "$TARGET" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  PR_JSON=$(gh pr view "$TARGET" --json number,url,headRefName,baseRefName,headRepository,headRepositoryOwner)
elif [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  PR_JSON=$(gh pr view "$TARGET" --json number,url,headRefName,baseRefName,headRepository,headRepositoryOwner)
else
  # Might be owner/repo#number or similar
  PR_JSON=$(gh pr view "$TARGET" --json number,url,headRefName,baseRefName,headRepository,headRepositoryOwner)
fi

PR_NUMBER=$(node -e 'const d = JSON.parse(process.argv[1]); console.log(d.number);' "$PR_JSON")
PR_URL=$(node -e 'const d = JSON.parse(process.argv[1]); console.log(d.url);' "$PR_JSON")
BASE_BRANCH=$(node -e 'const d = JSON.parse(process.argv[1]); console.log(d.baseRefName || "");' "$PR_JSON")
HEAD_BRANCH=$(node -e 'const d = JSON.parse(process.argv[1]); console.log(d.headRefName || "");' "$PR_JSON")

# Extract owner and repo from PR_URL
OWNER=$(node -e 'const u = new URL(process.argv[1]); const [, o] = u.pathname.split("/"); console.log(o);' "$PR_URL")
REPO=$(node -e 'const u = new URL(process.argv[1]); const [, , r] = u.pathname.split("/"); console.log(r);' "$PR_URL")

DIFF_FILE="/tmp/pr-${PR_NUMBER}.diff"
CONTEXT_FILE="/tmp/pr-${PR_NUMBER}-context.json"
GLOBAL_CONTEXT="/tmp/pr-context.json"

# 2. Fetch diff in background
gh pr diff "$PR_NUMBER" --repo "${OWNER}/${REPO}" > "$DIFF_FILE" 2>/dev/null || true

# 3. Query GitHub GraphQL API
GRAPHQL_QUERY='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      number
      title
      url
      headRefName
      baseRefName
      latestReviews(first: 20) {
        nodes {
          id
          state
          author { login }
          body
          submittedAt
        }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first: 20) {
            nodes {
              databaseId
              body
              author { login }
              createdAt
            }
          }
        }
      }
      comments(last: 15) {
        nodes {
          databaseId
          body
          author { login }
          createdAt
        }
      }
    }
  }
}'

RAW_DATA=$(gh api graphql -f query="$GRAPHQL_QUERY" -F owner="$OWNER" -F repo="$REPO" -F pr="$PR_NUMBER")

# 4. Process and deduplicate data with Node.js
node -e '
const fs = require("fs");
const raw = JSON.parse(process.argv[1]);
const diffContent = fs.existsSync(process.argv[2]) ? fs.readFileSync(process.argv[2], "utf8") : "";
const pr = raw.data.repository.pullRequest;

// Helper to slice diff hunks for a path
function getDiffHunkForPath(diff, filePath) {
  if (!diff || !filePath) return "";
  const marker = "diff --git a/" + filePath + " b/" + filePath;
  const start = diff.indexOf(marker);
  if (start === -1) return "";
  const nextDiff = diff.indexOf("\ndiff --git ", start + marker.length);
  const fileDiff = nextDiff === -1 ? diff.slice(start) : diff.slice(start, nextDiff);
  return fileDiff.slice(0, 3000); // Bound length to prevent huge context
}

// 1. Process inline review threads
const unresolved = (pr.reviewThreads?.nodes || []).filter(t => !t.isResolved);

// Deduplicate threads: cluster by (path, line) and matching core concern or discussion_r link
const clustered = [];
const seenClusters = new Map();

for (const t of unresolved) {
  const topComment = t.comments?.nodes?.[0];
  if (!topComment) continue;

  const key = `${t.path}:${t.line || t.originalLine || 0}`;
  const body = topComment.body || "";

  // Check for discussion_r link
  const discMatch = body.match(/discussion_r([0-9]+)/);
  const ruleMatch = body.match(/([a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+)/);
  const clusterKey = discMatch ? `disc:${discMatch[1]}` : (ruleMatch ? `${key}:${ruleMatch[1]}` : key);

  if (seenClusters.has(clusterKey)) {
    const existing = seenClusters.get(clusterKey);
    existing.collapsed_thread_ids.push(t.id);
    existing.collapsed_comment_ids.push(topComment.databaseId);
    // Merge follow-up comments if any
    for (const c of (t.comments?.nodes || []).slice(1)) {
      existing.comments.push({
        id: c.databaseId,
        author: c.author?.login || "unknown",
        body: c.body
      });
    }
    continue;
  }

  const threadEntry = {
    id: t.id,
    comment_id: topComment.databaseId,
    path: t.path,
    line: t.line || t.originalLine || 0,
    is_outdated: Boolean(t.isOutdated),
    reviewer: topComment.author?.login || "unknown",
    collapsed_thread_ids: [],
    collapsed_comment_ids: [],
    comments: (t.comments?.nodes || []).map(c => ({
      id: c.databaseId,
      author: c.author?.login || "unknown",
      body: c.body
    })),
    diff_hunk: getDiffHunkForPath(diffContent, t.path)
  };

  seenClusters.set(clusterKey, threadEntry);
  clustered.push(threadEntry);
}

// 2. Process review summaries (filter empty, whitespace-only, and bot-marker-only comments)
const reviewSummaries = [];
const seenAuthors = new Set();

for (const rev of (pr.latestReviews?.nodes || [])) {
  const body = (rev.body || "").trim();
  const author = rev.author?.login || "unknown";
  
  // Filter out empty, dismissed, or pure HTML comment markers (e.g. <!-- ocr-review-run:... -->)
  if (!body || rev.state === "DISMISSED") continue;
  if (/^<!--[\s\S]*?-->$/.test(body)) continue;
  if (seenAuthors.has(author)) continue;

  seenAuthors.add(author);
  reviewSummaries.push({
    id: rev.id,
    reviewer: author,
    state: rev.state,
    submitted_at: rev.submittedAt,
    body: body
  });
}

// 3. Process bot advisory items from issue comments (OpenCodeReview, CodeRabbit, etc.)
const advisoryItems = [];
let advisoryIndex = 1;

for (const c of (pr.comments?.nodes || [])) {
  const body = c.body || "";
  if (!body) continue;

  // Pattern A: OpenCodeReview summary
  if (body.includes("<!-- ocr-summary -->") || body.includes("OpenCodeReview")) {
    const rawItems = body.split(/\n(?=(?:!\[[^\]]+\]\([^\)]+\)\s*\n)?### 📄 )/);
    for (const item of rawItems) {
      const headerMatch = item.match(/### 📄 `([^`]+)` \((?:L([0-9]+)(?:-L([0-9]+))?)\)/);
      if (!headerMatch) continue;

      const filePath = headerMatch[1];
      const startLine = parseInt(headerMatch[2], 10);
      const sevMatch = item.match(/!\[([^·\]]+)·\s*([^\]]+)\]/);
      const category = sevMatch ? sevMatch[1].trim() : "general";
      const severity = sevMatch ? sevMatch[2].trim() : "low";

      // Extract description
      const lines = item.split("\n").filter(l => !l.startsWith("### 📄") && !l.startsWith("![") && !l.startsWith("⚠️"));
      const summaryText = lines.join("\n").replace(/<details>[\s\S]*?<\/details>/g, "").trim().slice(0, 300);

      advisoryItems.push({
        id: `advisory-ocr-${advisoryIndex++}`,
        source: "OpenCodeReview Summary",
        path: filePath,
        line: startLine,
        severity: severity,
        category: category,
        summary: summaryText.split("\n")[0] || summaryText,
        full_comment: item.trim(),
        diff_hunk: getDiffHunkForPath(diffContent, filePath)
      });
    }
  }

  // Pattern B: CodeRabbit additional comments
  if (body.includes("<!-- coderabbit_summary -->") || body.includes("CodeRabbit")) {
    const detailsMatch = body.match(/<details>\s*<summary>[^<]*Additional comments[^<]*<\/summary>([\s\S]*?)<\/details>/i);
    if (detailsMatch) {
      const section = detailsMatch[1];
      const items = section.split(/\n(?=\* \*\*`[^`]+`\*\*)/);
      for (const item of items) {
        const fileMatch = item.match(/\* \*\*`([^`:]+):?([0-9]+)?`\*\*:?\s*([^\n]+)/);
        if (fileMatch) {
          advisoryItems.push({
            id: `advisory-cr-${advisoryIndex++}`,
            source: "CodeRabbit Summary",
            path: fileMatch[1],
            line: fileMatch[2] ? parseInt(fileMatch[2], 10) : 0,
            severity: "low",
            category: "maintainability",
            summary: fileMatch[3].trim(),
            full_comment: item.trim(),
            diff_hunk: getDiffHunkForPath(diffContent, fileMatch[1])
          });
        }
      }
    }
  }
}

const contextData = {
  pr: {
    number: pr.number,
    title: pr.title,
    url: pr.url,
    owner: process.argv[3],
    repo: process.argv[4],
    head_branch: pr.headRefName,
    base_branch: pr.baseRefName
  },
  inline_threads: clustered,
  review_summaries: reviewSummaries,
  advisory_items: advisoryItems
};

fs.writeFileSync(process.argv[5], JSON.stringify(contextData, null, 2), "utf8");
fs.writeFileSync(process.argv[6], JSON.stringify(contextData, null, 2), "utf8");

console.log(`✅ Fetched PR #${pr.number} (${process.argv[3]}/${process.argv[4]})`);
console.log(`   - 🧵 Inline Threads: ${clustered.length} unresolved (${unresolved.length - clustered.length} duplicates collapsed)`);
console.log(`   - 📝 Review Summaries: ${reviewSummaries.length}`);
console.log(`   - 💡 Advisory Items (Optional): ${advisoryItems.length}`);
console.log(`   - 💾 Context written to: ${process.argv[5]}`);
' "$RAW_DATA" "$DIFF_FILE" "$OWNER" "$REPO" "$CONTEXT_FILE" "$GLOBAL_CONTEXT"

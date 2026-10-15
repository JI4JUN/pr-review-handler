#!/usr/bin/env bash
# resolve-threads.sh — Resolve review threads on a GitHub Pull Request via GraphQL.
# Usage:
#   resolve-threads.sh [PR_NUMBER_OR_URL] [--all | ID1 ID2 ...]
#
# IDs can be GraphQL thread node IDs (PRRT_...) or comment databaseIds (numbers).
# If no IDs are specified, defaults to resolving all threads in /tmp/pr-context.json.

set -euo pipefail

TARGET="${1:-}"
shift || true

# 1. Resolve PR target
if [[ -z "$TARGET" ]]; then
  PR_JSON=$(gh pr view --json number,url,headRepository,headRepositoryOwner 2>/dev/null || true)
  if [[ -z "$PR_JSON" || "$PR_JSON" == "{}" ]]; then
    echo "Error: No PR found for current branch. Specify PR: resolve-threads.sh <pr> [ids...]" >&2
    exit 1
  fi
elif [[ "$TARGET" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  PR_JSON=$(gh pr view "$TARGET" --json number,url,headRepository,headRepositoryOwner)
elif [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  PR_JSON=$(gh pr view "$TARGET" --json number,url,headRepository,headRepositoryOwner)
else
  PR_JSON=$(gh pr view "$TARGET" --json number,url,headRepository,headRepositoryOwner)
fi

PR_NUMBER=$(node -e 'const d = JSON.parse(process.argv[1]); console.log(d.number);' "$PR_JSON")
PR_URL=$(node -e 'const d = JSON.parse(process.argv[1]); console.log(d.url);' "$PR_JSON")
OWNER=$(node -e 'const u = new URL(process.argv[1]); const [, o] = u.pathname.split("/"); console.log(o);' "$PR_URL")
REPO=$(node -e 'const u = new URL(process.argv[1]); const [, , r] = u.pathname.split("/"); console.log(r);' "$PR_URL")

# Collect target IDs from remaining arguments
REQUESTED_IDS=("$@")

# 2. Fetch current reviewThreads from GitHub
QUERY='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 20) {
            nodes {
              databaseId
            }
          }
        }
      }
    }
  }
}'

RAW_DATA=$(gh api graphql -f query="$QUERY" -F owner="$OWNER" -F repo="$REPO" -F pr="$PR_NUMBER")

# 3. Determine which thread IDs need resolving
TARGET_THREAD_IDS=$(node -e '
const raw = JSON.parse(process.argv[1]);
const reqArgs = process.argv.slice(2);
const threads = raw.data.repository.pullRequest.reviewThreads.nodes || [];

let matchAll = reqArgs.length === 0 || reqArgs.includes("--all");
const targetSet = new Set(reqArgs.map(String));

const toResolve = [];

for (const t of threads) {
  if (t.isResolved) continue;

  if (matchAll) {
    toResolve.push(t.id);
    continue;
  }

  // Check if thread id matches
  if (targetSet.has(t.id)) {
    toResolve.push(t.id);
    continue;
  }

  // Check if any comment databaseId matches
  const commentIds = (t.comments?.nodes || []).map(c => String(c.databaseId));
  if (commentIds.some(cid => targetSet.has(cid))) {
    toResolve.push(t.id);
  }
}

console.log(toResolve.join(" "));
' "$RAW_DATA" "${REQUESTED_IDS[@]:-}")

if [[ -z "$TARGET_THREAD_IDS" ]]; then
  echo "ℹ️ No unresolved threads matched criteria for PR #${PR_NUMBER}."
  exit 0
fi

RESOLVED_COUNT=0
FAILED_COUNT=0

MUTATION='
mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) {
    thread {
      id
      isResolved
    }
  }
}'

for TID in $TARGET_THREAD_IDS; do
  if gh api graphql -f query="$MUTATION" -F id="$TID" >/dev/null 2>&1; then
    RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
  else
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo "✅ Resolved ${RESOLVED_COUNT} thread(s) on PR #${PR_NUMBER} (${OWNER}/${REPO})."
if [[ "$FAILED_COUNT" -gt 0 ]]; then
  echo "⚠️ Failed to resolve ${FAILED_COUNT} thread(s)."
fi

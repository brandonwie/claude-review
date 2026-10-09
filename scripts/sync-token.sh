#!/usr/bin/env bash
# Copies one CLAUDE_CODE_OAUTH_TOKEN into every repository whose workflows call
# this repository's shared workflows, so the token is updated in one place.
# Routing matches claude-review.yml: personal repositories (owner brandonwie)
# get a repository secret; work repositories get it in their `brandonwie`
# environment, which must already exist.
#
# Usage:  <token source> | scripts/sync-token.sh
#         scripts/sync-token.sh --dry-run        # list callers, set nothing
# The token is read from stdin, never from arguments. GH_TOKEN (or the gh
# login) must be allowed to write Actions secrets in every caller. OWNERS
# overrides the scanned accounts. Under CI (public logs) it prints counts only.
set -euo pipefail

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1
owners=${OWNERS:-"brandonwie playtag-dev"}
needle='uses: brandonwie/claude-review/.github/workflows/'

token=""
if [ "$dry_run" -eq 0 ]; then
  token=$(cat)
  [ -n "$token" ] || { echo "::error::no token on stdin" >&2; exit 2; }
fi

say() { [ -n "${CI:-}" ] || echo "$@"; }

# One query per owner returns every live repository with its workflow files.
# A user's list also holds repositories it only collaborates on, hence the
# owner filter below. $owner and $endCursor are GraphQL variables, not shell.
# shellcheck disable=SC2016
query='query($owner: String!, $endCursor: String) {
  repositoryOwner(login: $owner) {
    repositories(first: 100, after: $endCursor, isArchived: false) {
      pageInfo { hasNextPage endCursor }
      nodes {
        nameWithOwner
        object(expression: "HEAD:.github/workflows") {
          ... on Tree { entries { object { ... on Blob { text } } } }
        }
      }
    }
  }
}'

targets=()
for owner in $owners; do
  while IFS= read -r repo; do
    [ -n "$repo" ] && targets+=("$repo")
  done < <(gh api graphql --paginate -f owner="$owner" -f query="$query" \
    --jq ".data.repositoryOwner.repositories.nodes[]
      | select(.nameWithOwner | startswith(\"$owner/\"))
      | select([.object.entries[]?.object.text // \"\" | contains(\"$needle\")] | any)
      | .nameWithOwner")
done

ok=0
failed=0
for repo in ${targets[@]+"${targets[@]}"}; do
  if [ "${repo%%/*}" = brandonwie ]; then
    env_args=()
    where="repository secret"
  else
    env_args=(--env brandonwie)
    where="environment brandonwie"
  fi
  if [ "$dry_run" -eq 1 ]; then
    say "would set: $repo ($where)"
    ok=$((ok + 1))
  elif printf '%s' "$token" | gh secret set CLAUDE_CODE_OAUTH_TOKEN \
    --repo "$repo" ${env_args[@]+"${env_args[@]}"} >/dev/null 2>&1; then
    say "set: $repo ($where)"
    ok=$((ok + 1))
  else
    say "FAILED: $repo ($where)"
    failed=$((failed + 1))
  fi
done

echo "callers: ${#targets[@]}, $([ "$dry_run" -eq 1 ] && echo listed || echo set): $ok, failed: $failed"
[ "$failed" -eq 0 ] && [ "${#targets[@]}" -gt 0 ]

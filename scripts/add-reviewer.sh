#!/usr/bin/env bash
# Lets one person run "@claude review" in a work repository with their OWN
# token: creates the environment named after their GitHub login, restricts it
# to `main`, then stores their CLAUDE_CODE_OAUTH_TOKEN in it. The token is read
# from stdin (gh prompts for it when stdin is a terminal), never from arguments.
#
# Usage:  scripts/add-reviewer.sh <owner/repo> <github-login>
# Needs repository admin rights. Personal repositories (owner brandonwie) are
# refused: there only brandonwie reviews, with the repository secret.
set -euo pipefail

repo=${1:-}
login=${2:-}
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] && [[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || {
  echo "usage: $0 <owner/repo> <github-login>" >&2
  exit 2
}
[ "${repo%%/*}" != brandonwie ] || {
  echo "refused: $repo is a personal repository; only brandonwie reviews there" >&2
  exit 2
}

echo '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' |
  gh api -X PUT "repos/$repo/environments/$login" --input - >/dev/null
# Already present on a re-run; the check below proves the end state either way.
gh api -X POST "repos/$repo/environments/$login/deployment-branch-policies" \
  -f name=main -f type=branch >/dev/null 2>&1 || true
policies=$(gh api "repos/$repo/environments/$login/deployment-branch-policies" \
  --jq '[.branch_policies[] | "\(.type):\(.name)"] | join(",")')
[ "$policies" = "branch:main" ] || {
  echo "environment $login on $repo must deploy from main only (found: ${policies:-none})" >&2
  exit 1
}

gh secret set CLAUDE_CODE_OAUTH_TOKEN --env "$login" --repo "$repo"
echo "$login can now run @claude review in $repo with their own token."

#!/usr/bin/env bash
# Fails unless every workflow under .github/workflows pins each listed action to
# one and the same 40-character commit SHA, so every caller runs one version.
# Run from the repository root.
set -euo pipefail

status=0
for action in anthropics/claude-code-action actions/checkout; do
  refs=$(grep -hoE "uses: ${action}@[^ ]+" .github/workflows/*.yml | sed 's/^uses: //' | sort -u || true)
  count=$(printf '%s\n' "$refs" | grep -c . || true)
  echo "${action}: ${refs:-none}"
  if [ "$count" -ne 1 ] || ! printf '%s\n' "$refs" | grep -qE "@[0-9a-f]{40}$"; then
    echo "::error::${action} must be pinned to one commit SHA across .github/workflows (found ${count})"
    status=1
  fi
done
exit "$status"

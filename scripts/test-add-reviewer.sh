#!/usr/bin/env bash
# Runs add-reviewer.sh against a fake `gh`: it must create the environment,
# restrict it to main, store the token from stdin in that environment, and
# refuse personal repositories and malformed arguments.
set -euo pipefail

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "secret set" ]; then echo "$* value=$(cat)" >> "$FAKE_LOG"; exit 0; fi
echo "$*" >> "$FAKE_LOG"
case "$*" in *deployment-branch-policies*--jq*) echo "branch:main" ;; esac
EOF
chmod +x "$dir/gh"
script="$(dirname "$0")/add-reviewer.sh"

printf 'tok456' | FAKE_LOG="$dir/log" PATH="$dir:$PATH" bash "$script" work/app alice >/dev/null
grep -q '^api -X PUT repos/work/app/environments/alice --input -$' "$dir/log" || { echo "FAIL: no environment PUT"; exit 1; }
grep -q 'deployment-branch-policies -f name=main -f type=branch' "$dir/log" || { echo "FAIL: no main policy"; exit 1; }
grep -q '^secret set CLAUDE_CODE_OAUTH_TOKEN --env alice --repo work/app value=tok456$' "$dir/log" || { echo "FAIL: token not stored"; cat "$dir/log"; exit 1; }

for args in "brandonwie/3b alice" "work/app bad/login" "noslash alice"; do
  # shellcheck disable=SC2086
  if PATH="$dir:$PATH" FAKE_LOG="$dir/log" bash "$script" $args </dev/null >/dev/null 2>&1; then
    echo "FAIL: accepted '$args'"; exit 1
  fi
done
echo "add-reviewer: ok"

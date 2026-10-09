#!/usr/bin/env bash
# Runs sync-token.sh against a fake `gh` and checks the routing: a brandonwie
# repository gets a repository secret, any other owner gets the brandonwie
# environment, the token arrives on stdin, and one failure fails the run.
set -euo pipefail

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = api ]; then
  case "$*" in *owner=work*) echo "work/one" ;; *owner=brandonwie*) echo "brandonwie/p1" ;; esac
  exit 0
fi
if [ "$1 $2" = "secret set" ]; then
  echo "$* value=$(cat)" >> "$FAKE_LOG"
  case "$*" in *work/one*) exit 1 ;; esac
fi
EOF
chmod +x "$dir/gh"

status=0
printf 'tok123' | FAKE_LOG="$dir/log" PATH="$dir:$PATH" OWNERS="brandonwie work" \
  bash "$(dirname "$0")/sync-token.sh" >/dev/null || status=$?

expected="secret set CLAUDE_CODE_OAUTH_TOKEN --repo brandonwie/p1 value=tok123
secret set CLAUDE_CODE_OAUTH_TOKEN --repo work/one --env brandonwie value=tok123"
[ "$(cat "$dir/log")" = "$expected" ] || { echo "FAIL: unexpected gh calls"; cat "$dir/log"; exit 1; }
[ "$status" -eq 1 ] || { echo "FAIL: a failed target must fail the run (exit $status)"; exit 1; }
echo "sync-token routing: ok"

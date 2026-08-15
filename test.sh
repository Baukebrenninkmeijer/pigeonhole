#!/bin/sh
# Regression checks for bin/pigeonhole. Runs against a throwaway HOME in a temp
# dir — it never reads or writes the real $HOME/.pigeonhole.
#
#   sh test.sh
#
# Only covers behaviour that has actually broken: identity drift across cwd,
# archive escaping its own mailbox, liveness forgeable by a sender, and the
# retention rules around deleting mail.

set -u

PG=$(cd "$(dirname "$0")" && pwd)/bin/pigeonhole
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILED=0

ok()   { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; FAILED=1; }
is()   { [ "$2" = "$3" ] && ok "$1" || fail "$1" "expected '$3', got '$2'"; }

# Two worktrees of one repo, plus a second repo, all under a fake HOME.
export HOME="$TMP/home"
mkdir -p "$HOME"
for r in alpha beta; do
  mkdir -p "$TMP/$r" && (cd "$TMP/$r" && git init -q . && git commit -q --allow-empty -m init)
done
mkdir -p "$TMP/alpha/docs"

A="cd $TMP/alpha && $PG"
B="cd $TMP/beta && $PG"
M="$HOME/.pigeonhole/mail"

sh -n "$PG" || fail "syntax" "bin/pigeonhole does not parse"

eval "$A join" >/dev/null
eval "$B join" >/dev/null

# Identity is the worktree, not the cwd: a subdirectory must not fork a mailbox.
is "whoami at repo root" "$(eval "$A whoami")" "alpha-alpha"
is "whoami in subdir"    "$(cd "$TMP/alpha/docs" && sh "$PG" whoami)" "alpha-alpha"

# archive is confined to your own unread mail.
echo "hi" | eval "$B send alpha-alpha" >/dev/null
MSG=$(eval "$A check")
[ -n "$MSG" ] && ok "send delivers" || fail "send delivers" "alpha has no unread mail"

echo x > "$TMP/outside.md"
eval "$A archive $TMP/outside.md" 2>/dev/null && \
  fail "archive refuses foreign path" "moved a file from outside the mailbox" || \
  ok "archive refuses foreign path"
[ -f "$TMP/outside.md" ] || fail "archive refuses foreign path" "outside.md was moved anyway"

echo y | eval "$A send beta-beta" >/dev/null
STOLEN=$(eval "$B check")
eval "$A archive $STOLEN" 2>/dev/null && \
  fail "archive refuses a peer's mail" "took another agent's unread message" || \
  ok "archive refuses a peer's mail"
[ -f "$STOLEN" ] || fail "archive refuses a peer's mail" "peer's message vanished"

eval "$A archive $MSG" 2>/dev/null && ok "archive accepts own mail" \
  || fail "archive accepts own mail" "refused a path check printed"

# Liveness is .joined only — a sender must not resurrect a stale mailbox.
touch -t 202001010000 "$M/beta-beta/.joined"
eval "$A peers" | grep -q beta-beta && \
  fail "stale peer hidden" "beta-beta still listed as live" || ok "stale peer hidden"
echo z | eval "$A send beta-beta" >/dev/null
eval "$A peers" | grep -q beta-beta && \
  fail "send does not fake liveness" "sending mail made beta-beta look live" || \
  ok "send does not fake liveness"

# status is flattened to one safe line (it ends up inside the hook's JSON).
printf 'on "auth"\\stuff\nsecond line\n' | eval "$A status" >/dev/null
S=$(cat "$M/alpha-alpha/.status")
is "status is one safe line" "$S" "on authstuff"
eval "$B board" | grep -q "alpha-alpha: on authstuff$" \
  && ok "board shows peer status" || fail "board shows peer status" "not in board output"

# Retention: old archived mail goes, unread mail never does, mailboxes move.
UNREAD="$M/alpha-alpha/old-unread.md"
ARCH="$M/alpha-alpha/read/old-archived.md"
KEEP="$M/alpha-alpha/read/keep.txt"
touch "$UNREAD" "$ARCH" "$KEEP"
touch -t 202001010000 "$UNREAD" "$ARCH" "$KEEP"
eval "$A sweep"
[ -f "$UNREAD" ] && ok "old unread mail kept" || fail "old unread mail kept" "deleted"
[ -f "$ARCH" ] && fail "old archived mail deleted" "still present" || ok "old archived mail deleted"
[ -f "$KEEP" ] && ok "non-md in read/ kept" || fail "non-md in read/ kept" "deleted"
[ -d "$M/.retired/beta-beta" ] \
  && ok "stale mailbox retired, not deleted" \
  || fail "stale mailbox retired, not deleted" "beta-beta is not in .retired/"
[ -n "$(find "$M/.retired/beta-beta" -maxdepth 1 -name '*.md')" ] \
  && ok "retired mailbox keeps its unread mail" \
  || fail "retired mailbox keeps its unread mail" "mail lost on retire"

# The hook must emit exactly one line of valid JSON, and must not leak message text.
HOOK=$(cd "$TMP/alpha" && sh "$(dirname "$PG")/../hooks/session-start.sh")
printf '%s' "$HOOK" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null \
  && ok "hook emits valid JSON" || fail "hook emits valid JSON" "$HOOK"
[ -L "$HOME/.pigeonhole/bin/pigeonhole" ] && ok "hook links bin/pigeonhole" \
  || fail "hook links bin/pigeonhole" "symlink not created"

[ "$FAILED" -eq 0 ] && echo "all passed" || echo "FAILURES"
exit "$FAILED"

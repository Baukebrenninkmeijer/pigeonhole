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

# Two live peers for the hook to report: one with a status, one without. delta
# sorts before gamma, so plain alphabetical order would put the bare name first.
for p in gamma-gamma delta-delta; do mkdir -p "$M/$p/read" && touch "$M/$p/.joined"; done
echo "rewriting shared/auth.py" > "$M/gamma-gamma/.status"

# The hook must emit exactly one line of valid JSON, and must not leak message text.
HOOK=$(cd "$TMP/alpha" && sh "$(dirname "$PG")/../hooks/session-start.sh")
printf '%s' "$HOOK" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null \
  && ok "hook emits valid JSON" || fail "hook emits valid JSON" "$HOOK"
[ -L "$HOME/.pigeonhole/bin/pigeonhole" ] && ok "hook links bin/pigeonhole" \
  || fail "hook links bin/pigeonhole" "symlink not created"

# A bare name is nothing to collide with, so the statused peer must come first
# or the 12-line cap spends itself on names.
printf '%s' "$HOOK" | grep -q 'gamma-gamma: rewriting shared/auth.py; delta-delta' \
  && ok "hook lists statused peers first" \
  || fail "hook lists statused peers first" "$HOOK"

# Both nudges must be runnable lines, not a pointer at the skill.
printf '%s' "$HOOK" | grep -q "echo 'one line on what you are working on' | .HOME/.pigeonhole/bin/pigeonhole status" \
  && ok "hook spells out the status command" || fail "hook spells out the status command" "$HOOK"
printf '%s' "$HOOK" | grep -q 'pigeonhole send <name>' \
  && ok "hook nudges send when a peer has a status" \
  || fail "hook nudges send when a peer has a status" "$HOOK"

# With nobody statused there is nothing to collide with, so no send nudge.
rm -f "$M/gamma-gamma/.status"
printf '%s' "$(cd "$TMP/alpha" && sh "$(dirname "$PG")/../hooks/session-start.sh")" \
  | grep -q 'pigeonhole send <name>' \
  && fail "hook omits send nudge with no statuses" "nudged send at an empty board" \
  || ok "hook omits send nudge with no statuses"

# The prompt hook is what actually fills the board: agents do not post their own
# status when asked, so the task the user typed becomes the status.
UP="$(dirname "$PG")/../hooks/user-prompt.sh"
rm -f "$M/alpha-alpha/.status"
OUT=$(cd "$TMP/alpha" && printf '{"session_id":"x","prompt":"RES-9: rework \\"auth\\" in shared/auth.py\\nand the callers","cwd":"/x"}' | sh "$UP")
is "prompt hook writes a status" "$(cat "$M/alpha-alpha/.status" 2>/dev/null)" \
   "RES-9: rework auth in shared/auth.py and the callers"
is "prompt hook stays silent" "$OUT" ""

# An approval or a slash command is not a task and must not clobber a real one.
for P in "yes go ahead" "/commit and push the thing"; do
  (cd "$TMP/alpha" && printf '{"prompt":"%s"}' "$P" | sh "$UP")
  is "prompt hook ignores '$P'" "$(cat "$M/alpha-alpha/.status" 2>/dev/null)" \
     "RES-9: rework auth in shared/auth.py and the callers"
done

# Outside a git repo there is no agent to speak for.
rm -f "$M/alpha-alpha/.status"
(cd "$TMP" && printf '{"prompt":"a long enough prompt to pass the guard"}' | sh "$UP")
[ -f "$M/alpha-alpha/.status" ] && fail "prompt hook needs a git repo" "wrote a status from outside one" \
  || ok "prompt hook needs a git repo"

# doctor reports rather than mutates, and must survive a broken install.
eval "$A doctor" | grep -q '^you:.*alpha-alpha' && ok "doctor identifies you" \
  || fail "doctor identifies you" "no 'you:' line for alpha-alpha"
rm -f "$HOME/.pigeonhole/bin/pigeonhole"
eval "$A doctor" | grep -q 'MISSING' && ok "doctor flags a broken symlink" \
  || fail "doctor flags a broken symlink" "did not report the missing link"
eval "$A doctor" >/dev/null 2>&1 && fail "doctor exits nonzero on problems" "exited 0" \
  || ok "doctor exits nonzero on problems"

[ "$FAILED" -eq 0 ] && echo "all passed" || echo "FAILURES"
exit "$FAILED"

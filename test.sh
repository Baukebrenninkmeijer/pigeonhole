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

# Two horizons: quiet for BOARD_DAYS drops you off the roster, quiet for
# STALE_DAYS retires you. A mailbox between the two must stay addressable, or
# you cannot hand work to an agent who has not been back yet today.
FIVED=$(date -v-5d +%Y%m%d%H%M 2>/dev/null || date -d '5 days ago' +%Y%m%d%H%M)
mkdir -p "$M/quiet-quiet/read" && touch -t "$FIVED" "$M/quiet-quiet/.joined"
eval "$A peers" | grep -q quiet-quiet \
  && fail "quiet mailbox off the roster" "listed a peer last seen 5 days ago" \
  || ok "quiet mailbox off the roster"
eval "$A sweep"
[ -d "$M/quiet-quiet" ] && ok "quiet mailbox not retired" \
  || fail "quiet mailbox not retired" "sweep retired a mailbox inside STALE_DAYS"
echo q | eval "$A send quiet-quiet" >/dev/null \
  && ok "quiet mailbox still addressable" \
  || fail "quiet mailbox still addressable" "send refused an off-roster mailbox"
rm -rf "$M/quiet-quiet"

# Two peers in another repo for the hook to report: one with a status, one
# without. gamma is touched first, so recency alone would lead with delta.
for p in gamma-gamma delta-delta; do mkdir -p "$M/$p/read" && touch "$M/$p/.joined"; done
echo "rewriting shared/auth.py" > "$M/gamma-gamma/.status"

# The hook must emit exactly one line of valid JSON, and must not leak message text.
HOOK=$(cd "$TMP/alpha" && sh "$(dirname "$PG")/../hooks/session-start.sh")
printf '%s' "$HOOK" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null \
  && ok "hook emits valid JSON" || fail "hook emits valid JSON" "$HOOK"
[ -L "$HOME/.pigeonhole/bin/pigeonhole" ] && ok "hook links bin/pigeonhole" \
  || fail "hook links bin/pigeonhole" "symlink not created"

# Within one repo tier a bare name is nothing to collide with, so the statused
# peer leads or the 12-line cap spends itself on names.
printf '%s' "$HOOK" | grep -q 'gamma-gamma: rewriting shared/auth.py; delta-delta' \
  && ok "hook lists statused peers first" \
  || fail "hook lists statused peers first" "$HOOK"

# But a sibling worktree of your own repo outranks a statused stranger: it is
# the one you can actually collide with. alpha-sibling has no status at all and
# still has to come before gamma-gamma, which does.
mkdir -p "$M/alpha-sibling/read" && touch "$M/alpha-sibling/.joined"
printf '%s' "$(cd "$TMP/alpha" && sh "$(dirname "$PG")/../hooks/session-start.sh")" \
  | grep -q 'alpha-sibling.*gamma-gamma' \
  && ok "same repo outranks a status" \
  || fail "same repo outranks a status" "gamma-gamma came first"
rm -rf "$M/alpha-sibling"

# With nothing else to break the tie, the roster is most recently joined
# first. delta sorts first alphabetically and is the older join, so only real
# mtime ordering puts gamma on top. Distinct timestamps, not two touches in
# the same second: ls -t breaks ties however it likes.
rm -f "$M/gamma-gamma/.status"
TENH=$(date -v-10H +%Y%m%d%H%M 2>/dev/null || date -d '10 hours ago' +%Y%m%d%H%M)
touch -t "$TENH" "$M/delta-delta/.joined" && touch "$M/gamma-gamma/.joined"
eval "$A peers" | head -n 1 | grep -q gamma-gamma \
  && ok "roster leads with the most recent join" \
  || fail "roster leads with the most recent join" "$(eval "$A peers" | head -n 1)"
touch "$M/delta-delta/.joined"
echo "rewriting shared/auth.py" > "$M/gamma-gamma/.status"

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

# The todo hook is what actually fills the board: agents do not post their own
# status when asked, but they do write todo lists, so the in-progress item is
# the status. Agent-authored, and it moves when the work moves.
TH="$(dirname "$PG")/../hooks/todo-status.sh"
TODOS='{"tool_name":"TodoWrite","tool_input":{"todos":[{"content":"Read the auth module","status":"completed"},{"content":"Rewrite \\"validate_token\\" in shared/auth.py","status":"in_progress"},{"content":"Run the tests","status":"pending"}]}}'
rm -f "$M/alpha-alpha/.status"
OUT=$(cd "$TMP/alpha" && printf '%s' "$TODOS" | sh "$TH")
is "todo hook writes the in-progress item" "$(cat "$M/alpha-alpha/.status" 2>/dev/null)" \
   "Rewrite validate_token in shared/auth.py"
is "todo hook stays silent" "$OUT" ""

# A finished list has nothing in progress, and must not blank a live status.
(cd "$TMP/alpha" && printf '{"tool_input":{"todos":[{"content":"Run the tests","status":"completed"}]}}' | sh "$TH")
is "todo hook keeps the last status when nothing is in progress" \
   "$(cat "$M/alpha-alpha/.status" 2>/dev/null)" "Rewrite validate_token in shared/auth.py"

# Outside a git repo there is no agent to speak for.
rm -f "$M/alpha-alpha/.status"
(cd "$TMP" && printf '%s' "$TODOS" | sh "$TH")
[ -f "$M/alpha-alpha/.status" ] && fail "todo hook needs a git repo" "wrote a status from outside one" \
  || ok "todo hook needs a git repo"

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

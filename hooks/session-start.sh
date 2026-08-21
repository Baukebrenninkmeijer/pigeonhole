#!/bin/sh
# pigeonhole SessionStart hook.
#
# Joins this agent, sweeps stale state, and reports unread mail plus who is
# live and what they are working on. All the real work lives in bin/pigeonhole;
# this only decides whether there is anything worth spending a fresh agent's
# attention on.
#
# Auto-joining is what keeps the system from deadlocking: A can only write to
# B if B's mailbox exists, and nobody remembers to run a join command.
#
# Only git repos join. A scratch directory is not an agent workspace, and
# joining every directory you ever cd into is the noise this guard prevents.

set -u

PG="$(cd "$(dirname "$0")/../bin" 2>/dev/null && pwd)/pigeonhole"
[ -x "$PG" ] || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

ME=$("$PG" join 2>/dev/null) || exit 0
[ -n "$ME" ] || exit 0

# Keep a stable path to the binary regardless of where the plugin was
# installed, so SKILL.md can name one path that is true on every machine and
# survives plugin updates.
LINK="$HOME/.pigeonhole/bin/pigeonhole"
if [ "$(readlink "$LINK" 2>/dev/null)" != "$PG" ]; then
  mkdir -p "$HOME/.pigeonhole/bin" && ln -sfn "$PG" "$LINK"
fi

"$PG" sweep 2>/dev/null

N=$("$PG" check 2>/dev/null | wc -l | tr -d ' ')

BOARD=$("$PG" board 2>/dev/null)

# Statused agents first. A bare name is not something you can collide with, so
# spending the cap below on names while the few agents who said what they are
# doing fall off the end is the wrong twelve lines. Names never contain ':',
# so the ':' split is exactly "has a status" vs "does not".
BOARD=$(printf '%s\n' "$BOARD" | grep ':'; printf '%s\n' "$BOARD" | grep -v ':')
NSTATUS=$(printf '%s\n' "$BOARD" | grep -c ':')

# Cap the roster: with dozens of workspaces the full board is noise, and the
# skill's `board` subcommand gives the complete list on demand. Each line is
# "name" or "name: what they are working on"; status text was already flattened
# to one safe line by `status`, so nothing here can break the JSON below.
PEERS=""
COUNT=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  COUNT=$((COUNT + 1))
  [ "$COUNT" -gt 12 ] && continue
  PEERS="${PEERS:+$PEERS; }$(printf '%s' "$p" | cut -c1-70)"
done <<EOF
$BOARD
EOF
[ "$COUNT" -gt 12 ] && PEERS="$PEERS; and $((COUNT - 12)) more"

# Nothing to say: no mail, nobody around. Stay quiet.
[ "$N" -gt 0 ] || [ -n "$PEERS" ] || exit 0

MSG="pigeonhole: you are '$ME'."
[ "$N" -gt 0 ] && MSG="$MSG $N unread message(s). Invoke the pigeonhole skill to read and archive them before starting work."
if [ -n "$PEERS" ]; then
  # The ask comes before the roster. Twelve lines of other people's work is a
  # wall to skim past; behind it, a request reads as a footnote.
  # Spell the command out. Loading a skill to learn one pipeline is a cost most
  # agents decline at session start, and status is the write that seeds
  # everything else: with no statuses the board is names, and with no board
  # nobody has a reason to send. No double quotes or backslashes here -- this
  # string goes into the JSON below unescaped.
  MSG="$MSG Run this now, before your first edit, and again when your scope grows: echo 'one line on what you are working on' | \$HOME/.pigeonhole/bin/pigeonhole status"
  # The send nudge only makes sense next to lines you could collide with.
  MSG="$MSG Live agents: $PEERS."
  # The send nudge only makes sense next to lines you could collide with.
  [ "$NSTATUS" -gt 0 ] && MSG="$MSG If one of those lines touches a file you are about to change, tell that agent before you start: echo 'what you are about to change' | \$HOME/.pigeonhole/bin/pigeonhole send <name>"
fi

# Only names, an integer, and already-flattened status text reach this JSON —
# never message content. Mail is untrusted input and must enter context through
# the skill's Read step, where it is framed as coming from a peer, not injected
# as if it came from the user.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$MSG"

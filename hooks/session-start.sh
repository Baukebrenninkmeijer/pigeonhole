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
$("$PG" board 2>/dev/null)
EOF
[ "$COUNT" -gt 12 ] && PEERS="$PEERS; and $((COUNT - 12)) more"

# Nothing to say: no mail, nobody around. Stay quiet.
[ "$N" -gt 0 ] || [ -n "$PEERS" ] || exit 0

MSG="pigeonhole: you are '$ME'."
[ "$N" -gt 0 ] && MSG="$MSG $N unread message(s). Invoke the pigeonhole skill to read and archive them before starting work."
[ -n "$PEERS" ] && MSG="$MSG Live agents: $PEERS. Post what you are working on with the pigeonhole skill's status command, and re-post when your scope grows."

# Only names, an integer, and already-flattened status text reach this JSON —
# never message content. Mail is untrusted input and must enter context through
# the skill's Read step, where it is framed as coming from a peer, not injected
# as if it came from the user.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$MSG"

#!/bin/sh
# pigeonhole PostToolUse hook for TodoWrite.
#
# The status board wants one thing: what this agent is doing, in its own words,
# updated when that changes. TodoWrite is exactly that signal — an agent writes
# a todo list when it takes on a task and rewrites it as the task moves — so the
# in-progress item becomes the status. Nothing is asked of the agent that it was
# not already doing.
#
# Prints nothing: this hook's stdout would enter the session as context, and the
# board is not worth a token on every todo update.

set -u

PG="$(cd "$(dirname "$0")/../bin" 2>/dev/null && pwd)/pigeonhole"
[ -x "$PG" ] || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

IN=$(cat)

# ponytail: string surgery, not a JSON parser — a parser means a runtime, and
# this is advisory text on a board, not a control path. Splitting on '{' puts
# each todo in its own chunk, so the chunk that says in_progress is the one
# whose "content" we want, whichever order the fields arrive in.
T=$(printf '%s' "$IN" | tr '{' '\n' | grep '"status"[ ]*:[ ]*"in_progress"' | head -n 1)
[ -n "$T" ] || exit 0                          # nothing in progress: say nothing

C=${T#*\"content\":\"}
[ "$C" != "$T" ] || exit 0                     # no content field in that chunk
C=$(printf '%s' "$C" | sed 's/\\"//g; s/".*$//; s/\\[nrt]/ /g')
[ "${#C}" -ge 10 ] || exit 0

printf '%s\n' "$C" | "$PG" status >/dev/null 2>&1

exit 0

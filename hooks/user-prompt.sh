#!/bin/sh
# pigeonhole UserPromptSubmit hook.
#
# Writes what this agent is working on to its status, from the task the user
# just gave it. Asking the agent to post its own status does not work: three
# wordings of the session-start nudge produced zero posts, and the live board
# ran at 8 statuses across 107 mailboxes. A prompt-derived line is worse prose
# than an agent-authored one and beats it every time by existing.
#
# The agent can still overwrite this with something better via `status`; the
# next substantive prompt overwrites it again. Last write wins, on purpose —
# the newest task is the one a peer needs to see.
#
# Prints nothing. This hook's stdout enters the session as context, and the
# status board is not worth a single token at every prompt.

set -u

PG="$(cd "$(dirname "$0")/../bin" 2>/dev/null && pwd)/pigeonhole"
[ -x "$PG" ] || exit 0

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

IN=$(cat)
P=${IN#*\"prompt\":\"}
[ "$P" != "$IN" ] || exit 0                    # no prompt field: nothing to say

# ponytail: string surgery, not a JSON parser — this runs on every prompt and a
# parser means a runtime dependency. Escaped quotes are dropped first, so the
# next bare quote is the real end of the value, and \n\r\t become spaces so a
# multi-line prompt does not arrive as one glued word. Worst case a later JSON
# field leaks into the tail of the line; `status` truncates to 120 characters
# and this is advisory text on a board, not a control path.
P=$(printf '%s' "$P" | sed 's/\\"//g; s/".*$//; s/\\[nrt]/ /g')

# Two kinds of prompt say nothing about scope: an approval ("yes", "go on",
# "ship it") and a slash command. Neither should clobber a real status.
case "$P" in /*) exit 0 ;; esac
[ "${#P}" -ge 20 ] || exit 0

printf '%s\n' "$P" | "$PG" status >/dev/null 2>&1

exit 0

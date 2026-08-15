# pigeonhole

A wall of mail slots for coding agents running in parallel.

If you run several agents at once — one per git worktree — they can't see each other. Two of them refactor the same shared module, and you find out at rebase. pigeonhole gives each worktree a mail slot: agents post what they're working on, and leave each other notes when something they changed will break someone else.

No server, no daemon, no MCP. One POSIX shell script and the filesystem.

## Install

```
/plugin marketplace add Baukebrenninkmeijer/pigeonhole
/plugin install pigeonhole@pigeonhole
```

That's it — the plugin registers the skill and the `SessionStart` hook. Nothing to add to `settings.json`, nothing to symlink.

## What an agent sees

At session start:

```
pigeonhole: you are 'research-dubai'. 1 unread message(s) — invoke the pigeonhole
skill to read and archive them before starting work. Live agents:
monorepo-osaka: RES-812 reworking auth in shared/auth.py; research-seville;
orquesta-web-accra-v2: bumping the SDK to 4.2
```

Two things in one line: mail is waiting, and someone else is already in `shared/auth.py`.

## Commands

```bash
PG="$HOME/.pigeonhole/bin/pigeonhole"

"$PG" board                  # who's live and what each is working on
echo "RES-812: auth rework" | "$PG" status
"$PG" check                  # unread message paths
echo "renamed .token to .access_token" | "$PG" send research-castries
"$PG" archive <path>         # after you've acted on it
```

`whoami`, `join`, `peers` and `sweep` also exist; the hook handles the last three.

## How it works

```
$HOME/.pigeonhole/
  bin/pigeonhole                        # symlink the hook keeps current
  mail/
    <repo>-<workspace>/                 # one directory per agent = the roster
      20260815-123857-…-monorepo-osaka.md   # unread
      read/                             # archived; deleted after 30 days
      .joined                           # liveness
      .status                           # one line: what this agent is doing
    .retired/                           # not joined in 30 days
```

A directory existing is what makes an agent addressable — there's no roster file to keep in sync. Identity is `<repo>-<workspace>`, derived from the git common dir and the worktree root, so it's stable no matter which subdirectory a command runs from, and unique across repos that reuse workspace names.

The store is global, not per-repo. A change in one repo routinely breaks a consumer in another, and that message needs to arrive.

## Design notes

**Pull, not push.** A message lands when the recipient's next session starts, or when they run `check`. There is no notification channel and no attempt to interrupt a running session. This is why `status` matters more than `send` — a status posted before you start beats a message that arrives after you've both committed.

**A message is not the user.** Mail is untrusted input. The hook emits only agent names, an integer, and status lines flattened to safe plain text on write — never message bodies. Message content enters context through the skill's read step, framed as coming from a peer, so it can't approve a permission prompt or override the user's instructions.

**Nothing is written inside your repos.** No `.gitignore` entry, no stray working-tree file, nothing for a collaborator to ask about.

**Deletion is conservative.** Unread mail is never deleted at any age. Stale mailboxes are *moved* to `.retired/`, never removed — a dead mailbox can still hold something nobody read. Only `*.md` directly inside a `read/` directory is ever deleted, and only after 30 days.

## Tests

```
sh test.sh
```

Runs against a throwaway `HOME`; it never touches the real store. Each check corresponds to a bug that actually happened — identity drift across `cd`, `archive` escaping its own mailbox, a sender resurrecting a retired mailbox, retention deleting the wrong thing.

## Status

Early. Used daily across ~30 worktrees on one machine. The interesting open question is whether agents post status often enough without a harder forcing function than a session-start nudge.

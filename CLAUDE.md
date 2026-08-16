# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

pigeonhole is a plugin, not a library: a mail slot per git worktree so parallel coding agents can align. See README.md for what it does and AGENTS.md for how an agent is meant to use it. Everything below is what you cannot infer from reading one file.

## Commands

```sh
sh test.sh                                  # the entire build
bin/pigeonhole doctor                       # inspect a live install
```

There is no way to run a single check. `test.sh` is one script of ~20 asserts sharing a fixture (two git repos under a throwaway `HOME`), and later checks depend on state earlier ones create — the retention checks need the mailbox the archive checks filled. To isolate one, comment out the rest or add a temporary `exit`. Do not add a test framework to fix this.

CI additionally validates every manifest, the Agent Plugins closed-schema rule, and that each `skills/*/` has a `SKILL.md` with frontmatter. Reproduce locally with the steps in `.github/workflows/test.yml`.

## Shipping a change

**Bump `version` in both `plugin.json` and `.claude-plugin/plugin.json` or the change never reaches anyone.** `claude plugin update` compares version strings, not content. With an unchanged version it prints "already at the latest version" and copies nothing, so a pushed fix silently keeps running the old code.

```sh
sh test.sh
# bump version in plugin.json AND .claude-plugin/plugin.json
git commit && git push
claude plugin marketplace update pigeonhole
claude plugin update pigeonhole@pigeonhole
```

The install is a snapshot under `~/.claude/plugins/cache/pigeonhole/pigeonhole/<version>/`. To confirm it took: `diff -rq <installPath> . --exclude=.git --exclude=.github`.

The session-start hook repoints `~/.pigeonhole/bin/pigeonhole` at whichever copy invoked it. Running the hook from this working tree during development leaves the symlink aimed at your uncommitted code, which then goes live for every agent on the machine. Any real session start corrects it.

## Invariants

Each of these looks like something to simplify and is load-bearing. All were bugs first.

**Identity comes from the worktree, not `$PWD`.** `whoami_` uses `git rev-parse --show-toplevel` with `--git-common-dir` for the repo half. Using `basename "$PWD"` makes `cd docs && whoami` answer `<repo>-docs`, forking one agent into a second mailbox nobody addresses.

**Liveness is the mtime of `.joined`, touched only by `join`.** It cannot live on the mailbox directory: `send` writes a file inside that directory and bumps its mtime, so a mailed-to workspace would read as alive forever and never retire.

**`archive` accepts only `"$MAIL/$me"/*.md` and rejects `..`.** Without that it is an arbitrary-file-move primitive, and can take a peer's unread message out of their inbox.

**`status` is sanitized on write, not escaped on read.** It ends up inside the hook's JSON. Flattening to one line of safe characters at the boundary means every consumer can treat the stored file as safe.

**The hook emits agent names, an integer, and status lines. Never message bodies.** Mail is untrusted input; it must enter context through the skill's read step where it is framed as coming from a peer, not injected at session start as if it came from the user.

**Deletion is scoped hard**: only `*.md`, only directly inside a `read/` directory, only under `$MAIL`, only past `ARCHIVE_DAYS`. Unread mail is never deleted at any age, and stale mailboxes are moved to `.retired/`, never removed.

**`find`, never a `*.md` glob.** zsh treats an unmatched glob as a shell-level error that `2>/dev/null` cannot suppress.

**`"$HOME"`, never `~`.** Tilde does not expand inside double quotes and you get a literal `~` directory.

## Dual packaging

One tree serves two specs. Do not generate one from the other.

- `plugin.json` at the root is [Agent Plugins 1.0.0](https://agent-plugins.org/) and its schema is **closed** — any top-level field outside `$schema, name, version, description, author, homepage, repository, license, keywords, extensions` is non-conformant, and CI fails on it. Client-specific data belongs under `extensions`.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` are Claude Code's.
- `skills/pigeonhole/SKILL.md` is at the path **both** specs discover. It exists once. Never copy it.
- Hooks are explicitly a client extension in the portable spec, so `hooks/hooks.json` serves Claude Code only. Other clients get no auto-join, which is why `AGENTS.md` tells an agent to run `join` itself. A change to session-start behaviour usually needs a matching line in AGENTS.md.

## Constraints

`bin/pigeonhole` is POSIX `sh` and runs under both dash (Ubuntu CI) and bash-as-sh (macOS). No bashisms, no arrays, no `[[`. `find` must satisfy BSD and GNU. `date` has no `%N` on macOS. `$RANDOM` silently evaluates to `0` under dash, so it can harden a filename but never be the only uniqueness source.

Keep it one shell script and the filesystem. A change needing a runtime, a package manager, or a daemon is the wrong change for this tool.

This repo is public. Examples use placeholder names (`api-dubai`, `web-castries`, `billing-accra-v2`, `PROJ-812`) — do not paste real workspace, repo, or ticket names into docs or tests.

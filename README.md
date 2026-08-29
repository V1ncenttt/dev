# simply/dev

A reusable way of running agent work on a repo — roles, the documents they share,
and the rules that keep them from stepping on each other.

**[AGENTS.md](AGENTS.md) is the system.** Read that. This file is only how to
adopt it.

## Adopt it in a project

    mkdir -p <project>/.claude
    ln -sfn ~/projects/simply/dev/agents <project>/.claude/agents
    ln -sfn ~/projects/simply/dev/AGENTS.md <project>/SYSTEM.md

Gitignore `/SYSTEM.md` — the link target is an absolute machine-specific path, so
committing it would hand a fresh clone a broken symlink. The project's own
`AGENTS.md` carries the two commands above so a clone can recreate the link.

Then give the project a root `AGENTS.md` that points at `@SYSTEM.md` — an
in-repo path an agent can find and trust (Chris: *"it's going to be hard for
random agents to read outside of repo"*) — and adds only what is true of that
project —
its gates, its crates, its paths, its doc filenames. Nothing a second project
would also want belongs there; it belongs here.

Lay the project out per the default structure in §3.

## Layout

    AGENTS.md     the system: roles, the doc web, the directory structure, the rules
    agents/       the six role definitions, symlinked into each project

## The six roles

`coder` · `researcher` · `tech-lead` · `designer` build in their own workspaces
and never move trunk. `integrator` works in the default workspace and is the only
one that lands. `patchbay` holds the conversation, the board and the briefs.

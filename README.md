# simply/dev

> **Fork of [poucet/dev](https://github.com/poucet/dev).** This branch (`vibe-claude`)
> adds Mistral **vibe** as a first-class harness alongside Claude Code and pi.dev.
> Upstream remains the source of truth; this fork exists to carry the vibe wiring
> until it lands (or stays here if it doesn't).

A reusable way of running agent work on a repo — roles, the documents they share,
and the rules that keep them from stepping on each other.

**[AGENTS.md](AGENTS.md) is the system.** Read that. This file is only how to
adopt it.

## Adopt it in a project

Run the installer:

    ~/projects/simply/dev/adopt.sh <project>

It is idempotent and never overwrites anything that already exists. It
copies `AGENTS.md` and symlinks the role definitions, lays out the doc web of §3
(ops skeletons, `docs/scratch/`, the human channel, `.workspaces/`,
`.screenshots/`), and appends the gitignore entries those need.

**The role definitions go in the directory your coding harness reads them
from — pick the one that matches the harness.** The script auto-detects
(`--harness pi|claude|vibe|both|all` to override, or a comma list like
`--harness claude,vibe`):

    # Claude Code — agents from .claude/agents  (symlinked)
    # pi.dev — personas from .pi/agents
    #   (also needs `projectPersonas: true` in ~/.pi/agent/subagents.json,
    #    and the project must be trusted — pi prompts on launch)
    # Mistral vibe — .vibe/agents/*.toml + .vibe/prompts/*.md
    #   (vibe splits each role into a TOML profile naming a system_prompt_id
    #    and a separate prompt .md with the persona body; adopt.sh generates
    #    both from agents/*.md, and the project must be trusted — vibe prompts
    #    on first launch. Re-run adopt.sh after editing a role to refresh them.)

The links' targets are absolute machine-specific paths, so they are gitignored;
the vibe-generated files are derived the same way and gitignored too. The
project's own `AGENTS.md` records the commands that recreate them (a fresh
clone runs the installer again).

The role files are shared verbatim between harnesses that read them directly
(Claude Code, pi.dev), so their frontmatter must stay valid for every harness
that reads them: **omit `tools`** (both harnesses then allow all tools —
Claude Code by inheritance, pi because it has no allow-all token and treats a
`tools:` list as literal names). Vibe does not read the `.md` directly — it
gets the persona from the generated prompt and tool/model settings from the
generated TOML — so the canonical role files stay the single source of truth.
Per-model or per-role tool restrictions are set by the harness config, not the
role files.

Lay the project out per the default structure in §3.

## A repo you don't own

For a shared repo you don't control (a work repo, reviewed by people who never
opted into any of this), don't run the installer inside it. Run it into a
sibling `ops/` directory instead, next to a plain clone of the shared repo —
see *A repo you don't own* in [AGENTS.md](AGENTS.md) §2. Nothing of this
system ever enters the shared repo except code, its tests, and a `CHANGELOG.md`
if the team already keeps one.

## Layout

    AGENTS.md     the system: roles, the doc web, the directory structure, the rules
    adopt.sh      the installer: symlinks + doc-web skeleton + gitignore, idempotent
    agents/       the eight role definitions, symlinked into each project
                  (.claude/agents for Claude Code, .pi/agents for pi.dev;
                   for Mistral vibe, generated into .vibe/agents/*.toml and
                   .vibe/prompts/*.md)

## The eight roles

`coder` · `researcher` · `tech-lead` · `designer` build in their own workspaces
and never move trunk. `integrator` works in the default workspace and is the only
one that lands. `scribe` keeps `BOARD.md` true, also in the default workspace and never at the
same time as `integrator`. `patchbay` holds the conversation and the briefs.

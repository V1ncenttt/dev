#!/usr/bin/env bash
#
# adopt.sh — install the simply/dev workflow into a project.
#
# Does four things, all idempotent (safe to re-run; nothing existing is
# overwritten):
#
#   1. copies AGENTS.md        -> this repo's AGENTS.md
#   2. wires the role definitions into the directory the coding harness in use
#      reads them from:
#        pi.dev       .pi/agents       (personas; needs projectPersonas: true
#                                       in ~/.pi/agent/subagents.json and a
#                                       trusted project)
#        Claude Code  .claude/agents   (subagents; symlinked)
#        Mistral vibe .vibe/agents/*.toml + .vibe/prompts/*.md
#                                     (vibe splits each role into a TOML
#                                      profile naming a system_prompt_id, and a
#                                      prompt .md holding the persona body —
#                                      both generated from agents/*.md)
#   3. lays out the doc web per AGENTS.md §3:
#        docs/ops/        BOARD CHANGELOG ISSUES IDEAS ROADMAP DECISIONS
#        docs/{design,research,guides,reference,archive}/  (.gitkeep)
#        docs/scratch/       STATUS.md   (gitignored)
#        .workspaces/  .screenshots/
#   4. appends the gitignore entries the above need, to the project's
#      .gitignore (created if absent). The symlink targets are machine-specific
#      absolute paths, so they must never be committed. The vibe-generated
#      files are derived from agents/*.md and gitignored the same way; re-run
#      the installer to refresh them after editing a role.
#
# Usage:
#   ./adopt.sh <project-dir> [--harness pi|claude|vibe|both|all|auto]
#                 (a comma list is also accepted, e.g. --harness claude,vibe)
#
#   --harness          which harness directory(s) to wire (default: auto —
#                      .vibe if the project has one, then .claude, else .pi)

#
set -euo pipefail

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "dev dir: $DEV_DIR"

usage() { sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

PROJECT=""
HARNESS="auto"

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help) usage 0 ;;
		--harness) HARNESS="${2:?}"; shift 2 ;;
		-*) echo "unknown option: $1" >&2; usage 1 >&2 ;;
		*) if [ -n "$PROJECT" ]; then echo "unexpected argument: $1" >&2; usage 1 >&2; fi
		   PROJECT="$1"; shift ;;
	esac
done

[ -n "$PROJECT" ] || usage 1 >&2
[ -d "$PROJECT" ] || { echo "not a directory: $PROJECT" >&2; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"

# Resolve the harness: explicit flag wins (a comma list is accepted, e.g.
# "claude,vibe"). "auto" wires .vibe if present, then .claude, else .pi.
if [ "$HARNESS" = "auto" ]; then
	if [ -d "$PROJECT/.vibe" ]; then HARNESS="vibe"
	elif [ -d "$PROJECT/.claude" ]; then HARNESS="claude"
	else HARNESS="pi"; fi
fi
case "$HARNESS" in
	both) HARNESS="pi,claude" ;;
	all)  HARNESS="pi,claude,vibe" ;;
esac
# Normalise into the space-separated ACTIVE set, validating each token.
ACTIVE=""
IFS=',' read -ra _tokens <<<"$HARNESS"
for _t in "${_tokens[@]}"; do
	case "$_t" in
		pi|claude|vibe) ACTIVE="$ACTIVE $_t" ;;
		*) echo "--harness must be pi, claude, vibe, both, all, or a comma list (got: $_t)" >&2; exit 1 ;;
	esac
done
ACTIVE="${ACTIVE# }"

# --- helpers -----------------------------------------------------------------

# Create a directory (and parents) if absent.
ensure_dir() { mkdir -p -- "$1"; }

# Ensure dir contains a .gitkeep so an empty tree survives in git.
ensure_gitkeep() { ensure_dir "$1"; [ -e "$1/.gitkeep" ] || touch "$1/.gitkeep"; }

# Ensure dir contains a .gitignore with wild card to ignore that directory.
ensure_untracked_dir() { ensure_dir "$1"; [ -e "$1/.gitignore" ] || echo '*' > "$1/.gitignore"; }

# Create a file with the given heredoc content only if it does not exist.
ensure_file() { # <path>
	local path="$1"
	[ -e "$path" ] && return 0
	cat > "$path"
}

# Symlink, refreshing a stale link but never clobbering a real file/directory.
link_into() { # <target> <link-path>
	local target="$1" link="$2"
	if [ -e "$link" ] && [ ! -L "$link" ]; then
		echo "  !! exists and is not a symlink, left alone: $link" >&2
		return 0
	fi
	ln -sfn -- "$target" "$link"
}

# Copy a file
copy_file() { # <target> <copy-path>
	local target="$1" copypath="$2"
	if [ -e "$copypath" ]; then
		echo "  !! exists, left alone: $copypath" >&2
		return 0
	fi
	cp -- "$target" "$copypath"
}

# Is a given harness in the ACTIVE set? (membership test for comma lists)
has_h() { # <token>
	case " $ACTIVE " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Generate the vibe harness files from agents/*.md: one TOML profile per role
# in .vibe/agents/ and one persona .md in .vibe/prompts/. Unlike the symlinks
# above these are derived files, so they are rewritten on every run (re-run
# adopt.sh after editing a role to refresh them). Requires python3.
generate_vibe_agents() { # <project-dir>
	local project="$1"
	if ! command -v python3 >/dev/null 2>&1; then
		echo "  !! python3 not found; skipped vibe generation" >&2
		return 0
	fi
	python3 - "$DEV_DIR" "$project" <<'PYEOF'
import sys, pathlib

dev, project = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
src = dev / "agents"
out_agents = project / ".vibe" / "agents"
out_prompts = project / ".vibe" / "prompts"
out_agents.mkdir(parents=True, exist_ok=True)
out_prompts.mkdir(parents=True, exist_ok=True)

def toml_s(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def split_frontmatter(text):
    # A leading "---\n" ... "---\n" block; body is everything after.
    if text.startswith("---\n"):
        parts = text.split("---\n", 2)
        if len(parts) == 3:
            return parts[1], parts[2]
    if text.startswith("---\r\n"):
        parts = text.split("---\r\n", 2)
        if len(parts) == 3:
            return parts[1], parts[2]
    return "", text

for md in sorted(src.glob("*.md")):
    meta = {}
    fm, body = split_frontmatter(md.read_text(encoding="utf-8"))
    for line in fm.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    name = meta.get("name", md.stem)
    desc = meta.get("description", "")
    display = name.replace("-", " ").replace("_", " ").title()
    toml = (
        f"# Generated by adopt.sh from agents/{name}.md — do not edit by hand;\n"
        f"# edit the role and re-run adopt.sh.\n"
        f"display_name = {toml_s(display)}\n"
        f"description = {toml_s(desc)}\n"
        f'safety = "neutral"\n'
        f'agent_type = "subagent"\n'
        f"# flip to \"agent\" to run this role with `vibe --agent {name}`\n"
        f"system_prompt_id = {toml_s(name)}\n"
    )
    (out_agents / f"{name}.toml").write_text(toml, encoding="utf-8")
    (out_prompts / f"{name}.md").write_text(body.lstrip("\n"), encoding="utf-8")
    print(f"  .vibe/agents/{name}.toml + .vibe/prompts/{name}.md")
PYEOF
}

# --- 1. AGENTS.md -------------------------------------------------------------

copy_file "$DEV_DIR/AGENTS.md" "$PROJECT/AGENTS.md"

# --- 2. harness agents wiring ------------------------------------------------

# pi and Claude Code read role files directly, so a symlink into the harness's
# agents directory is enough. vibe splits each role into a TOML profile and a
# separate prompt .md, so those are generated instead.
AGENT_DIRS=()
has_h pi     && AGENT_DIRS+=(".pi/agents")
has_h claude && AGENT_DIRS+=(".claude/agents")
for dir in "${AGENT_DIRS[@]+"${AGENT_DIRS[@]}"}"; do
	ensure_dir "$PROJECT/$(dirname "$dir")"
	ensure_untracked_dir "$PROJECT/$(dirname "$dir")"
	link_into "$DEV_DIR/agents" "$PROJECT/$dir"
done
if has_h vibe; then
	ensure_dir "$PROJECT/.vibe"
	ensure_untracked_dir "$PROJECT/.vibe/agents"
	ensure_untracked_dir "$PROJECT/.vibe/prompts"
	generate_vibe_agents "$PROJECT"
fi

# --- 3. the doc web (AGENTS.md §3) --------------------------------------------

OPS="$PROJECT/docs/ops"
ensure_dir "$OPS"

ensure_file "$OPS/BOARD.md" <<'EOF'
# Board

Line-items only; what belongs here is stated once in AGENTS.md §2. Scrathpad state
(what is running right now) lives in `docs/scratch/` — gitignored, invisible to
lanes; a lane gets its context from its brief, not from here.

Legend: 🚧 in flight · ✅ landed · ⏸ deferred.

## In flight

## Milestones

## Queued

## Deferred by decision

## Landed index
EOF

ensure_file "$OPS/CHANGELOG.md" <<'EOF'
# Changelog

What got added, per landing — dated with a clock and the jj change id. The entry
format is stated once in AGENTS.md §2.

## Unreleased
EOF

ensure_file "$OPS/ISSUES.md" <<'EOF'
# Issues

> What belongs here, and what does not: @AGENTS.md §2.
> 🐞 open · 🔬 triaged (cause known, fix specced) · 🔄 being fixed ·
> ✅ fixed · 🗑️ won't fix / not a bug. Sizes: S ≈ a session · M ≈ a lane.

| Status | Found | What | Verdict |
|---|---|---|---|
EOF

ensure_file "$OPS/IDEAS.md" <<'EOF'
# Ideas

An inbox: raw, half-formed, uncommitted. An idea only ever moves down; ids are
stable and never reused.

> What belongs here, and what does not: @AGENTS.md §2.
>
> Status: 💡 open · 🔶 partly answered by something that shipped · 🎯 next up ·
> 📋 specced and queued · 🔄 in flight · 🔬 being researched · ✅ shipped ·
> 🗑️ answered by deciding not to.

## Inbox
| Status | Added | # | Idea | Notes |
|---|---|---|---|---|

## In-flight
| Status | Added | # | Idea | Notes |
|---|---|---|---|---|

## Done
| Status | Added | # | Idea | Notes |
|---|---|---|---|---|
EOF

ensure_file "$OPS/ROADMAP.md" <<'EOF'
# Roadmap

> What belongs here, and what does not: @AGENTS.md §2. 

Each horizon is one **story line** from @docs/ops/IDEAS.md carried to a usable
state, ordered so every phase makes the next cheaper. Phases are themes, not
gates: a row can be pulled forward whenever it's wanted — say its `LABEL` if it
is on the board, otherwise ask and it gets specced.

> Status: 🔄 in flight · ⏸️ started then paused · 📋 specced & queued on
> @docs/ops/BOARD.md · 🔶 partly shipped (the account is in the changelog; what
> is left is in the row) · 🎯 next up · ⬜ open, not scheduled anyw

| St | Size | Item | Ideas |
|---|---|---|---|
EOF

ensure_file "$OPS/DECISIONS.md" <<'EOF'
# Decisions

ADR-lite: small-but-binding decisions with their rationale, newest first —
things too small for a design doc but too important to live only in commit
messages or conversation. Big designs stay in docs/design/; findings in
docs/research/. One line of context each; link deeper docs where they exist.

One row, one decision, one date — so a settled question stays settled. Carries
both a clock and the jj change id (AGENTS.md §2).

| When · change id | Decision | Rationale |
|---|---|---|
EOF

# The decay-free doc kinds: empty, gitkeep'd.
for kind in design research guides reference archive; do
	ensure_gitkeep "$PROJECT/docs/$kind"
done

# The scratch, workspaces and screenshots directories.
ensure_untracked_dir "$PROJECT/docs/scratch"
ensure_untracked_dir "$PROJECT/.workspaces"
ensure_untracked_dir "$PROJECT/.screenshots"

# --- report -------------------------------------------------------------------

echo "Adopted simply/dev into $PROJECT (harness: $ACTIVE)."
echo "  AGENTS.md -> $DEV_DIR/AGENTS.md"
for dir in "${AGENT_DIRS[@]+"${AGENT_DIRS[@]}"}"; do
	echo "  $dir -> $DEV_DIR/agents"
done
echo "  docs/ops/, docs/{design,research,guides,reference,archive}/, docs/scratch/"
echo "  .workspaces/, .screenshots/"
if has_h pi; then
	echo
	echo "Reminders for pi:"
	echo "  - set \"projectPersonas\": true in ~/.pi/agent/subagents.json"
	echo "  - trust the project when pi prompts on next launch"
fi
if has_h vibe; then
	echo
	echo "Reminders for vibe:"
	echo "  - trust the project when vibe prompts on first launch"
	echo "  - roles are subagents; dispatch them via the task tool, or flip"
	echo "    agent_type to \"agent\" in .vibe/agents/<role>.toml to run a role"
	echo "    as the primary agent with: vibe --agent <role>"
fi
echo

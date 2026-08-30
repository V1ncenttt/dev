#!/usr/bin/env bash
#
# adopt.sh — install the simply/dev workflow into a project.
#
# Does four things, all idempotent (safe to re-run; nothing existing is
# overwritten):
#
#   1. copies AGENTS.md        -> this repo's AGENTS.md
#   2. symlinks the role definitions into the directory the coding harness
#      in use reads them from:
#        pi.dev       .pi/agents       (personas; needs projectPersonas: true
#                                       in ~/.pi/agent/subagents.json and a
#                                       trusted project)
#        Claude Code  .claude/agents   (subagents)
#   3. lays out the doc web per AGENTS.md §3:
#        docs/ops/        BOARD CHANGELOG ISSUES IDEAS ROADMAP DECISIONS
#        docs/{design,research,guides,reference,archive}/  (.gitkeep)
#        docs/scratch/       STATUS.md   (gitignored)
#        .workspaces/  .screenshots/
#   4. appends the gitignore entries the above need, to the project's
#      .gitignore (created if absent). The symlink targets are machine-specific
#      absolute paths, so they must never be committed.
#
# Usage:
#   ./adopt.sh <project-dir> [--harness pi|claude|both|auto]
#
#   --harness          which harness directory(s) to wire (default: auto —
#                      .claude if the project has one, else .pi)

#
set -euo pipefail

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

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

# Resolve the harness: explicit flag wins; auto picks .claude if the project
# already has one, else .pi.
if [ "$HARNESS" = "auto" ]; then
	if [ -d "$PROJECT/.claude" ]; then HARNESS="claude"; else HARNESS="pi"; fi
fi
case "$HARNESS" in
	pi|claude|both) ;;
	*) echo "--harness must be pi, claude, both or auto (got: $HARNESS)" >&2; exit 1 ;;
esac

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
copy_file() { <target> <copy-path>
	local target="$1" copypath="$2"
	if [ -e "$copypath" ]; then
		echo "  !! exists, left alone: $link" >&2
		return 0
	fi
	cp -- "target" "copypath"
}

# --- 1. AGENTS.md -------------------------------------------------------------

copy_file "$DEV_DIR/AGENTS.md" "$PROJECT/AGENTS.md"

# --- 2. harness agents symlink ------------------------------------------------

AGENT_DIRS=()
[ "$HARNESS" = "pi" ] || [ "$HARNESS" = "both" ] && AGENT_DIRS+=(".pi/agents")
[ "$HARNESS" = "claude" ] || [ "$HARNESS" = "both" ] && AGENT_DIRS+=(".claude/agents")
for dir in "${AGENT_DIRS[@]}"; do
	ensure_dir "$PROJECT/$(dirname "$dir")"
	ensure_untracked_dir "$PROJECT/$(dirname "$dir")"
	link_into "$DEV_DIR/agents" "$PROJECT/$dir"
done

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

echo "Adopted simply/dev into $PROJECT (harness: $HARNESS)."
echo "  AGENTS.md -> $DEV_DIR/AGENTS.md"
for dir in "${AGENT_DIRS[@]}"; do
	echo "  $dir -> $DEV_DIR/agents"
done
echo "  docs/ops/, docs/{design,research,guides,reference,archive}/, docs/scratch/"
echo "  .workspaces/, .screenshots/"
if [ "$HARNESS" = "pi" ] || [ "$HARNESS" = "both" ]; then
	echo
	echo "Reminders for pi:"
	echo "  - set \"projectPersonas\": true in ~/.pi/agent/subagents.json"
	echo "  - trust the project when pi prompts on next launch"
fi
echo
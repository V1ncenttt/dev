#!/usr/bin/env bash
#
# adopt.sh — install the simply/dev workflow into a project.
#
# Does four things, all idempotent (safe to re-run; nothing existing is
# overwritten):
#
#   1. symlinks SYSTEM.md        -> this repo's AGENTS.md
#   2. symlinks the role definitions into the directory the coding harness
#      in use reads them from:
#        pi.dev       .pi/agents       (personas; needs projectPersonas: true
#                                       in ~/.pi/agent/subagents.json and a
#                                       trusted project)
#        Claude Code  .claude/agents   (subagents)
#   3. lays out the doc web per SYSTEM.md §3:
#        docs/ops/        BOARD CHANGELOG ISSUES IDEAS ROADMAP DECISIONS
#        docs/{design,research,guides,reference,archive}/  (.gitkeep)
#        docs/live/       STATUS.md   (gitignored)
#        .workspaces/  .screenshots/progress/
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

# Create a file with the given heredoc content only if it does not exist.
ensure_file() { # <path>
	local path="$1"
	[ -e "$path" ] && return 0
	cat > "$path"
}

# Append a gitignore line if it is not present (exact-line match).
add_ignore() { # <project> <line>
	local line="$2"
	local gitignore="$1/.gitignore"
	touch "$gitignore"
	grep -qxF -- "$line" "$gitignore" || printf '%s\n' "$line" >> "$gitignore"
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

# --- 1. SYSTEM.md -------------------------------------------------------------

link_into "$DEV_DIR/AGENTS.md" "$PROJECT/SYSTEM.md"

# --- 2. harness agents symlink ------------------------------------------------

AGENT_DIRS=()
[ "$HARNESS" = "pi" ] || [ "$HARNESS" = "both" ] && AGENT_DIRS+=(".pi/agents")
[ "$HARNESS" = "claude" ] || [ "$HARNESS" = "both" ] && AGENT_DIRS+=(".claude/agents")
for dir in "${AGENT_DIRS[@]}"; do
	ensure_dir "$PROJECT/$(dirname "$dir")"
	link_into "$DEV_DIR/agents" "$PROJECT/$dir"
done

# --- 3. the doc web (SYSTEM.md §3) --------------------------------------------

OPS="$PROJECT/docs/ops"
ensure_dir "$OPS"

ensure_file "$OPS/BOARD.md" <<'EOF'
# Board

Line-items only; what belongs here is stated once in SYSTEM.md §2. Live state
(what is running right now) lives in `docs/live/` — gitignored, invisible to
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
format is stated once in SYSTEM.md §2.

## Unreleased
EOF

ensure_file "$OPS/ISSUES.md" <<'EOF'
# Issues

A parking lot, not a queue — defects and rough edges noticed in passing; nothing
here is scheduled until promoted onto the board. What belongs here is stated once
in SYSTEM.md §2.

| Status | Found | What | Verdict |
|---|---|---|---|
EOF

ensure_file "$OPS/IDEAS.md" <<'EOF'
# Ideas

An inbox: raw, half-formed, uncommitted. An idea only ever moves down; ids are
stable and never reused. What belongs here is stated once in SYSTEM.md §2.

## Inbox

## In-flight

## Done
EOF

ensure_file "$OPS/ROADMAP.md" <<'EOF'
# Roadmap

Horizons and versions, and what a version means in the register of the ones
before it. Only what is not done — finished work is the changelog's. See
SYSTEM.md §2.
EOF

ensure_file "$OPS/DECISIONS.md" <<'EOF'
# Decisions

One row, one decision, one date — so a settled question stays settled. Carries
both a clock and the jj change id (SYSTEM.md §2).

| When · change id | Decision | Rationale |
|---|---|---|
EOF

# The decay-free doc kinds: empty, gitkeep'd.
for kind in design research guides reference archive; do
	ensure_gitkeep "$PROJECT/docs/$kind"
done

# The live directory — gitignored, rewritten freely, invisible to lanes.
ensure_dir "$PROJECT/docs/live"
ensure_file "$PROJECT/docs/live/STATUS.md" <<'EOF'
# Live status

What is running, what is ready and unintegrated, where trunk is, what waits on
the human. Gitignored (this whole directory is), so it can be rewritten at any
time — including mid-integration — without dirtying the working copy. Invisible
to lanes; a lane gets its context from its brief.
EOF

# Workspaces and screenshots.
ensure_dir "$PROJECT/.workspaces"
ensure_dir "$PROJECT/.screenshots/progress"

# --- 4. gitignore -------------------------------------------------------------

add_ignore "$PROJECT" "SYSTEM.md"
add_ignore "$PROJECT" ".workspaces/"
add_ignore "$PROJECT" ".screenshots/"
add_ignore "$PROJECT" "docs/live/"
for dir in "${AGENT_DIRS[@]}"; do
	add_ignore "$PROJECT" "$dir"
done

# --- report -------------------------------------------------------------------

echo "Adopted simply/dev into $PROJECT (harness: $HARNESS)."
echo "  SYSTEM.md -> $DEV_DIR/AGENTS.md"
for dir in "${AGENT_DIRS[@]}"; do
	echo "  $dir -> $DEV_DIR/agents"
done
echo "  docs/ops/, docs/{design,research,guides,reference,archive}/, docs/live/, $HUMAN_CHANNEL/"
echo "  .workspaces/, .screenshots/progress/"
if [ "$HARNESS" = "pi" ] || [ "$HARNESS" = "both" ]; then
	echo
	echo "Reminders for pi:"
	echo "  - set \"projectPersonas\": true in ~/.pi/agent/subagents.json"
	echo "  - trust the project when pi prompts on next launch"
fi
echo
echo "Next: give the project a root AGENTS.md that points at @SYSTEM.md and adds"
echo "only what is true of that project (its gates, its paths)."

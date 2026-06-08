#!/usr/bin/env bash
# setup-worktree-deps.sh — symlink heavy dependency dirs from the parent clone
# into the current git worktree so the first commit's pre-commit hooks (which
# expect .venv / node_modules) do not fail on a fresh worktree (dotfiles#516 AC 4.2).
#
# WHAT  When run from inside a git worktree, links .venv and node_modules from
#       the main working tree (git common dir's parent) into the worktree, if
#       they exist in the parent and are absent in the worktree.
# WHY   EnterWorktree creates an isolated checkout with no .venv / node_modules;
#       the pre-commit framework + node syntax checks then fail on commit 1.
# USAGE bash scripts/setup-worktree-deps.sh        # run once, right after EnterWorktree
# EXIT  0 always (idempotent; logs each decision — never silently no-ops).
set -uo pipefail

log() { printf '[setup-worktree-deps] %s\n' "$*" >&2; }

git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
  log "ERROR not inside a git repository — nothing to do (exit 0)"
  exit 0
}

# The main working tree is the parent of the common .git dir.
main_worktree="$(cd "$(dirname "$git_common_dir")" && pwd)"
worktree_root="$(git rev-parse --show-toplevel 2>/dev/null)"

if [[ "$main_worktree" == "$worktree_root" ]]; then
  log "INFO running in the main working tree (not a worktree) — no linking needed"
  exit 0
fi

log "INFO main clone: $main_worktree"
log "INFO worktree:   $worktree_root"

linked=0
for dep in .venv node_modules; do
  src="$main_worktree/$dep"
  dst="$worktree_root/$dep"
  if [[ -e "$dst" || -L "$dst" ]]; then
    log "SKIP $dep already present in worktree"
    continue
  fi
  if [[ ! -d "$src" ]]; then
    log "SKIP $dep absent in main clone — nothing to link"
    continue
  fi
  ln -s "$src" "$dst"
  log "LINK $dep -> $src"
  linked=$((linked + 1))
done

log "DONE linked $linked dependency dir(s)"
exit 0

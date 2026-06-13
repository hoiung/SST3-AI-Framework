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

# Nested node_modules (dotfiles#528 AC 5.1): a multi-package repo (e.g. a `frontend/`
# subdir) keeps its node_modules one level down, which the top-level loop misses. Link
# each immediate-subdir node_modules too. Iterate only the depth-1 subdirs (never descend
# INTO the huge top-level node_modules) so this stays fast.
for sub in "$main_worktree"/*/; do
  [[ -d "${sub}node_modules" ]] || continue
  rel="$(basename "$sub")/node_modules"
  nested_dst="$worktree_root/$rel"
  if [[ -e "$nested_dst" || -L "$nested_dst" ]]; then
    log "SKIP $rel already present in worktree"
    continue
  fi
  mkdir -p "$(dirname "$nested_dst")"
  ln -s "${sub}node_modules" "$nested_dst"
  log "LINK $rel -> ${sub}node_modules"
  linked=$((linked + 1))
done

# .env (dotfiles#528 AC 5.1): provision into the worktree as a COPY, NOT a symlink —
# env files legitimately differ per worktree (a symlink would force the worktree to
# share the parent's secrets) — chmod 600. HARD GUARD: copy ONLY if `.env` is gitignored
# in the worktree, so a secrets file can never become committable. `git check-ignore`
# is the authoritative test (honours the worktree's own .gitignore + the global excludes).
env_src="$main_worktree/.env"
env_dst="$worktree_root/.env"
if [[ -e "$env_dst" || -L "$env_dst" ]]; then
  log "SKIP .env already present in worktree"
elif [[ ! -f "$env_src" ]]; then
  log "SKIP .env absent in main clone — nothing to copy"
elif ! git -C "$worktree_root" check-ignore -q .env; then
  log "SKIP .env is NOT gitignored in the worktree — refusing to copy a committable secrets file (add .env to .gitignore first)"
else
  cp "$env_src" "$env_dst"
  chmod 600 "$env_dst"
  log "COPY .env -> $env_dst (mode 600, gitignored — never a symlink)"
  linked=$((linked + 1))
fi

log "DONE linked $linked dependency dir(s)"
exit 0

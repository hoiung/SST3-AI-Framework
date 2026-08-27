#!/usr/bin/env bash
# sst3-grep-before-write.sh — F-11 PreToolUse Grep-before-write (#498 AC 2.12).
#
# WHAT  Claude Code PreToolUse Write matcher. Fires when the agent is about to
#       Write to a path under `src/` / `SST3/` / `claude/` / `scripts/`. Greps
#       the repo for similarly-named files (by basename without extension);
#       on matches, emits stderr WARN listing existing files the agent should
#       check FIRST per AP #10 (grep-before-writing).
#
# WHY   RC-2 + RC-6 (Memory-Pattern-Bias + Scope-Creep): the agent reflexively
#       creates a "new" helper / hook / rule even when an existing surface
#       could be extended. The WARN surfaces existing candidates BEFORE the
#       Write lands, so the agent gets a chance to consult them.
#
# SCOPE
#   FIRES when target path matches: src/ SST3/ claude/ scripts/
#   EXCLUDES /tmp/ _drafts/ _archive/ docs/research/
#   BYPASS  SST3_GREP_BEFORE_WRITE_OVERRIDE=1 → exit 0 silent
#
# CONTRACT  stdin = PreToolUse JSON. `.tool_input.file_path` extracted.
#       jq + git required. Missing tools → exit 1 advisory (no block).
#
# REVERSIBLE  Remove the Write-matcher hook entry from claude/settings.json.
set -uo pipefail

OVERRIDE="${SST3_GREP_BEFORE_WRITE_OVERRIDE:-0}"
[[ "$OVERRIDE" == "1" ]] && exit 0

# GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE / GIT_COMMON_DIR / GIT_OBJECT_DIRECTORY each
# OVERRIDE an explicit repo selection, and git hooks plus the pre-commit framework export
# them into child processes routinely. Unscrubbed, the repo-root resolution below returns
# whatever repo the PARENT was in, so the AP #10 gate lists sibling files from the WRONG
# repository — and reports a clean "no similar files" for a repo it never looked at
# (dotfiles#569; doctrine AP #31). Scrubbed before ANY git call.
# shellcheck source=_lib-repo-identity.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib-repo-identity.sh"
sst3_scrub_git_env

if ! command -v jq >/dev/null 2>&1; then
  printf 'F-11 grep-before-write: jq missing; pre-write grep skipped.\n' >&2
  exit 1
fi

raw_stdin="$(cat 2>/dev/null || true)"
PATH_TARGET="$(printf '%s' "$raw_stdin" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[[ -z "$PATH_TARGET" ]] && exit 0

# Strip leading absolute prefix to a repo-relative form (best-effort).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
if [[ -n "$REPO_ROOT" ]] && [[ "$PATH_TARGET" == "$REPO_ROOT"/* ]]; then
  REL="${PATH_TARGET#"$REPO_ROOT"/}"
else
  REL="$PATH_TARGET"
fi

# Exclude FIRST so /tmp/foo/src/bar.sh is correctly silent (excluded dirs win).
if [[ "$REL" == /tmp/* || "$REL" == */tmp/* \
   || "$REL" == _drafts/* || "$REL" == */_drafts/* \
   || "$REL" == _archive/* || "$REL" == */_archive/* \
   || "$REL" == docs/research/* || "$REL" == */docs/research/* ]]; then
  exit 0
fi

# Scope check — only fire on the scoped dirs.
case "$REL" in
  src/*|SST3/*|claude/*|scripts/*) : ;;   # in-scope
  *) exit 0 ;;                            # outside scope → silent
esac

# If the file already exists, this is an update, not a new write — no need
# to grep-before-write. The pattern fires on NEW file creation.
if [[ -e "$REPO_ROOT/$REL" ]]; then
  exit 0
fi

# Basename without extension as the search needle. To catch sibling-files in a
# naming family (e.g. new `sst3-branch-helper.sh` near existing
# `sst3-branch-guard.sh`), strip the final segment after the last `-` or `_`
# and use the resulting prefix as the grep needle. Falls back to the full stem
# when the stem has no separator.
BASE="$(basename "$REL")"
STEM="${BASE%.*}"
NEEDLE="${STEM%[-_]*}"
[[ -z "$NEEDLE" || "$NEEDLE" == "$STEM" ]] && NEEDLE="$STEM"
# Discard trivial needles that would match everything.
if [[ -z "$NEEDLE" || ${#NEEDLE} -lt 4 ]]; then
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  printf 'F-11 grep-before-write: git missing; pre-write grep skipped.\n' >&2
  exit 1
fi

# Use `git ls-files` so the search respects .gitignore.
MATCHES="$(git -C "$REPO_ROOT" ls-files 2>/dev/null | grep -F "$NEEDLE" | grep -v "^$REL$" | head -20 || true)"
if [[ -n "$MATCHES" ]]; then
  printf 'F-11 grep-before-write: new file `%s` matches existing files by name stem `%s` (AP #10).\n' "$REL" "$NEEDLE" >&2
  printf 'Consider extending one of these instead of creating a new file:\n' >&2
  while IFS= read -r m; do printf '  - %s\n' "$m" >&2; done <<<"$MATCHES"
  printf '  (Override: SST3_GREP_BEFORE_WRITE_OVERRIDE=1)\n' >&2
fi
exit 0

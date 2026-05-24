#!/usr/bin/env bash
# claude/hooks/_lib-branch-issue.sh — shared helper sourced by hooks that derive
# the active Issue number from the worktree's branch name (#498 Stage 5 L1C F2).
#
# Defines:
#   derive_issue_num_from_branch  echoes the issue number (digits only) for
#                                 branch names of the form `solo/issue-N-...`
#                                 or `worktree-solo+issue-N-...`. Echoes empty
#                                 string when not in a git repo, no branch, or
#                                 branch doesn't match the convention.
#
# Sourced by: sst3-session-context-injector.sh, sst3-tier-a-ac-binding-gate.sh.
# Single source of truth — if the branch convention changes, update only here.

derive_issue_num_from_branch() {
  local branch issue_num
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  issue_num="$(printf '%s' "$branch" | grep -oE 'issue-[0-9]+' | head -1 | cut -d- -f2 || printf '')"
  printf '%s' "$issue_num"
}

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
# Mirrors the canonical solo-branch convention (sst3_utils.SOLO_BRANCH_RE /
# sst3-bash-utils.sh::sst3_solo_branch_alt, #509 AC6.5) — keep the anchored
# pattern below in sync with that canonical if the convention changes.

derive_issue_num_from_branch() {
  local branch issue_num
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
  # Anchored to the solo / worktree-solo convention ONLY (the `^...solo[/+-]issue-`
  # prefix mirrors SOLO_BRANCH_RE). A bare `issue-N` on a non-solo branch
  # (e.g. `feature/issue-42`) must NOT yield a spurious issue number — that
  # would inject false issue context into the session-context-injector and
  # the Tier-A AC-binding gate. (#509 Stage-5: 6th branch-matcher site unified.)
  issue_num="$(printf '%s' "$branch" | grep -oE '^(worktree-)?solo[/+-]issue-[0-9]+' | grep -oE '[0-9]+$' || printf '')"
  printf '%s' "$issue_num"
}

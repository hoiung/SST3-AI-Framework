#!/usr/bin/env bash
# sst3-tier-a-ac-binding-gate.sh — F-4 Tier-A AC binding gate (#498 AC 2.8).
#
# WHAT  Claude Code Stop hook. Reads the current Issue body (via gh CLI inferred
#       from branch name); for every Tier-A AC checkbox that is `[ ]` (unticked)
#       AND lacks a `[deferred-…]` annotation AND maps to phase-completion
#       criteria, emits a WARN message to stderr.
#
# WHY   AP #20 binding-gate cadence requires Tier-A boxes MCP-ticked at each
#       phase boundary; the Stop hook is the silently-uncommon failure mode
#       (agent reaches Stop without closing out). WARN-first for 1-2 weeks to
#       gather FP-rate data; DENY upgrade after the rate is acceptable.
#
# CONTRACT  gh CLI required to read Issue body. Absent gh → exit 0 silent
#       (do not block the Stop event). jq required to parse. Both missing →
#       exit 0 silent (advisory hook, never blocks Stop).
#
# REVERSIBLE  Remove Stop hook entry from claude/settings.json.
set -uo pipefail

if ! command -v gh >/dev/null 2>&1; then
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Derive issue number from current branch via shared helper (#498 Stage 5 L1C F2
# — AP #9 single-source).
# shellcheck source=_lib-branch-issue.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib-branch-issue.sh"
# shellcheck source=_lib-repo-identity.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib-repo-identity.sh"

# Scrubbed HERE, at top level, and not relied on transitively. `derive_issue_num_from_branch`
# does scrub, but every call site of it is a command substitution — and `unset` inside `$( )`
# runs in a subshell, so it never reaches this shell. `gh` resolves its repository from the
# git environment exactly as `git` does, so an inherited GIT_DIR sends the `gh issue view`
# below to the PARENT process's repository: the right issue NUMBER read from the wrong REPO.
# Measured (#569 Stage 5): with GIT_DIR pointing at repo A and cwd in repo B, this hook read
# A's issue body and warned about A's unticked ACs while claiming to act for B.
sst3_scrub_git_env

ISSUE_NUM="$(derive_issue_num_from_branch)"
[[ -z "$ISSUE_NUM" ]] && exit 0   # Not on an issue branch.

BODY="$(gh issue view "$ISSUE_NUM" --json body --jq '.body' 2>/dev/null || printf '')"
[[ -z "$BODY" ]] && exit 0

# Tier-A AC pattern: lines starting with `- [ ] **AC ` (loosely — could be
# `- [ ]   **AC X.Y**`). Phase-completion criteria: AC X.Y where presence of
# "Verification:" indicates a binary-gate AC (Tier A).
UNTICKED_COUNT=0
while IFS= read -r line; do
  # Skip lines with `[deferred-...]` annotation.
  if [[ "$line" == *'[deferred-'* ]]; then
    continue
  fi
  # Skip Tier-B / non-AC checkboxes.
  if [[ ! "$line" =~ ^[[:space:]]*-\ \[\ \].*\*\*AC[[:space:]] ]]; then
    continue
  fi
  # Require an indicator that this is binary/verifiable (Verification: clause).
  if [[ "$line" == *"Verification:"* || "$line" == *"verification:"* ]]; then
    UNTICKED_COUNT=$((UNTICKED_COUNT + 1))
  fi
done <<<"$BODY"

if [[ $UNTICKED_COUNT -gt 0 ]]; then
  printf 'F-4 Tier-A AC binding gate: %d unticked Tier-A AC(s) on Issue #%s.\n' \
    "$UNTICKED_COUNT" "$ISSUE_NUM" >&2
  printf '  WARN-first mode: command proceeds, but MCP-tick before next phase per AP #20.\n' >&2
  printf '  Use `mcp__github-checkbox__update_issue_checkbox` to close with evidence.\n' >&2
fi

exit 0

#!/usr/bin/env bash
# sst3-session-context-injector.sh — SST3 SessionStart context injector (dotfiles#498 F-1)
#
# WHAT  Claude Code SessionStart hook (matchers: startup / resume / compact).
#       Emits a JSON envelope whose `additionalContext` carries 4 deterministic
#       fields the agent needs at session entry but historically forgot:
#         (a) verbatim operator task from ~/handover/current-task.txt if present
#         (b) active Issue + AC status (gh issue view --json title,body,labels)
#         (c) Reading Confirmation Checklist literal text
#         (d) post-compact mandatory re-read directive
#
# WHY   RC-1 (Prose-Rule Substrate Failure) + RC-2 (Memory-Pattern-Bias):
#       canon prose alone does not survive a compact. A SessionStart hook fires
#       at startup AND every post-compact resume, so the agent re-enters with
#       the literal mandatory-reading checklist in context rather than relying
#       on memory of having read it earlier. Zero context-window weight per
#       session beyond the emitted text itself.
#
# OUTPUT MODES
#   default (live)  Emits the Claude Code hook envelope:
#                     {"hookSpecificOutput":{"hookEventName":"SessionStart",
#                                            "additionalContext":"<flat str>"}}
#   --test          Emits a structured object form for jq verification:
#                     {"additionalContext":{
#                        "operator_task":"…",
#                        "active_issue":{…},
#                        "reading_checklist":["…","…",…],
#                        "post_compact_directive":"…"}}
#       Both forms always exit 0 — this hook is informational, never blocking.
#
# CONTRACT  jq must be available (install via <your-dotfiles-clone>/scripts/install.sh). gh may be
#       absent — graceful-degrade to a placeholder string for field (b).
#       ~/handover/current-task.txt may be absent — graceful-degrade likewise.
#
# REVERSIBLE  Remove the SessionStart hook block from claude/settings.json or
#       set `"disableAllHooks": true`. Zero residual state.
set -uo pipefail

# Resume pointer (dotfiles#510): default is ~/handover/current-task.txt — written to
# $HOME (NOT a literal `~`, which bash does not expand inside a ${VAR:-…} default) so
# it survives a WSL VM idle-reap / reboot, unlike the legacy /tmp location.
TASK_FILE="${SST3_CURRENT_TASK_FILE:-$HOME/handover/current-task.txt}"
MODE="${1:-live}"

if ! command -v jq >/dev/null 2>&1; then
  # Degraded path — emit empty envelope so SessionStart does not stall.
  printf '{}\n'
  exit 0
fi

# (a) Verbatim operator task — preserved exactly as written; never paraphrased.
if [[ -r "$TASK_FILE" ]]; then
  OPERATOR_TASK="$(cat "$TASK_FILE" 2>/dev/null || printf '')"
else
  OPERATOR_TASK=""
fi

# (b) Active Issue + AC status. gh inferred from cwd; absent gh degrades cleanly.
ACTIVE_ISSUE_JSON='{}'
if command -v gh >/dev/null 2>&1; then
  # Branch name like worktree-solo+issue-498-foo or solo/issue-498-foo → issue #498.
  # Derivation lives in shared helper (#498 Stage 5 L1C F2 — AP #9 single-source).
  # shellcheck source=_lib-branch-issue.sh
  source "$(dirname "${BASH_SOURCE[0]}")/_lib-branch-issue.sh"
  ISSUE_NUM="$(derive_issue_num_from_branch)"
  if [[ -n "$ISSUE_NUM" ]]; then
    ACTIVE_ISSUE_JSON="$(gh issue view "$ISSUE_NUM" --json number,title,labels 2>/dev/null || printf '{}')"
    [[ -z "$ACTIVE_ISSUE_JSON" ]] && ACTIVE_ISSUE_JSON='{}'
  fi
fi

# (c) Reading Confirmation Checklist — literal text per CLAUDE.md.
READ_CHECKLIST_JSON="$(jq -nc '[
  "Read STANDARDS.md",
  "Read ANTI-PATTERNS.md",
  "Read WORKFLOW.md",
  "Read project CLAUDE.md",
  "Read active Issue body line-by-line"
]')"

# (d) Post-compact directive — fires at every resume, not just startup.
POST_COMPACT_DIRECTIVE="Post-compact recovery: re-read CLAUDE.md + STANDARDS.md + ANTI-PATTERNS.md + WORKFLOW.md + active Issue. Do NOT resume from memory. Memory of prior reads is NOT a substitute — files change."

# Build the additionalContext object.
CTX_OBJ="$(jq -nc \
  --arg task "$OPERATOR_TASK" \
  --argjson issue "$ACTIVE_ISSUE_JSON" \
  --argjson checklist "$READ_CHECKLIST_JSON" \
  --arg directive "$POST_COMPACT_DIRECTIVE" \
  '{operator_task:$task, active_issue:$issue, reading_checklist:$checklist, post_compact_directive:$directive}')"

if [[ "$MODE" == "--test" ]]; then
  # Test mode: emit structured form so AC 2.1 jq verification works.
  jq -nc --argjson ctx "$CTX_OBJ" '{additionalContext:$ctx}'
  exit 0
fi

# Live mode: flatten to string, wrap in Claude Code hook envelope.
FLAT="$(jq -nr --argjson ctx "$CTX_OBJ" '
  "=== SST3 Session Context ===\n" +
  "Operator task: " + ($ctx.operator_task // "(none captured)") + "\n" +
  "Active Issue: " + (($ctx.active_issue | tostring) // "(none)") + "\n" +
  "Mandatory reading:\n" + ($ctx.reading_checklist | map("  - " + .) | join("\n")) + "\n" +
  "Directive: " + $ctx.post_compact_directive')"

jq -nc \
  --arg flat "$FLAT" \
  '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$flat}}'
exit 0

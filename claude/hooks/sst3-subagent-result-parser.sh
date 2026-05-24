#!/usr/bin/env bash
# sst3-subagent-result-parser.sh — F-7 SubagentStop RESULT-block parser (#498 AC 2.10).
#
# WHAT  Claude Code SubagentStop hook. Parses the subagent transcript for a
#       fenced `## RESULT` block; verifies required fields present
#       (verdict, files_touched, findings, tee_log, scope_gaps). When the
#       block mentions graph queries, verifies `mcp_graph_available: yes|no`
#       is the FIRST line of the block (AP #19 contract).
#
# WHY   RC-4 (Layer-1 unilateral angle coverage): subagents that omit the
#       RESULT block — or omit mcp_graph_available — disable downstream
#       cross-validation. WARN-first: stderr advisory, exit 0; agent sees
#       the warning at the SubagentStop boundary, can correct in the next
#       dispatch.
#
# CONTRACT  stdin = SubagentStop event JSON. The full subagent transcript
#       lives at `.transcript_path` (a file path the runtime hands the hook).
#       jq required; fail-toward-silent on missing tools to avoid blocking.
#
# REVERSIBLE  Remove the SubagentStop hook entry from claude/settings.json.
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

raw_stdin="$(cat 2>/dev/null || true)"
[[ -z "$raw_stdin" ]] && exit 0

# Transcript path conventions (Claude Code SubagentStop event shape).
TRANSCRIPT="$(printf '%s' "$raw_stdin" | jq -r '.transcript_path // .transcriptPath // empty' 2>/dev/null)"

if [[ -z "$TRANSCRIPT" || ! -r "$TRANSCRIPT" ]]; then
  # Older runtimes may inline the transcript directly under `.transcript`.
  RESPONSE="$(printf '%s' "$raw_stdin" | jq -r '.response // .transcript // empty' 2>/dev/null)"
  if [[ -z "$RESPONSE" ]]; then
    exit 1   # Runtime error — neither path nor inline transcript. Advisory.
  fi
else
  RESPONSE="$(cat "$TRANSCRIPT" 2>/dev/null || printf '')"
fi

[[ -z "$RESPONSE" ]] && exit 0

# Locate the `## RESULT` block. Tolerant of various fence styles.
RESULT_BLOCK="$(printf '%s' "$RESPONSE" | awk '
  /^[[:space:]]*##[[:space:]]+RESULT[[:space:]]*$/ { found=1; next }
  found && /^[[:space:]]*##[[:space:]]/ { found=0 }
  found { print }
')"

if [[ -z "${RESULT_BLOCK//[[:space:]]/}" ]]; then
  printf 'F-7 subagent-result-parser: subagent emitted no `## RESULT` block (AP #14 / RC-4).\n' >&2
  exit 0   # WARN-only.
fi

# Required fields.
MISSING_FIELDS=()
for field in "verdict:" "files_touched:" "findings:" "tee_log:" "scope_gaps:"; do
  if ! printf '%s' "$RESULT_BLOCK" | grep -qF "$field"; then
    MISSING_FIELDS+=("$field")
  fi
done

if [[ ${#MISSING_FIELDS[@]} -gt 0 ]]; then
  printf 'F-7 subagent-result-parser: RESULT block missing fields: %s\n' "${MISSING_FIELDS[*]}" >&2
fi

# Graph-query discussion → require mcp_graph_available first line.
if printf '%s' "$RESULT_BLOCK" | grep -qiE 'graph|mcp_graph|callers_of|sst3-code-'; then
  FIRST_NONEMPTY="$(printf '%s' "$RESULT_BLOCK" | awk 'NF { print; exit }')"
  if ! printf '%s' "$FIRST_NONEMPTY" | grep -qiE '^[[:space:]]*mcp_graph_available[[:space:]]*:[[:space:]]*(yes|no)'; then
    printf 'F-7 subagent-result-parser: RESULT block discusses graph queries but mcp_graph_available is not the first line (AP #19).\n' >&2
  fi
fi

exit 0

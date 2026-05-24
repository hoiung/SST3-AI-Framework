#!/usr/bin/env bash
# sst3-issue-body-privacy-gate.sh — F-13 PreToolUse bash wrapper (#498 AC 2.5).
#
# WHAT  PreToolUse hook matched on `mcp__github__create_issue` and
#       `mcp__github__update_issue` (per claude/settings.json wiring). Reads
#       the MCP tool-call JSON from stdin, extracts `.tool_input.body`,
#       feeds it to the Python privacy scanner. DENY mode: scanner exit 1
#       → wrapper exits 2 (blocks tool call); scanner exit 0 → wrapper
#       exits 0 (silent pass).
#
# WHY   F-13 is the irreversible-impact carve-out: privacy violations in a
#       public-mirrored Issue body are not undoable (filter-repo + force-push
#       only partially scrub; backup-tags + downstream forks remain leak
#       vectors per dotfiles#497 evidence). DENY rather than WARN at this gate.
#
# CONTRACT  stdin = MCP PreToolUse JSON. jq required. Python scanner at
#       scripts/sst3-privacy-scan-issue-body.py.
#
# REVERSIBLE  Remove the `mcp__github__create_issue` / `mcp__github__update_issue`
#       PreToolUse matcher from claude/settings.json. Zero residual state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Try repo-canonical layout first; fall back to the user-scoped install.
SCANNER=""
for candidate in \
  "$SCRIPT_DIR/../../scripts/sst3-privacy-scan-issue-body.py" \
  "${DOTFILES_ROOT:-<your-dotfiles-clone>}/scripts/sst3-privacy-scan-issue-body.py"; do
  if [[ -f "$candidate" ]]; then
    SCANNER="$candidate"
    break
  fi
done

if [[ -z "$SCANNER" ]]; then
  # Scanner not found: log to stderr, exit 1 (runtime error, NOT a tool-call block).
  # An exit-1 PreToolUse hook is advisory; the tool call still proceeds. This is
  # the documented graceful-degrade — a missing scanner must not silently bypass
  # the gate, but it also must not block legitimate work while the harness is
  # not fully installed (Phase 4.5 operator-execute checkpoint).
  printf 'F-13 wrapper: scanner not found; tool call NOT inspected.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'F-13 wrapper: jq missing; tool call NOT inspected.\n' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'F-13 wrapper: python3 missing; tool call NOT inspected.\n' >&2
  exit 1
fi

raw_stdin="$(cat 2>/dev/null || true)"
# Extract Issue body. mcp__github__create_issue uses `.tool_input.body`;
# mcp__github__update_issue may use the same field. Fall back to `.tool_input.body_markdown`.
BODY="$(printf '%s' "$raw_stdin" | jq -r '.tool_input.body // .tool_input.body_markdown // empty' 2>/dev/null || printf '')"

if [[ -z "$BODY" ]]; then
  # Empty body (e.g. delete-issue / lock-issue / no body field) → nothing to scan.
  exit 0
fi

# Pipe body to the scanner; exit-1 from scanner → DENY (exit 2 blocks tool call).
SCAN_OUT="$(printf '%s' "$BODY" | python3 "$SCANNER" --stdin 2>&1)"
SCAN_RC=$?

if [[ $SCAN_RC -eq 0 ]]; then
  exit 0
fi

if [[ $SCAN_RC -eq 1 ]]; then
  # Privacy violation → block with helpful message to the operator.
  printf 'F-13 PRIVACY GATE — BLOCKED\n' >&2
  printf '%s\n' "$SCAN_OUT" >&2
  printf '\nThe Issue body contains privacy-sensitive substrings. The mcp__github tool\n' >&2
  printf 'call has been BLOCKED to prevent an irreversible public-repo leak.\n' >&2
  printf 'Remediation: scrub the body OR add a `.secret-allowlist` entry if FP.\n' >&2
  exit 2
fi

# Scanner exit-2 = usage error (our bug, not the operator's content) → log + advisory.
printf 'F-13 wrapper: scanner usage error rc=%d; tool call NOT inspected.\n' "$SCAN_RC" >&2
printf '%s\n' "$SCAN_OUT" >&2
exit 1

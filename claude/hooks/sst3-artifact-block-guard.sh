#!/usr/bin/env bash
# sst3-artifact-block-guard.sh — PreToolUse guard: block the built-in Artifact
# tool (dotfiles#538).
#
# WHAT  Claude Code PreToolUse "Artifact" matcher. Default DENY (exit 2) — the
#         built-in Artifact tool publishes to claude.ai (Anthropic's servers);
#         it is banned by policy. Artifacts are built LOCAL via the
#         artifact-branding skill (sst3_brand.py + leak-scan) and published, if
#         ever, only to the operator's own site by explicit choice.
#         ESCAPE HATCH: SST3_ALLOW_ARTIFACT=1 bypasses the block (operator-
#         authorised, single-session only).
#
# WHY   A claude.ai-hosted artifact is a third-party surface outside operator
#       ownership — no leak-scan gate, un-deletable server-side, an unauthorised
#       distribution channel. A memory rule is too weak (diluted/purged); this
#       is the harness-enforced backstop that does not depend on model recall.
#
# CONTRACT  stdin = PreToolUse JSON. The settings.json matcher "Artifact" already
#       scopes this hook to Artifact-tool calls, so this guard is FAIL-CLOSED:
#       it DENIES even when jq is absent or stdin is unparseable (the opposite of
#       the fail-open destructive-op-guard — a publish-to-external-server default
#       must never silently succeed). When jq IS present it additionally allows
#       any non-Artifact tool_name through, as defensive belt-and-suspenders
#       against a mis-scoped matcher.
#
# REVERSIBLE  Remove the "Artifact" PreToolUse matcher entry from
#       claude/settings.json, or set "disableAllHooks": true, or run the one call
#       with SST3_ALLOW_ARTIFACT=1.
set -uo pipefail

ALLOW="${SST3_ALLOW_ARTIFACT:-0}"
LOG="${SST3_ARTIFACT_LOG:-$HOME/.claude/hooks/artifact-block-guard.log}"
# Log rotation cap (mirrors destructive-op-guard). Default 5MB — truncate to tail
# when exceeded so growth is bounded without losing recent audit history.
LOG_MAX_BYTES="${SST3_ARTIFACT_LOG_MAX_BYTES:-5242880}"
LOG_TAIL_BYTES="${SST3_ARTIFACT_LOG_TAIL_BYTES:-2621440}"

audit() {
  local decision="$1" detail="$2"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  if [[ -f "$LOG" ]]; then
    local sz
    sz="$(stat -c %s "$LOG" 2>/dev/null || wc -c <"$LOG" 2>/dev/null || printf 0)"
    if [[ "$sz" =~ ^[0-9]+$ ]] && (( sz > LOG_MAX_BYTES )); then
      local tmp="${LOG}.rotating"
      if tail -c "$LOG_TAIL_BYTES" "$LOG" >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$LOG" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
      else
        rm -f "$tmp" 2>/dev/null || true
      fi
    fi
  fi
  printf 'ts=%s cwd=%s decision=%s detail=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PWD" "$decision" "$detail" \
    >>"$LOG" 2>/dev/null || true
}

emit_deny() {
  printf 'SST3 artifact-block-guard: BLOCKED — the Artifact tool publishes to claude.ai (external servers) and is banned by policy.\n' >&2
  printf '  Build the artifact LOCAL via the artifact-branding skill (sst3_brand.py + leak-scan); publish only to your own site by choice.\n' >&2
  printf '  Override (operator-authorised, this call only): SST3_ALLOW_ARTIFACT=1\n' >&2
  audit deny "$1"
  exit 2
}

# Operator escape hatch — explicit, single-session.
if [[ "$ALLOW" == "1" ]]; then
  audit allow "SST3_ALLOW_ARTIFACT=1"
  exit 0
fi

raw_stdin="$(cat 2>/dev/null || true)"

# Defensive belt-and-suspenders: if jq is present and the payload names a
# DIFFERENT tool, let it through (the matcher should already prevent this).
# If jq is absent, do NOT fail open — fall through to DENY (fail-closed).
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$raw_stdin" | jq -r '.tool_name // empty' 2>/dev/null)"
  if [[ -n "$tool_name" && "$tool_name" != "Artifact" ]]; then
    audit allow "non-Artifact tool_name=$tool_name"
    exit 0
  fi
fi

emit_deny "Artifact tool call blocked (tool_name=${tool_name:-unknown})"

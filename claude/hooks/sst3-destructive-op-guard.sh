#!/usr/bin/env bash
# sst3-destructive-op-guard.sh — F-4 destructive-op PreToolUse hook (#498 AC 2.7).
#
# WHAT  Claude Code PreToolUse Bash matcher. Classifies the command into:
#         ALLOW    silent pass (allowlist match — paper/live/DS systemctl
#                  restart, the operator's pre-authorised cadence)
#         WARN     stderr advisory + exit 0 (--no-verify / SKIP=… preserved as
#                  visible-by-design observability)
#         DENY     exit 2 (blocks tool call) for irreversible destructive ops:
#                    git push --force / --force-with-lease
#                    git filter-repo
#                    git reset --hard
#                    git branch -D
#                    rm -rf /<absolute path>
#                    DROP TABLE (in any embedded SQL)
#
# WHY   Operator-authorised paper/live/DS restarts are routine; force-pushes
#       and history-rewrites are irreversible. The branch-guard already gates
#       the dotfiles#488 class; this guards the Issue #1448-class + dotfiles#497
#       (filter-repo) class. ESCAPE HATCH: SST3_DESTRUCTIVE_OVERRIDE=1 bypasses
#       DENY (matches branch-guard precedent).
#
# CONTRACT  stdin = PreToolUse JSON; `.tool_input.command` read via jq.
#       Fail-toward-FLAG (AC2-equivalent): jq missing OR parse error → log to
#       stderr + exit 1 (advisory; does NOT block).
#
# REVERSIBLE  Remove the PreToolUse Bash matcher entry from claude/settings.json
#       or set `"disableAllHooks": true`.
set -uo pipefail

OVERRIDE="${SST3_DESTRUCTIVE_OVERRIDE:-0}"
LOG="${SST3_DESTRUCTIVE_LOG:-$HOME/.claude/hooks/destructive-op-guard.log}"
# Log rotation cap (#498 Stage 5 L1C F6). Default 5MB — when exceeded, the log
# is truncated to its tail (last LOG_TAIL_BYTES bytes) so growth is bounded
# without losing recent audit history. Override via SST3_DESTRUCTIVE_LOG_MAX_BYTES.
LOG_MAX_BYTES="${SST3_DESTRUCTIVE_LOG_MAX_BYTES:-5242880}"
LOG_TAIL_BYTES="${SST3_DESTRUCTIVE_LOG_TAIL_BYTES:-2621440}"

audit() {
  local decision="$1" cmd="$2"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  # Rotate (truncate-to-tail) when over cap. stat -c is GNU; fall back to wc -c
  # for portability (BSD stat). Failure to rotate is non-fatal — append still happens.
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
  printf 'ts=%s cwd=%s decision=%s cmd=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PWD" "$decision" "$cmd" \
    >>"$LOG" 2>/dev/null || true
}

emit_warn() {
  # WARN advisory: command STILL runs. Stderr message + exit 0.
  printf 'F-4 destructive-op-guard: %s — advisory only, command will proceed.\n' "$1" >&2
  audit warn "$2"
  exit 0
}
emit_deny() {
  printf 'F-4 destructive-op-guard: BLOCKED — %s\n' "$1" >&2
  printf '  Override: set SST3_DESTRUCTIVE_OVERRIDE=1 (operator-authorised only).\n' >&2
  audit deny "$2"
  exit 2
}
emit_allow() {
  audit allow "$1"
  exit 0
}

raw_stdin="$(cat 2>/dev/null || true)"

if ! command -v jq >/dev/null 2>&1; then
  printf 'F-4 destructive-op-guard: jq missing; command NOT inspected.\n' >&2
  exit 1
fi

CMD="$(printf '%s' "$raw_stdin" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -z "$CMD" ]] && exit 0   # Non-Bash tool / no command field — nothing to classify.

# Allowlist — explicit, exact-form: paper/live/DS systemctl restarts. Matched
# whole-word so a packed-substring command does not accidentally match.
if [[ "$CMD" =~ (^|[^[:alnum:]_])sudo[[:space:]]+systemctl[[:space:]]+restart[[:space:]]+pb-(paper-controller|live-controller|data-service-rs[0-9a-z-]*)([^[:alnum:]_-]|$) ]]; then
  emit_allow "$CMD"
fi

# DENY class — irreversible. Checked BEFORE WARN so a force-push with
# --no-verify (which would also WARN) still DENY-blocks.
if [[ "$OVERRIDE" != "1" ]]; then
  # git push --force / --force-with-lease / -f / refspec `+ref:ref`.
  # `-f` is git's documented short form for --force (`man git-push`); refspec `+`
  # is the documented force-update syntax (`git-push(1)` §<refspec>). Both bypass
  # the long-form DENY if not explicitly matched. Pattern requires `git push`
  # then optional `<args> ` (one or more space-terminated args), then one of the
  # 4 force forms. `-f` boundary uses `[^[:alnum:]_-]|$` AFTER to avoid matching
  # `-fast` or `-foo`; preceded by `[[:space:]]+` after `push` to anchor it as
  # a standalone arg (not a substring of `--force`).
  if [[ "$CMD" =~ (^|[^[:alnum:]_-])git[[:space:]]+push[[:space:]]+(.*[[:space:]])?(--force([^-]|$)|--force-with-lease|-f([^[:alnum:]_-]|$)|\+[A-Za-z0-9_/.+-]+:[A-Za-z0-9_/.+-]+) ]]; then
    emit_deny "git push --force / -f / --force-with-lease / refspec + (irreversible)" "$CMD"
  fi
  # git filter-repo (history rewrite — dotfiles#497 class).
  if [[ "$CMD" =~ (^|[^[:alnum:]_-])git[[:space:]]+filter-repo([^[:alnum:]_-]|$) ]]; then
    emit_deny "git filter-repo (history rewrite, irreversible to public mirrors)" "$CMD"
  fi
  # git reset --hard.
  if [[ "$CMD" =~ (^|[^[:alnum:]_-])git[[:space:]]+reset[[:space:]].*--hard([^[:alnum:]_-]|$) ]]; then
    emit_deny "git reset --hard (uncommitted-work loss)" "$CMD"
  fi
  # git branch -D / --delete --force.
  if [[ "$CMD" =~ (^|[^[:alnum:]_-])git[[:space:]]+branch[[:space:]].*(-D([^[:alnum:]_-]|$)|--delete[[:space:]]+--force) ]]; then
    emit_deny "git branch -D (unmerged-branch deletion)" "$CMD"
  fi
  # rm -rf / — root or absolute-path bombing pattern.
  if [[ "$CMD" =~ (^|[^[:alnum:]_-])rm[[:space:]]+(-[A-Za-z]*[rR][A-Za-z]*[fF][A-Za-z]*|-[A-Za-z]*[fF][A-Za-z]*[rR][A-Za-z]*)([[:space:]].+)?[[:space:]]+/($|[^.]) ]]; then
    emit_deny "rm -rf / (filesystem destruction)" "$CMD"
  fi
  # DROP TABLE (SQL embedded in shell args or scripts).
  if [[ "$CMD" =~ (DROP|drop)[[:space:]]+(TABLE|table)([[:space:]]|;|$) ]]; then
    emit_deny "DROP TABLE (SQL destructive)" "$CMD"
  fi
fi

# WARN class — advisory; command runs.
if [[ "$CMD" =~ --no-verify([^[:alnum:]_-]|$) ]]; then
  emit_warn "--no-verify bypasses pre-commit hooks (audit-trail visible-by-design)" "$CMD"
fi
if [[ "$CMD" =~ (^|[^[:alnum:]_-])SKIP=[A-Za-z0-9_,-]+[[:space:]] ]]; then
  emit_warn "SKIP=<hook> bypasses one or more pre-commit hooks" "$CMD"
fi

exit 0

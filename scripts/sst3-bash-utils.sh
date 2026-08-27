#!/usr/bin/env bash
# sst3-bash-utils.sh — Shared bash helpers for the wrapper-lane (Issue #447).
#
# Sister of dotfiles/scripts/sst3_utils.py (Python helpers).
# Dash-vs-underscore distinction prevents Python `from sst3_utils import` collision.
#
# Helpers (index re-derived from the definitions below on every edit — it had
# drifted to 6 documented against 8 defined by dotfiles#565):
#   assert_safe_identifier <val>             — reject shell metacharacters; exit 64 (Phase 1)
#   normalise_lang <lang>                    — canonicalise language name; exit 64 if unsupported (Phase 3)
#   require_engine_version <tool> <min>      — warn-only stderr if version below pin (Phase 3)
#   read_paths_from <ndjson_file>            — emit unique file paths from {file:...} NDJSON (Phase 8 retrofit)
#   wrapper_sentinel <name> <count> <kind>   — "I ran" stderr line; call from EXIT trap
#   activate_paths_from_filter <ndjson>      — install transparent stdout NDJSON .file filter (Phase 8)
#   sst3_solo_branch_alt <issue>             — canonical solo-branch ERE alternation (#509 AC6.5)
#   ast_grep_check_rc <wrapper> <rc>         — discriminate broken engine from benign empty (#547 AC 6.1)
#   probe_or_fail [--numeric] <label> -- <cmd...>
#                                            — run a probe; echo its stdout, or return 1 loudly
#                                              rather than substituting a clean-looking default (#565 AC 5.1)
#
# Source via:
#   source "$(dirname "$0")/sst3-bash-utils.sh"
#
# NDJSON contract reminder for callers of activate_paths_from_filter:
# the helper installs `exec > >(jq -c ...)` which aborts the jq stream on
# the FIRST malformed stdout line and silently drops everything after.
# Wrappers MUST emit only valid one-object-per-line JSON to stdout.
# stderr (sentinels, diagnostics) is unaffected.

# PATH bootstrap — relocated from sst3-self-test.sh:22-37 (Issue #456).
# Reaches engines under $HOME/{.cargo,.local,.npm-global}/bin from non-interactive
# bash (.bashrc early-returns there). getent guard fixes SC2116 empty-HOME bug.
# Self-test keeps an inline copy so it self-bootstraps if this helper breaks.
#
# Test seam (#537): SST3_SKIP_PATH_BOOTSTRAP=1 skips ALL prepends (including the
# unconditional /usr/local/bin). Engine-missing simulations (self-test fixture
# sst3-check-paths-from-strict leg (c)) restrict PATH to prove --strict exit-2;
# without the seam this bootstrap re-adds /usr/local/bin and defeats the
# restriction on hosts where the engine lives there (CI installs ast-grep to
# /usr/local/bin — validate.yml). Production callers never set it.
if [[ -z "${SST3_SKIP_PATH_BOOTSTRAP:-}" ]]; then
    : "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)}"
    [[ -z "$HOME" ]] && { echo "ERROR: cannot resolve HOME for PATH bootstrap" >&2; exit 1; }
    # Each prepended only when missing from PATH (idempotent on repeat sourcing). Iteration-last wins lookup precedence: final order = /usr/local > npm-global > local > cargo > orig PATH.
    for extra in "$HOME/.cargo/bin" "$HOME/.local/bin" "$HOME/.npm-global/bin" "/usr/local/bin"; do
        case ":$PATH:" in
            *":$extra:"*) ;;
            *) [[ -d "$extra" ]] && PATH="$extra:$PATH" ;;
        esac
    done
    export PATH
fi
# Reject anything other than a plain identifier with dots (Class.method allowed).
# Exit 64 (EX_USAGE) consistent with the wrapper bad-args contract.
# Closes the command-injection class on every wrapper that interpolates user-
# supplied SYMBOL/NAME/BASE_CLASS into a shell-evaluated ast-grep pattern.
assert_safe_identifier() {
    local val="$1"
    if [[ ! "$val" =~ ^[a-zA-Z_][a-zA-Z0-9_.]*$ ]]; then
        echo "ERROR: identifier '$val' contains unsafe characters; expected ^[a-zA-Z_][a-zA-Z0-9_.]*\$" >&2
        exit 64
    fi
}

# Canonicalise language name. Echoes the canonical form on stdout.
# Maps: py|python|python3 → python; js|javascript|gs → javascript;
#       ts|typescript → typescript; tsx → tsx; rs|rust → rust;
#       sh|bash|shell → bash; md|markdown → markdown.
# Anything else → exit 64.
normalise_lang() {
    local lang="$1"
    case "$lang" in
        py|python|python3) echo "python" ;;
        # #548: `jsx` folds into javascript — ast-grep's javascript grammar both
        # parses and discovers .jsx files (0.42.1 probe), and this is the single
        # site that unblocks `jsx` for every arg-taking wrapper (callers,
        # search, callees, large, subclasses, entry-points, callers-transitive),
        # each of which previously exit-64'd on `unsupported lang: jsx`.
        js|javascript|gs|jsx) echo "javascript" ;;
        ts|typescript) echo "typescript" ;;
        tsx) echo "tsx" ;;
        rs|rust) echo "rust" ;;
        sh|bash|shell) echo "bash" ;;
        md|markdown) echo "markdown" ;;
        *)
            echo "ERROR: unsupported lang: $lang (supported: python, javascript, jsx, typescript, tsx, rust, bash, markdown)" >&2
            exit 64
            ;;
    esac
}

# Warn-only engine-version pin. Empirical break-on-version-X data not yet
# collected (Phase 3 of #447 docs this as a Layer-2 follow-up). Emits
# `WARN:` to stderr if missing or below `<min>`. Never blocks.
# Usage: require_engine_version <tool> <min>
# E.g.   require_engine_version ast-grep 0.20
require_engine_version() {
    local tool="$1"
    local min="$2"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "WARN: $tool not on PATH; pin min_known_working=$min (warn-only)" >&2
        return 0
    fi
    local ver
    ver=$("$tool" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)
    if [[ -z "$ver" ]]; then
        echo "WARN: could not parse $tool --version output for pin check (min_known_working=$min)" >&2
        return 0
    fi
    local lowest
    lowest=$(printf '%s\n%s\n' "$ver" "$min" | sort -V | head -n1)
    if [[ "$lowest" != "$min" ]]; then
        echo "WARN: $tool version $ver below min_known_working=$min (warn-only; not yet empirically blocked)" >&2
    fi
}

# Read NDJSON file emitting one file path per line, deduplicated, in input order.
# Each NDJSON record must have a `.file` string. Records lacking `.file` are skipped.
# Used by --paths-from <file> retrofit (Phase 8) and the self-test driver.
read_paths_from() {
    local ndjson_file="$1"
    if [[ ! -r "$ndjson_file" ]]; then
        echo "ERROR: --paths-from file not readable: $ndjson_file" >&2
        exit 64
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo 'ERROR: jq not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
        exit 127
    fi
    jq -r 'select(.file != null) | .file' "$ndjson_file" | awk '!seen[$0]++'
}

# Universal "I ran" sentinel — call from EXIT trap.
# Usage:
#   trap 'wrapper_sentinel "sst3-code-large" "$SST3_EMITTED_COUNT" "function"' EXIT
wrapper_sentinel() {
    local name="${1:-$(basename "$0" .sh)}"
    local count="${2:-0}"
    local kind="${3:-record}"
    printf '%s: emitted %d %s(s)\n' "$name" "$count" "$kind" >&2
}

# --paths-from retrofit: parse --paths-from from "$@", strip it, and if a
# filter file was given, redirect this script's stdout through a jq filter
# that only passes NDJSON records whose `.file` is in the allowed set.
# Body code emits as usual; filtering is transparent.
#
# Usage at top of a retrofitted wrapper (after `source sst3-bash-utils.sh`):
#     # Strip --paths-from from positional args + activate filter:
#     ARGS=(); PATHS_FROM=""
#     while [[ $# -gt 0 ]]; do
#         case "$1" in
#             --paths-from) PATHS_FROM="${2:-}"; shift 2 || break;;
#             *) ARGS+=("$1"); shift;;
#         esac
#     done
#     set -- "${ARGS[@]}"
#     activate_paths_from_filter "$PATHS_FROM"
#
# Empty PATHS_FROM = no-op (filter not installed; stdout passes through).
# stderr is NOT filtered (sentinel + diagnostics still flow through).
# (#447 Phase 8 — universal retrofit, mechanical.)
activate_paths_from_filter() {
    local nd="${1:-}"
    [[ -z "$nd" ]] && return 0
    if [[ ! -r "$nd" ]]; then
        echo "ERROR: --paths-from file not readable: $nd" >&2
        exit 64
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo 'ERROR: jq not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
        exit 127
    fi
    local pattern
    pattern=$(jq -Rsc 'split("\n")|map(select(length>0))' < <(read_paths_from "$nd"))
    [[ -z "$pattern" || "$pattern" == "[]" ]] && return 0
    # Redirect stdout into a coprocess that filters NDJSON by .file membership.
    exec > >(jq -c --argjson allowed "$pattern" \
        'if (.file? // null) == null then . else select(.file as $f | $allowed | index($f) != null) end')
}

# --- could-not-look contract (#565 AC 5.1) --------------------------------
#
# The invariant this Issue exists to enforce: a check that cannot COMPLETE its
# probe must never be indistinguishable from a check that probed and found
# nothing. MEASURED across the 72 governance shell files, 64 carried a
# failure-swallowing token, and live members included a security scanner
# reporting `emitted 0 leak(s)` over a real on-disk leak and a completeness
# check reading a network failure as "branch deleted".
#
# Generalises the fail-closed precedent at scripts/sec-staged-scan.sh:56-64
# and :101-124: an unresolvable probe is an exit-coded loud failure, never a
# substituted default.
#
# This marker is the single literal every could-not-look diagnostic carries, so
# one grep finds every site at audit time. Callers MUST NOT re-spell it.
SST3_PROBE_FAILED_MARKER="SST3_PROBE_FAILED"

# probe_or_fail [--numeric] <label> -- <command...>
#
# Runs <command...>, echoing its stdout on success so the caller can use it in
# a command substitution. Returns 1 WITHOUT echoing anything when the probe
# could not be completed:
#   * the command exited non-zero (including 127 not-found and 124 timeout)
#   * --numeric was given and stdout is not a bare integer
# In both cases a diagnostic carrying $SST3_PROBE_FAILED_MARKER goes to stderr.
#
# Usage — the `if` is load-bearing; a bare `$(probe_or_fail ...)` discards the
# status and reintroduces the very defect this closes:
#
#     if out="$(probe_or_fail --numeric "D4 ahead-count" -- \
#                 git -C "$root" rev-list --count "origin/$br..HEAD")"; then
#         ...act on $out...
#     else
#         set_verdict D4 fail "could not look: ahead-count probe failed"
#     fi
#
# stderr of the probed command is captured (not suppressed) and folded into the
# diagnostic, because the error text is the diagnosis. It is NOT merged into
# stdout — a warning on stderr must not become part of the answer.
probe_or_fail() {
    local numeric=0
    if [[ "${1:-}" == "--numeric" ]]; then numeric=1; shift; fi
    local label="${1:-<unlabelled>}"; shift || true
    if [[ "${1:-}" == "--" ]]; then shift; fi
    if [[ $# -eq 0 ]]; then
        printf '%s: %s — could not look: probe_or_fail invoked with no command\n' \
            "$SST3_PROBE_FAILED_MARKER" "$label" >&2
        return 1
    fi
    local errfile out rc err
    errfile="$(mktemp)" || {
        printf '%s: %s — could not look: mktemp failed\n' "$SST3_PROBE_FAILED_MARKER" "$label" >&2
        return 1
    }
    out="$("$@" 2>"$errfile")"
    rc=$?
    err="$(tr '\n' ' ' < "$errfile" | cut -c1-300)"
    rm -f "$errfile"
    if [[ "$rc" -ne 0 ]]; then
        printf '%s: %s — could not look: `%s` exited %s: %s\n' \
            "$SST3_PROBE_FAILED_MARKER" "$label" "$*" "$rc" "$err" >&2
        return 1
    fi
    if [[ "$numeric" -eq 1 && ! "$out" =~ ^[0-9]+$ ]]; then
        printf '%s: %s — could not look: `%s` exited 0 but returned non-numeric output %s\n' \
            "$SST3_PROBE_FAILED_MARKER" "$label" "$*" "'$out'" >&2
        return 1
    fi
    printf '%s' "$out"
    return 0
}

# sst3_solo_branch_alt <issue> — canonical solo-branch grep alternation (#509 AC6.5).
# Bash sister of the Python single-source `sst3_utils.SOLO_BRANCH_RE`. Echoes an
# ERE fragment matching EVERY solo branch form for the given issue number, so
# callers (e.g. leader-stage5-drain-check.sh) stop re-hand-rolling — and drifting —
# the alternation. Forms: solo/issue-N- , solo+issue-N- , solo-issue-N- , each with
# an optional `worktree-` prefix (EnterWorktree renames `/` -> `+`). KEEP IN SYNC
# with sst3_utils.SOLO_BRANCH_RE.
sst3_solo_branch_alt() {
    local issue="$1"
    printf '(worktree-)?solo[/+-]issue-%s-' "$issue"
}

# ast_grep_check_rc <wrapper-name> <rc> — #547 AC 6.1 (R1 broken-engine loudness).
# Discriminates the captured ast-grep exit code (rc, NOT output emptiness):
#   rc 0 = matches; rc 1 = benign empty (`run` zero-matches / no files of the
#   lang / missing file arg — probe matrix, ast-grep 0.42.1; `scan` exits 0 on
#   zero matches). Both return 0 — a genuine empty result stays a valid empty.
#   rc >= 2 (crash, garbage binary, rule/pattern parse error 8, exec-127) =
#   engine PRESENT but BROKEN: emit {"kind":"<wrapper-name>-error",...} on
#   stdout (#544 untested-py-error convention — stdout NDJSON, NEVER bare
#   stderr: review.sh composes wrappers via `$(... 2>&1)`) and return 1.
# Callers exit 0 after the record (any partial records already emitted stay
# valid; the record IS the loud signal — sec-staged-scan/sst3-check consumers
# gate on `-error` kinds in the stream, not on rc).
# When SST3_REAL_STDOUT_FD is set (callees.sh: helpers whose stdout is
# $(...)-captured), the record goes to that saved FD so it cannot poison the
# captured data.
ast_grep_check_rc() {
    local wrapper="$1" rc="${2:-99}"
    [[ "$rc" =~ ^[0-9]+$ ]] || rc=99
    (( rc <= 1 )) && return 0
    local record
    record=$(printf '{"kind":"%s-error","reason":"ast-grep exited rc=%s: engine present but broken (benign classes: 0=match, 1=zero-matches)","rc":%s}' \
        "$wrapper" "$rc" "$rc")
    if [[ -n "${SST3_REAL_STDOUT_FD:-}" ]]; then
        printf '%s\n' "$record" >&"${SST3_REAL_STDOUT_FD}"
    else
        printf '%s\n' "$record"
    fi
    return 1
}

# sst3_commit_is_metrics_only <repo_dir> <sha> — bash twin of
# check-devprojects-clean.py `_is_local_only_commit` (`_LOCAL_ONLY_PREFIXES`).
# KEEP IN SYNC with that constant: the two implement ONE documented carve-out
# ("commits touching only SST3-metrics/ are unpushed on purpose", STANDARDS.md
# "DevProjects Cleanliness Enforcement"), and until dotfiles#569's close-out
# only the Python side had it. D4/C11 therefore went red on any concurrent
# session's in-flight feedback commits — which every /Leader stage writes, so
# the failure was near-permanent rather than occasional.
#
# Returns 0 (metrics-only, excludable) ONLY when every path the commit touches
# is under SST3-metrics/. A probe failure returns 1 (NOT excludable) — the
# exclusion must never be the reason something goes unseen.
sst3_commit_is_metrics_only() {
    local repo="$1" sha="$2" shown p any=0
    # --no-renames is load-bearing, not tidiness (same reasoning as the Python
    # twin): rename detection is ON by default and reports only the DESTINATION
    # path, so a commit that MOVES real source into SST3-metrics/ would present
    # as touching only SST3-metrics/ and satisfy this exclusion in full.
    shown="$(git -C "$repo" show --no-renames --name-only --format= "$sha" 2>/dev/null)" || return 1
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        any=1
        [[ "$p" == SST3-metrics/* ]] || return 1
    done <<< "$shown"
    # An empty path list is NOT metrics-only. An empty commit carries no
    # evidence that it is the local-only convention, and reading "no paths" as
    # "every path matched" is the vacuous-clean shape this carve-out must avoid.
    [[ "$any" -eq 1 ]]
}

# sst3_count_commits_excluding_metrics <repo_dir> <rev-list-arg>... — count the
# commits the given rev-list selects, MINUS the metrics-only ones.
# Echoes the count and returns 0; returns 1 echoing NOTHING when the rev-list
# itself could not run, so a caller can report could-not-look instead of reading
# a probe failure as a clean zero.
sst3_count_commits_excluding_metrics() {
    local repo="$1"; shift
    local shas sha n=0
    shas="$(git -C "$repo" rev-list "$@" 2>/dev/null)" || return 1
    while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue
        sst3_commit_is_metrics_only "$repo" "$sha" || n=$(( n + 1 ))
    done <<< "$shas"
    printf '%s' "$n"
}

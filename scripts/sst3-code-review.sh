#!/usr/bin/env bash
# sst3-code-review.sh — Composite diff-scoped review (replaces 4MB-JSON monolith).
#
# Usage:   sst3-code-review.sh <base-branch>
# Example: sst3-code-review.sh main
# Output:  NDJSON written to /tmp/review.ndjson chaining:
#            {section:"impact", changed_file, impacted_callers}
#            {section:"untested-in-diff", file, untested:[names]}
#            {section:"empty-diff-range", base, note}  (BASE...HEAD has 0 commits; exit 0 no-op)
# Engines: composes sst3-code-impact.sh + sst3-code-untested-py.sh.

set -euo pipefail
export LC_ALL=C


SST3_EMITTED_COUNT="${SST3_EMITTED_COUNT:-0}"
on_sigterm() {
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg n "sst3-code-review" --argjson e "${SST3_EMITTED_COUNT:-0}" \
            '{kind:($n + "-killed"), reason:"sigterm", partial_records:$e}'
    else
        printf '{"kind":"%s-killed","reason":"sigterm","partial_records":%s}\n' \
            "sst3-code-review" "${SST3_EMITTED_COUNT:-0}"
    fi
    exit 143
}
trap on_sigterm SIGTERM

# shellcheck source=./sst3-bash-utils.sh
source "$(dirname "$0")/sst3-bash-utils.sh"

# --paths-from retrofit (#447 Phase 8): strip --paths-from from positional args
# and (if a filter NDJSON was supplied) install a transparent stdout filter
# via activate_paths_from_filter from sst3-bash-utils.sh.
__PATHS_FROM_SST3=""
__ARGS_SST3=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --paths-from) __PATHS_FROM_SST3="${2:-}"; shift 2 || break;;
        *) __ARGS_SST3+=("$1"); shift;;
    esac
done
set -- "${__ARGS_SST3[@]+"${__ARGS_SST3[@]}"}"
activate_paths_from_filter "$__PATHS_FROM_SST3"

if [[ $# -lt 1 ]]; then
    echo "ERROR: usage: $(basename "$0") <base-branch>" >&2
    exit 64
fi

# #447 Phase 3 (Shape 27): startup engine checks. Previously code-review.sh had
# zero — relied on inner wrappers exiting 127. The blanket `|| true` patterns
# below then conflated engine-missing with empty-result, hiding the diagnostic.
if ! command -v ast-grep >/dev/null 2>&1; then
    echo 'ERROR: ast-grep not installed (required by sst3-code-impact.sh); see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi
if ! command -v jq >/dev/null 2>&1; then
    echo 'ERROR: jq not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi

BASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# #447 Phase 3 (Shape 7): fixed `/tmp/review.ndjson` raced multi-shell. Default
# to mktemp; SST3_REVIEW_NDJSON overrides (test fixtures + deterministic dev).
OUT="${SST3_REVIEW_NDJSON:-$(mktemp -t sst3_review.XXXXXX.ndjson)}"

: > "$OUT"

# #520 (item-3): a bad/typo'd base ref must NOT be silently swallowed by the
# empty-range guard below (`git rev-list ... 2>/dev/null || echo 0` would map an
# unresolvable ref to RANGE_COUNT=0 and report "nothing to review" — reintroducing
# the very silent-failure class this guard fixes: a typo'd ref looking like a clean
# diff). Validate the ref FIRST and fail loud with the reserved usage code 64.
if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null 2>&1; then
    echo "ERROR: base ref '${BASE}' does not resolve to a commit" >&2
    exit 64
fi

# #520 (item-3): empty-diff-range guard. When BASE...HEAD has zero commits (e.g.
# the Stage-5 audit running `review.sh <default>` AFTER a merge, so the range is
# empty), the impact engine emits 0 bytes rc 0 and the `grep -v '^$'` pipe below
# exits 1 — under `pipefail`+`set -e` that aborts the script BEFORE `echo "$OUT"`,
# a silent exit 1 indistinguishable from "engine broken". An empty range is a
# legitimate no-op: emit a distinct diagnostic and exit 0. BASE is already
# validated above, so the `|| echo 0` here only ever fires on a genuinely-empty
# (valid) range. Exit codes 64/127/143 stay reserved for usage / engine-missing /
# sigterm.
RANGE_COUNT=$(git rev-list --count "${BASE}...HEAD" 2>/dev/null || echo 0)
if [[ "$RANGE_COUNT" -eq 0 ]]; then
    EMPTY_NOTE="no commits in ${BASE}...HEAD; nothing to review"
    jq -nc --arg b "$BASE" --arg note "$EMPTY_NOTE" \
        '{section:"empty-diff-range", base:$b, note:$note}' >> "$OUT"
    echo "empty-diff-range: $EMPTY_NOTE" >&2
    echo "$OUT"
    exit 0
fi

# #447 Phase 3 (Shape 27): replaced blanket `|| true` with explicit per-step
# error capture. If sst3-code-impact.sh fails (engine-broken / SIGTERM), we
# emit a structured diagnostic instead of silently producing an empty review.
set +e
IMPACT_OUT=$(bash "$SCRIPT_DIR/sst3-code-impact.sh" "$BASE" 2>&1)
IMPACT_RC=$?
set -e
if [[ $IMPACT_RC -ne 0 ]]; then
    jq -nc --arg s "$IMPACT_OUT" --argjson rc "$IMPACT_RC" \
        '{section:"review-error", source:"sst3-code-impact", exit:$rc, stderr:$s}' >> "$OUT"
else
    # #520 (item-3): `grep -v` exits 1 on empty-but-successful impact output;
    # under pipefail+set -e that aborts the script. No-match is NOT an error
    # here (rc 0 + empty is a valid "nothing impacted") — guard with `|| true`.
    printf '%s\n' "$IMPACT_OUT" | { grep -v '^$' || true; } \
        | jq -c '. + {section: "impact"}' >> "$OUT"
fi

if [[ -f .coverage ]] && command -v coverage >/dev/null 2>&1; then
    CHANGED=$(git diff --name-only "${BASE}...HEAD" -- '*.py' 2>/dev/null || true)
    if [[ -n "$CHANGED" ]]; then
        set +e
        UNTESTED_OUT=$(bash "$SCRIPT_DIR/sst3-code-untested-py.sh" 2>&1)
        UNTESTED_RC=$?
        set -e
        if [[ $UNTESTED_RC -ne 0 ]]; then
            jq -nc --arg s "$UNTESTED_OUT" --argjson rc "$UNTESTED_RC" \
                '{section:"review-error", source:"sst3-code-untested-py", exit:$rc, stderr:$s}' >> "$OUT"
        else
            # #520 (item-3): same guard — untested-py returns empty rc 0 when all
            # changed .py are tested; no-match `grep -v` exit 1 must not abort.
            printf '%s\n' "$UNTESTED_OUT" | { grep -v '^$' || true; } \
                | jq -c --arg changed "$CHANGED" '
                    . as $u |
                    ($changed | split("\n")) as $files |
                    select($u.file as $f | $files | index($f)) |
                    $u + {section: "untested-in-diff"}
                  ' >> "$OUT"
        fi
    fi
fi

echo "$OUT"

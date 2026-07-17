#!/usr/bin/env bash
# sst3-code-impact.sh — Blast-radius analysis for files changed vs a base branch.
#
# Usage:   sst3-code-impact.sh <base-branch>
# Example: sst3-code-impact.sh main
# Output:  NDJSON, one object per changed file: {changed_file, impacted_callers}
#          where impacted_callers is an integer count of call sites referencing
#          a top-level symbol in changed_file.
# Engines: git diff --name-only base...HEAD; ast-grep --json=stream per file.

set -euo pipefail
export LC_ALL=C


SST3_EMITTED_COUNT="${SST3_EMITTED_COUNT:-0}"
on_sigterm() {
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg n "sst3-code-impact" --argjson e "${SST3_EMITTED_COUNT:-0}" \
            '{kind:($n + "-killed"), reason:"sigterm", partial_records:$e}'
    else
        printf '{"kind":"%s-killed","reason":"sigterm","partial_records":%s}\n' \
            "sst3-code-impact" "${SST3_EMITTED_COUNT:-0}"
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

BASE="$1"

if ! command -v ast-grep >/dev/null 2>&1; then
    echo 'ERROR: ast-grep not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi

CHANGED=$(git diff --name-only "${BASE}...HEAD" -- '*.py' '*.ts' '*.tsx' '*.js' '*.rs' 2>/dev/null || true)

if [[ -z "$CHANGED" ]]; then
    exit 0
fi

# Count repo-wide call sites matching one ast-grep pattern (#544 Stage-5
# dedup — shared by the bare + receiver-qualified shapes in the loop below,
# mirroring callers.sh's emit_call_sites split). Uses the caller's $LANG.
# Zero-caller case: `wc -l` exits 0 with `0` output, but pipe SIGPIPE on
# ast-grep failure can yield `0\n0` via `|| echo 0` fallback — strip non-digits
# so subsequent arithmetic doesn't fail with "syntax error in expression".
# Stage 5 fix L1.I (Issue #12 post-impl review) — `set -o pipefail` at the
# top propagates ast-grep's nonzero exit (it returns non-zero on certain
# zero-match patterns) through the pipe, silently under-counting impact
# records. Disable pipefail in this subshell only; the `${n:-0}` + non-digit
# strip already handle the empty output case safely.
count_call_sites() {
    local n
    n=$( (set +o pipefail; ast-grep run --pattern "$1" --lang "$LANG" --json=stream 2>/dev/null | wc -l) )
    n=${n//[^0-9]/}
    printf '%s\n' "${n:-0}"
}

while IFS= read -r FILE; do
    [[ -f "$FILE" ]] || continue
    # Language dispatch (AC 5.1 dotfiles#516 kept the per-language split; #546
    # ports the extraction itself from shape patterns to kind-rules).
    case "$FILE" in
        *.py)  LANG="python" ;;
        *.ts)  LANG="typescript" ;;
        *.tsx) LANG="tsx" ;;
        *.js)  LANG="javascript" ;;
        *.rs)  LANG="rust" ;;
        *)     continue ;;
    esac
    # #546: definition extraction ported to the #445 R4 kind-rule convention
    # already used by sst3-code-callees.sh:98-155 and sst3-code-large.sh.
    # Shape patterns cannot match nodes carrying extra children, so Rust
    # `pub`/`pub(crate)`/`pub async` fns and impl methods (visibility_modifier
    # child), JS/TS class methods (method_definition kind), and typed/exported
    # functions were never extracted — measured recall on the #546 probe tree:
    # rust 2/6, ts 1/6 (python 3/3). Kind-rules recover 6/6 / 6/6 / 3/3.
    # Anonymous arrows have no `name` field and stay unaddressable by name
    # (same limit as callees.sh:119-120). variable_declarator also yields
    # non-function consts and destructuring patterns — non-identifier names
    # are filtered below; over-extraction adds mostly-0-count lookups (a
    # const name colliding with a called function elsewhere can add a small
    # over-count — the same coarse-name imprecision this advisory already
    # carries; over-count errs safe).
    # shellcheck disable=SC2016  # $NAME inside rule strings is an ast-grep meta-var, not a shell expansion
    case "$LANG" in
        python)
            EXTRACT_RULE='id: impact-defs
language: python
rule:
  kind: function_definition
  has:
    field: name
    pattern: $NAME' ;;
        typescript|tsx|javascript)
            EXTRACT_RULE="id: impact-defs
language: $LANG
rule:
  any:
    - kind: function_declaration
    - kind: method_definition
    - kind: variable_declarator
  has:
    field: name
    pattern: \$NAME" ;;
        rust)
            EXTRACT_RULE='id: impact-defs
language: rust
rule:
  kind: function_item
  has:
    field: name
    pattern: $NAME' ;;
    esac
    # pipefail disabled in this subshell only: zero matches make ast-grep exit
    # non-zero (as does grep on empty input), which would otherwise abort the
    # loop under set -o pipefail. The grep keeps only plain ASCII identifiers:
    # destructuring declarators bind the whole pattern text (`{a, b}`) as
    # $NAME, and assert_safe_identifier below exit-64s on those — drop them
    # here instead (orphans.sh:137 precedent). Deliberate trade-off (Ralph
    # Tier-2/3 #546): JS/TS `$`-identifiers (`data$`, `$emit`) and non-ASCII
    # identifiers (`def café()`) are ALSO dropped silently and their call
    # sites uncounted — assert_safe_identifier rejects both classes, so
    # pre-#546 the same symbols exit-64'd the WHOLE run; silent-drop is the
    # milder failure mode, and the raw counter-query lane (playbook #484
    # W6.4) is the recall backstop.
    SYMBOLS=$( set +o pipefail
        ast-grep scan --inline-rules "$EXTRACT_RULE" --json=stream "$FILE" 2>/dev/null \
            | jq -r '.metaVariables.single.NAME.text // empty' \
            | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*$' \
            | sort -u )
    COUNT=0
    for SYM in $SYMBOLS; do
        [[ -z "$SYM" ]] && continue
        assert_safe_identifier "$SYM"
        # #544: count BOTH call-site shapes, mirroring the #496 fix in
        # sst3-code-callers.sh — the bare pattern alone is a 100% recall miss
        # on receiver-qualified calls (field-expression callee: `self.method()`
        # / `obj.method()`). The two shapes are structurally disjoint
        # (identifier vs field-expression callee), so summing never
        # double-counts a call site. Extraction above is kind-based (#546),
        # so method/pub symbols now reach these queries in every language.
        N=$(count_call_sites "${SYM}(\$\$\$)")
        N2=$(count_call_sites "\$SST3_RECV.${SYM}(\$\$\$)")
        COUNT=$((COUNT + N + N2))
        # #546: language-specific THIRD shapes — each a structurally distinct
        # callee node the first two cannot match (disjointness empirically
        # verified both directions, so summing never double-counts):
        #   rust — scoped-path calls `lib::f()` / `crate::lib::f()` /
        #   `self::f()` (scoped_identifier callee — the dominant Rust call
        #   style); one pattern matches every segment depth.
        #   ts/tsx/js — optional-chain calls `obj?.m()`; the plain-dot
        #   receiver pattern does NOT match them (and `?.` does not match
        #   plain-dot calls).
        case "$LANG" in
            rust)                      N3=$(count_call_sites "\$SST3_PATH::${SYM}(\$\$\$)") ;;
            typescript|tsx|javascript) N3=$(count_call_sites "\$SST3_RECV?.${SYM}(\$\$\$)") ;;
            *)                         N3=0 ;;
        esac
        COUNT=$((COUNT + N3))
    done
    jq -nc --arg f "$FILE" --argjson c "$COUNT" '{changed_file: $f, impacted_callers: $c}'
done <<< "$CHANGED"

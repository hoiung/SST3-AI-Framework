#!/usr/bin/env bash
# sst3-code-subclasses.sh — Reverse-inheritance lookup for a class via ast-grep.
#
# Usage:   sst3-code-subclasses.sh <class_name> <lang>
# Example: sst3-code-subclasses.sh BaseStrategyController python
# Output:  NDJSON, one object per subclass: {file, line, kind:"subclass", child}
#          line is a 1-indexed editor line (#547 AC 7.1).
# Engines: ast-grep --json=stream + jq base-list filter.
#
# #445 R4 (Bug D): companion to sst3-code-callers.sh, which is blind to
# inheritance — it only matches expression-position calls `Foo($$$)`, not
# `class Bar(Foo):` ClassDef nodes. On <consumer-public-1>,
# BaseStrategyController has 5 production subclass + production-call sites
# that callers.sh missed entirely. This wrapper closes that gap.
#
# Type-annotation references (`def f(x: Foo)`) and string-interpolated
# patches (`f"{MOD}.Foo._x"`) are deferred to future companion wrappers
# (sst3-code-typerefs.sh / sst3-code-stringrefs.sh) — different AST kinds,
# different engines.

set -euo pipefail
export LC_ALL=C


SST3_EMITTED_COUNT="${SST3_EMITTED_COUNT:-0}"
on_sigterm() {
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg n "sst3-code-subclasses" --argjson e "${SST3_EMITTED_COUNT:-0}" \
            '{kind:($n + "-killed"), reason:"sigterm", partial_records:$e}'
    else
        printf '{"kind":"%s-killed","reason":"sigterm","partial_records":%s}\n' \
            "sst3-code-subclasses" "${SST3_EMITTED_COUNT:-0}"
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

if [[ $# -lt 2 ]]; then
    echo "ERROR: usage: $(basename "$0") <class_name> <lang>" >&2
    exit 64
fi

SYMBOL="$1"
# #548: route through the shared normaliser (see callees.sh for rationale).
# jsx -> javascript lands on the dedicated javascript arm below, which exists
# because `language: javascript` cannot use the abstract_class_declaration kind.
LANG=$(normalise_lang "$2")

assert_safe_identifier "$SYMBOL"

if ! command -v ast-grep >/dev/null 2>&1; then
    echo 'ERROR: ast-grep not installed; see dotfiles/docs/guides/code-query-playbook.md "Wrapper-Script Lane > Install"' >&2
    exit 127
fi

# Per-language class-definition query. Python keeps its shape pattern (the
# parenthesised base-list form matches all python class shapes); ts/tsx, js
# and rust use kind-rules (#547 AC 4.1/4.2 — D6+D7): shape patterns cannot
# match nodes carrying extra children (abstract/decorated classes, generic +
# where-clause impls). The ts/tsx vs js SPLIT is probe-forced:
# `abstract_class_declaration` is a TS-only kind — referencing it under
# `language: javascript` is a load-time HARD "Invalid Kind" error even in
# unreachable `any:` branches.
case "$LANG" in
    python)
        # shellcheck disable=SC2016
        PATTERN='class $NAME($$$BASES): $$$BODY'
        ;;
    typescript|tsx)
        # shellcheck disable=SC2016  # $NAME/$BASE are ast-grep meta-vars
        RULE="id: subclasses
language: $LANG
rule:
  any:
    - kind: class_declaration
    - kind: abstract_class_declaration
  all:
    - has: {field: name, pattern: \$NAME}
    - has: {kind: class_heritage, has: {kind: extends_clause, has: {field: value, pattern: \$BASE}}}"
        ;;
    javascript)
        # js grammar has no abstract-class syntax and its class_heritage
        # holds a bare identifier (no extends_clause wrapper).
        # shellcheck disable=SC2016
        RULE='id: subclasses
language: javascript
rule:
  kind: class_declaration
  all:
    - has: {field: name, pattern: $NAME}
    - has: {kind: class_heritage, has: {kind: identifier, pattern: $BASE}}'
        ;;
    rust)
        # Rust uses impl blocks for trait/inheritance composition.
        # `impl <Trait> for <Type>` — match $TYPE implementing $SYMBOL trait.
        # impl_item is the same top-level kind across plain/generic/where
        # impls, so ONE rule covers all three; `all:` nesting is mandatory
        # (duplicate sibling `has:` keys are a hard parse error).
        # shellcheck disable=SC2016
        RULE='id: subclasses
language: rust
rule:
  kind: impl_item
  all:
    - has: {field: trait, pattern: $TRAIT}
    - has: {field: type, pattern: $TYPE}'
        ;;
    *)
        echo "ERROR: unsupported lang: $LANG (supported: python, typescript, tsx, javascript, rust)" >&2
        exit 64
        ;;
esac

case "$LANG" in
    python)
        # #547 AC 6.1: buffer-then-check — the rc gate runs BEFORE jq sees the
        # stream, so a broken engine's garbage stdout can neither crash jq nor
        # leak bare stderr into review.sh's `$(... 2>&1)` composition capture.
        AG_OUT=$(mktemp)
        AG_RC=0
        ast-grep run --pattern "$PATTERN" --lang python --json=stream > "$AG_OUT" 2>/dev/null || AG_RC=$?
        ast_grep_check_rc "sst3-code-subclasses" "$AG_RC" || { rm -f "$AG_OUT"; exit 0; }
        # #547 Stage-5 sibling-recall fix: strip a subscript suffix off the base
        # text before equality — a generic base `class X(Repo[User])` binds BASES
        # text `Repo[User]`, which fails bare-`Repo` equality without the strip
        # (the python twin of the rust generic strip, AC 4.3). `Dict[str, Repo]`
        # → `Dict` so querying an inner type-arg (`Repo`) correctly does NOT match.
        jq -c --arg sym "$SYMBOL" '
            . as $m
            | ($m.metaVariables.multi.BASES // []) as $bases
            | if any($bases[]; (.text | sub("\\[.*$"; "")) == $sym) then
                {file: $m.file, line: ($m.range.start.line + 1), kind: "subclass",
                 child: ($m.metaVariables.single.NAME.text // "?")}
              else empty end
          ' < "$AG_OUT"
        rm -f "$AG_OUT"
        ;;
    typescript|tsx|javascript)
        # Combined consumption arm — --json=stream output is grammar-agnostic
        # once the RULE is per-arm. ts $BASE binds the BARE identifier even
        # for `extends Foo<T>` (probe-verified), so no strip is needed here.
        AG_OUT=$(mktemp)
        AG_RC=0
        ast-grep scan --inline-rules "$RULE" --json=stream > "$AG_OUT" 2>/dev/null || AG_RC=$?
        ast_grep_check_rc "sst3-code-subclasses" "$AG_RC" || { rm -f "$AG_OUT"; exit 0; }
        jq -c --arg sym "$SYMBOL" '
            . as $m
            | if ($m.metaVariables.single.BASE.text // "") == $sym then
                {file: $m.file, line: ($m.range.start.line + 1), kind: "subclass",
                 child: ($m.metaVariables.single.NAME.text // "?")}
              else empty end
          ' < "$AG_OUT"
        rm -f "$AG_OUT"
        ;;
    rust)
        # #547 AC 4.3 (rust-only generic strip): impl_item fields RETAIN
        # generics — `impl<T> Container<T> for Holder` binds $TRAIT =
        # `Container<T>` — so strip the argument suffix before equality.
        AG_OUT=$(mktemp)
        AG_RC=0
        ast-grep scan --inline-rules "$RULE" --json=stream > "$AG_OUT" 2>/dev/null || AG_RC=$?
        ast_grep_check_rc "sst3-code-subclasses" "$AG_RC" || { rm -f "$AG_OUT"; exit 0; }
        jq -c --arg sym "$SYMBOL" '
            . as $m
            | if (($m.metaVariables.single.TRAIT.text // "") | sub("<.*$"; "")) == $sym then
                {file: $m.file, line: ($m.range.start.line + 1), kind: "trait_impl",
                 child: ($m.metaVariables.single.TYPE.text // "?")}
              else empty end
          ' < "$AG_OUT"
        rm -f "$AG_OUT"
        ;;
esac

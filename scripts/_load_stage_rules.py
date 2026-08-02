#!/usr/bin/env python3
"""_load_stage_rules.py — per-stage canon section extractor.

Internal helper for `load-stage-rules.sh` (#498 Stage 5 L1C F3 — moves the
extraction Python out of an embedded heredoc so it can share the
`sst3_stage_tag_parser.py` regex constants with `check-stage-tags.py`).

Args:
  argv[1] : stage token (`1`-`5` or `always`)
  argv[2:]: canon file paths, optionally preceded by `--root <repo-root>`

`--root` is how the provenance header in the emitted output is anchored. It is
optional and positional args are unchanged, so the existing
`_load_stage_rules.py <stage> <file>...` contract still works (test harnesses
rely on it). `load-stage-rules.sh` always passes it, which keeps root
resolution in ONE place rather than duplicating layout detection here.

Emits matched sections to stdout. Sections without a tag are NOT emitted —
explicit tagging is required for ##/### (tagging-coverage gate is AC 4.5).
A `####` sub-heading is honoured at its OWN tag's stages when tagged, else it
INHERITS its nearest tagged ##/### ancestor (#514 Stage 5 — so a stage-1/2/3/5
rule no longer silently loads at the parent's Stage-4 tag). Resolution lives in
`sst3_stage_tag_parser.walk_sections`.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Shared parser — same module as check-stage-tags.py imports.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from sst3_stage_tag_parser import TAG_RE, walk_sections  # noqa: E402


def canon_label(canon: Path, root: Path | None) -> str:
    """Provenance path for the emitted header. Depth-free, never raises.

    Was `canon.relative_to(canon.parents[2])`, which hard-codes a two-deep
    layout. That is correct only for `<repo>/standards/`. In the flattened
    public mirror, `parents[2]` is the checkout's PARENT, so the header became
    `<checkout-dir>/standards/STANDARDS.md` -- wrong, and it leaked the name of
    whatever directory the adopter cloned into. At a root-level checkout
    (`/standards/STANDARDS.md`) it raised IndexError outright. This file carries
    no path literal for a text transform to rewrite, so the mirror transform
    chain could never have fixed it -- which is why it had to land before
    publication rather than after (#552 AC 1.0).

    Order: the root the caller resolved, then an `SST3` path segment, then the
    immediate parent. The `SST3` literal carries no trailing slash, so
    `path_scrub`'s `_SST3_SELF_RE` does not rewrite it in the mirror -- verified
    post-transform per AC 2.3.
    """
    if root is not None:
        try:
            return canon.relative_to(root).as_posix()
        except ValueError:
            pass
    for parent in canon.parents:
        if parent.name == "SST3":
            return canon.relative_to(parent.parent).as_posix()
    return f"{canon.parent.name}/{canon.name}"


def section_matches(stage_set: set[str], wanted: str) -> bool:
    if wanted == "always":
        return "always" in stage_set
    return "always" in stage_set or wanted in stage_set


def emit_canon(
    canon: Path, stage_arg: str, root: Path | None = None
) -> tuple[bool, bool]:
    """Emit this file's matching sections.

    Returns (emitted_anything, emitted_stage_specific).

    Both halves are load-bearing, and the SECOND exists because the first was not
    enough (#552 Ralph round 7 introduced it, round 9 found it inert).

    `emitted_anything` catches a canon file that matches NOTHING: it emits nothing
    and raises nothing, so with three files supplied the other two still fill the
    buffer and every downstream non-empty check passes.

    `emitted_stage_specific` catches the quieter case that first return MISSES.
    `section_matches` treats an `always`-tagged section as matching EVERY stage, and
    all three canon files carry `always` tags (STANDARDS.md 8, ANTI-PATTERNS.md 2,
    WORKFLOW.md 1). So a file can lose 100% of its stage-N content and still report
    "contributed", because its always-carve-out sections keep emitting. Measured
    PRE-FIX at 93856c0d (these are historical figures, not current pins -- the
    mutation now fails closed, so they cannot be re-derived): neutralising all 10
    stage-4 tags in WORKFLOW.md took stage 4 from 268607 to 243155 bytes (-9.5%),
    and all 5 stage-3 tags in ANTI-PATTERNS.md took stage 3 from 68139 to 50446
    (-26%), both at rc=0 with empty stderr. That is the round-7
    fail-open surviving inside the round-7 fix -- an aggregate guard that does not
    guard its parts, one level down. See main() for the exemption this forces.
    """
    text = canon.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=False)
    sections = walk_sections(lines)
    if not sections:
        return (False, False)

    file_emitted_header = False
    emitted_stage_specific = False
    for sec in sections:
        if not section_matches(sec["effective"], stage_arg):
            continue
        start_idx = sec["body_start"]
        end_idx = sec["body_end"]
        # Strip a trailing tag-comment (and trailing blanks) that belongs to
        # the NEXT heading so it is not emitted as part of this body.
        back = end_idx - 1
        while back > start_idx and not lines[back].strip():
            back -= 1
        if back > start_idx and TAG_RE.search(lines[back]):
            end_idx = back
        # A section counts as stage-SPECIFIC when the requested stage is named
        # EXPLICITLY in its tag, rather than being reached via the always-carve-out.
        # Testing membership directly is what makes that precise; the first version
        # of this check asked "does this section NOT match 'always'", which
        # misclassified a combined tag (#552 Ralph Tier 2 round 10). A section
        # tagged `<!-- stages: 3,always -->` is grammar-valid, names stage 3
        # outright, and was being counted as always-only -- so a file whose stage-3
        # content all carried combined tags would be rejected with an error text
        # ("every stage-'3' tag is missing or malformed") that was flatly untrue of
        # the input. Reproduced at rc=1 on a synthetic canon file before the fix.
        # Membership also collapses the stage_arg == 'always' case correctly:
        # 'always' in the set is exactly the right test there, so no special case.
        if stage_arg in sec["effective"]:
            emitted_stage_specific = True
        if not file_emitted_header:
            print(f"\n<!-- ===== {canon_label(canon, root)} ===== -->")
            file_emitted_header = True
        for body_idx in range(start_idx, end_idx):
            print(lines[body_idx])
    return (file_emitted_header, emitted_stage_specific)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(
            "usage: _load_stage_rules.py <stage> [--root <repo-root>] <canon-file>...",
            file=sys.stderr,
        )
        return 1
    stage_arg = argv[1]
    rest = argv[2:]
    root: Path | None = None
    if rest and rest[0] == "--root":
        if len(rest) < 3:
            print("error: --root needs a path and at least one canon file", file=sys.stderr)
            return 1
        root = Path(rest[1])
        rest = rest[2:]
    canon_files = [Path(p) for p in rest]
    # PER-FILE contribution guard (#552 Ralph Tier 2 round 7). The loader's
    # `[[ -s "$EXTRACT_OUT" ]]` check catches a TOTAL zero-byte extraction, which
    # is the loud failure. The quiet one is a SINGLE canon file matching nothing
    # while its siblings still emit: the buffer is non-empty, the loader exits 0,
    # stderr is empty, and an entire source file's governance content is gone.
    #
    # Reproduced before fixing: stripping every `<!-- stages: -->` tag from
    # ANTI-PATTERNS.md (a hook-bypassed commit, a web-UI edit, an admin merge)
    # dropped the `always` subset from 17913 to 15125 bytes -- 2788 bytes, 15.6%,
    # including part of the privacy / voice / destructive-op carve-out this
    # loader's own header names as the reason the subset exists -- at exit 0 with
    # empty stderr. That is the exact fail-open shape #552 exists to close,
    # surviving inside the fix for it.
    #
    # Applied to EVERY stage, not just `always`, because it was measured rather
    # than assumed: all 18 (3 files x 6 stages) combinations currently emit
    # non-zero, so a silent file is an anomaly in every stage. Returning non-zero
    # routes through the loader's existing `if ! python3 ...` branch, so the
    # operator sees the `load-stage-rules:` sentinel -- no new failure mechanism.
    #
    # KNOWN LIMIT -- this guard is per-FILE, not per-SECTION, and the error text
    # says so deliberately. It fires only when a canon file contributes NOTHING.
    # Partial loss WITHIN a file stays silent: stripping 9 of the 10 stage-4-bearing
    # tags from WORKFLOW.md alone took stage 4 from 268607 to 243251 bytes (-9.4%,
    # measured pre-fix at 93856c0d; historical, not a current pin)
    # at rc=0 with empty stderr, because that file still emitted one section. An
    # earlier draft of the message claimed to refuse "a silently-partial subset",
    # which overclaimed exactly that gap (#552 Ralph round 9). Closing it here would
    # need a per-stage expected-section count, which drifts as canon is edited and
    # would fail closed on every legitimate edit; the common path is instead covered
    # by the `sst3-stage-tags` pre-commit hook, which validates tag well-formedness
    # at authoring time. State the bound rather than implying the stronger property.
    results = {canon: emit_canon(canon, stage_arg, root) for canon in canon_files}
    silent = [canon for canon, (any_, _) in results.items() if not any_]

    # Second guard: a file that emitted ONLY via the always-carve-out has lost all
    # of its stage-N content while still looking like a contributor. No file is
    # exempt: every (file, stage) combination carries at least one stage-specific
    # section (#555 AC 2.3 re-tagged WORKFLOW.md's Stage-3 checklist from `always`
    # to `2,3`, closing the one legitimate zero this guard used to exempt). If a
    # future canon edit removes the last stage-specific section from a file, this
    # fails CLOSED and names it -- the intended direction: that state is
    # indistinguishable from the silent-drop this loader exists to prevent, and a
    # deliberate removal should have to declare an exemption here.
    always_only = [
        canon
        for canon, (any_, specific) in results.items()
        if any_ and not specific
    ]
    # Report EVERY failure class present, not just the first. A silent file and
    # an always-only file can fail in the SAME invocation; returning after the
    # first named only one, so the operator fixed it, re-ran, and only then saw
    # the second. Both paths already fail closed (rc=1); this makes the diagnostic
    # name every offending file at once, which is the "name the offending file"
    # thesis applied to the two-failure case (#552 Stage 5).
    failed = False
    if always_only:
        names = ", ".join(str(c) for c in always_only)
        print(
            f"error: canon file(s) emitted ONLY always-carve-out sections for stage "
            f"'{stage_arg}': {names}. Every stage-'{stage_arg}' tag in the file is "
            f"missing or malformed, so its stage content is gone while the file still "
            f"appears to contribute. Refusing to emit a subset that is missing a whole "
            f"file's stage content.",
            file=sys.stderr,
        )
        failed = True

    if silent:
        names = ", ".join(str(c) for c in silent)
        print(
            f"error: canon file(s) contributed NOTHING for stage '{stage_arg}': {names}. "
            f"Expected every supplied canon file to emit at least one section. "
            f"Most likely cause: its `<!-- stages: ... -->` tags are missing or malformed. "
            f"Refusing to emit a subset that is missing a whole canon file.",
            file=sys.stderr,
        )
        failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

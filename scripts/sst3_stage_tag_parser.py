"""sst3_stage_tag_parser.py — shared module for `<!-- stages: -->` tag parsing.

Single source of truth for the stage-tag grammar + tag-walk algorithm (#498
Stage 5 L1C F3). Imported by both `check-stage-tags.py` (audit script) and
`_load_stage_rules.py` (per-stage canonical loader). If the tag grammar ever
changes, update only HERE.

Grammar (per #498 AC 4.3):
  <!-- stages: <token>[,<token>]* -->
  where <token> is `always` or a single digit 1-5.

Algorithm: every `## ` / `### ` heading must be immediately preceded by a tag
comment (skipping blank lines).

`####` sub-headings (#514 Stage 5): a `####` is OPTIONALLY taggable. When a
`####` carries its own `<!-- stages: -->` tag the loader honours it (the rule
loads at exactly those stages); when it does not, the `####` INHERITS its
nearest tagged `##`/`###` ancestor's stages. `HEADING_RE` (the coverage gate's
`####`-exempt matcher) is unchanged — `####` tags are an opt-in override, not a
new mandatory-coverage requirement. `walk_sections` resolves effective stages
for every heading level; `extract_governing_stages` recovers, from a `####`'s
own prose, the stages it CLAIMS to govern so the checker can flag a `####`
whose inherited tag silently excludes a stage it governs (the dotfiles#514
FINDING-B class: a stage-1/2/3/5 rule riding a `<!-- stages: 4 -->` parent).
"""

from __future__ import annotations

import re

HEADING_RE = re.compile(r"^(#{2,3})\s+(.+?)\s*$")
# SUBHEADING_RE additionally matches `####` — used by the loader (to honour
# per-#### tags) and the checker guard (to detect governing-vs-inherited
# mismatch). NOT used by the ##/### coverage gate, which keeps #### exempt.
SUBHEADING_RE = re.compile(r"^(#{2,4})\s+(.+?)\s*$")
TAG_RE = re.compile(r"<!--\s*stages:\s*([^>]+?)\s*-->")
VALID_TOKEN_RE = re.compile(r"^(always|[1-5])$")
# A governing stage reference: "Stage 1" .. "Stage 5" with a SPACE (so
# "pre-Stage-3" / "Stage-4" hyphenated cross-refs do NOT match — those are
# pointers, not scope declarations).
_STAGE_TOK_RE = re.compile(r"\bStage\s+([1-5])\b")
# The same declaration in the corpus's abbreviated notation: `Leader.md S1/S3/S5`.
# Only SLASH-JOINED RUNS count, never a bare `S3` — a lone token collides with
# ordinary prose ("S3 bucket"), while no sentence writes "S1/S3" by accident.
# Without this, one item of a list binds and its neighbour does not purely on
# notation: ANTI-PATTERNS.md AP #19's "12 subagent-only moments" writes item 6 as
# `WORKFLOW.md Stage 3` (binds) and item 4 as `Leader.md S1/S3/S5` (did not).
_STAGE_RUN_RE = re.compile(r"\bS[1-5](?:/S[1-5])+\b")
_PAREN_RE = re.compile(r"\(([^()]*)\)")
# Binding-vs-mention discriminators for `extract_binding_stages` (Issue #54).
# The wiring artifacts are the two files that DEFINE the stages — naming one
# beside a `Stage N` token is what makes a sentence bind rather than narrate.
_WIRING_ARTIFACT_RE = re.compile(r"\b(?:Leader|WORKFLOW)\.md\b")
# Retrospective / pointer fields: they record where a failure was OBSERVED, or
# point at a kin rule. Never a binding, even when they name an artifact and a
# stage. Only these three qualify — each is backwards-looking or referential by
# definition, so an artifact+stage inside one describes history, not wiring.
#
# All three are load-bearing, each proven by ablation. Against the LIVE corpus,
# dropping `Related` re-tags AP #21 off its `**Related**: ... Leader.md Stage 5
# DON'T list` pointer. `Evidence` and `Root Cause` bind nothing on today's live
# corpus, but both are pinned by the checked-in false-positive fixture — case
# (h) of test_stage_tag_subscope.sh: drop `Evidence` and it false-positives on
# Stage 5, drop `Root Cause` and it false-positives on Stage 1. So none of the
# three is dead weight under JBGE, and a regression in any one fails the suite.
#
# `Pattern` and `Self-Healing` were briefly in this list and were REMOVED
# (Issue #54 Ralph Tier 3): both are PRESCRIPTIVE in this corpus — the
# `**Pattern**` field carries the normative rule statement (see AP #20, #21 and
# #22) and `**Self-Healing**` carries actor instructions (see AP #3). Excluding
# them was a latent false negative in the exact defect class this rule exists
# to close.
#
# Cite anti-patterns by NUMBER + FIELD NAME, never by line number: these
# citations are into a file other issues edit concurrently. An earlier revision
# named exact lines, and parallel work on master inserted 19 lines above them,
# silently pointing every citation at unrelated content (Issue #54 Stage 5).
_NARRATIVE_FIELD_RE = re.compile(r"^\*\*(?:Evidence|Related|Root Cause)\*\*")
_FENCE_RE = re.compile(r"^\s*```")


def find_tag_for_heading(lines: list[str], heading_idx: int) -> tuple[int, str | None]:
    """Walk backward from heading line (skipping blanks) and return the first
    line containing a `<!-- stages: -->` tag.

    Args:
      lines: file lines, 0-indexed.
      heading_idx: index of the heading line in `lines`.

    Returns:
      (tag_line_idx, tag_value) — `tag_value` is the raw token list string
      (e.g. `"always"` or `"1,4"`). Returns (-1, None) if no tag found before
      a non-blank non-tag line OR before file start.
    """
    j = heading_idx - 1
    while j >= 0 and not lines[j].strip():
        j -= 1
    if j < 0:
        return (-1, None)
    m = TAG_RE.search(lines[j])
    if not m:
        return (j, None)
    return (j, m.group(1))


def validate_tokens(raw_token_str: str) -> tuple[list[str], list[str]]:
    """Split a raw tag value into tokens; return (valid_tokens, invalid_tokens)."""
    tokens = [t.strip() for t in raw_token_str.split(",")]
    valid = [t for t in tokens if VALID_TOKEN_RE.match(t)]
    invalid = [t for t in tokens if not VALID_TOKEN_RE.match(t)]
    return (valid, invalid)


def parse_stages(tag_value: str | None) -> set[str]:
    """Convert `<!-- stages: 1,2,always -->` → set of stage tokens."""
    if not tag_value:
        return set()
    return {p.strip() for p in tag_value.split(",") if p.strip()}


def walk_sections(lines: list[str]) -> list[dict]:
    """Resolve every ##/###/#### heading to its effective stage set.

    Effective stages = the heading's OWN `<!-- stages: -->` tag if present,
    else INHERITED from the nearest preceding heading of a shallower level
    (a `####` rides its `###` parent; a `###` its `##` parent). Returns one
    dict per heading with keys: idx, level, title, own (set), effective (set),
    body_start, body_end (next-heading idx of ANY level, or len(lines)).
    """
    raw: list[tuple[int, int, str]] = []
    for idx, line in enumerate(lines):
        m = SUBHEADING_RE.match(line)
        if m:
            raw.append((idx, len(m.group(1)), m.group(2)))

    sections: list[dict] = []
    stack: list[tuple[int, set[str]]] = []  # (level, effective_stages)
    for n, (idx, level, title) in enumerate(raw):
        _, tag_value = find_tag_for_heading(lines, idx)
        own = parse_stages(tag_value)
        while stack and stack[-1][0] >= level:
            stack.pop()
        inherited = stack[-1][1] if stack else set()
        effective = own if own else inherited
        stack.append((level, effective))
        body_end = raw[n + 1][0] if n + 1 < len(raw) else len(lines)
        sections.append(
            {
                "idx": idx,
                "level": level,
                "title": title,
                "own": own,
                "effective": effective,
                "body_start": idx,
                "body_end": body_end,
            }
        )
    return sections


def extract_governing_stages(title: str, body: str) -> set[str]:
    """Recover the stages a rule CLAIMS to govern from its own prose.

    Conservative — only STRONG governing signals (low false-positive), so a
    lone hyphenated cross-reference like "Stage-4 Gate 1" does NOT register:
      (a) heading-leading "Stage N ..." (e.g. "Stage 1 Layer-2 Adversarial").
      (b) any parenthetical enumerating >=2 distinct "Stage N" with a space
          (e.g. "(Stage 1 research, Stage 2 draft-check, Stage 5 audit)").

    Returns a set of digit strings. Empty = no strong governing claim found.
    """
    gov: set[str] = set()
    hm = re.match(r"^Stage\s+([1-5])\b", title.strip())
    if hm:
        gov.add(hm.group(1))
    for paren in _PAREN_RE.findall(f"{title}\n{body}"):
        nums = set(_STAGE_TOK_RE.findall(paren))
        if len(nums) >= 2:
            gov |= nums
    return gov


def has_enforcement_line(body: str) -> bool:
    """True when the block carries an `**Enforcement**:` field at all.

    Coverage bookkeeping (Issue #54): a section with neither an Enforcement
    line nor an artifact-anchored binding gives the stage-binding audit nothing
    to parse, so a pass over it is silence, not evidence. Callers use this to
    report an honest denominator instead of a blanket clean pass.
    """
    return any(line.lstrip().startswith("**Enforcement**") for line in body.splitlines())


def extract_binding_stages(body: str) -> set[str]:
    """Recover the stages a `## Anti-Pattern` body BINDS itself to, from its
    prose rather than its `**Enforcement**:` field (Issue #54).

    Why this exists: `extract_enforcement_stages` reads the `**Enforcement**:`
    line only, and just 17 of 30 anti-patterns carry one — of those, only 4 name
    a stage. AP #14 binds itself to "Leader.md Stage 1 and Stage 5 angle prompts"
    in its 14e body while its Enforcement line names no stage at all, so the
    Enforcement-only path reported a clean pass on a live mis-tag.

    THE RULE — what counts as a BINDING vs a mere MENTION:

      A line is a BINDING when it (a) names a wiring artifact the stage agent
      actually executes — `Leader.md` or `WORKFLOW.md`, the two files that
      DEFINE the stages — AND (b) carries a space-form `Stage N` token on that
      same line. Both halves are required: the artifact is what turns "this
      happened at Stage 3" into "this rule fires at Stage 3".

      A line is NOT a binding when it is:
        - inside a fenced code block (sample commands, not wiring);
        - a retrospective or pointer field — `**Evidence**` / `**Related**` /
          `**Root Cause**`. These record where a failure was OBSERVED or point
          at kin rules; they do not bind. AP #21's `**Related**: ... Leader.md
          Stage 5 DON'T list` is the worked case — a pointer, so it must not
          re-tag AP #21. NOTE the list stops there: `**Pattern**` and
          `**Self-Healing**` are PRESCRIPTIVE in this corpus and must stay
          eligible to bind;
        - hyphenated (`Stage-4`, `pre-Stage-3`) — `_STAGE_TOK_RE` already
          treats those as cross-references, per this module's convention.

    Deliberately conservative: it under-claims rather than over-claims, because
    a false positive re-tags a correct anti-pattern and widens what every agent
    loads. Verified against all 30 live anti-patterns — it flags exactly #14
    (adds 1,3,5), #19 (adds 1,3,5) and #24 (adds 1). Re-derive this list by
    running the guard rather than trusting it: it changed once already, when
    `_STAGE_RUN_RE` recovered AP #19's abbreviated `S1/S3/S5` binding.

    KNOWN REACH LIMITS — there are TWO, and they are different failure modes.
    State them separately; three earlier drafts of this docstring conflated
    them:

      (i) NO ARTIFACT ANCHOR — AP #23, and AP #21's real binding. A body can
          state a genuine stage obligation in an ELIGIBLE field and still not
          bind, simply because no `Leader.md` / `WORKFLOW.md` token sits beside
          it. AP #23 is the pure case: its body carries ZERO artifact tokens,
          so nothing can match. Its bullet beginning "Stage 5 subagent flags an
          audit verdict…" reads like a real Stage-5 binding. The rule is not
          silent here because it judged; it is silent because it cannot see.

     (ii) ANCHOR PRESENT BUT SUPPRESSED — AP #21's `**Related**` pointer only.
          That field names `Leader.md` beside `Stage 5`, and the `Related`
          exclusion discards it as a pointer, which is correct: it points at a
          kin rule rather than wiring one.

          Do NOT read (ii) as the whole story for AP #21 — an earlier revision
          did, and it was wrong. AP #21's SUBSTANTIVE Stage-5 obligation lives
          in its `**Pattern**` and `**How to apply**` fields, both deliberately
          eligible to bind. They fail for lack of an artifact anchor, so AP #21
          is materially a case (i), and a smarter field rule would not recover
          it — only an anchor in those fields would.

          Live consequence, unfixed: AP #21 loads at Stage 2 ONLY, while
          `Leader.md`'s Stage-5 DON'T list names AP #21 by name. A Stage-5
          agent is told to obey a rule it never loads — this rule's own defect
          class, still live in the corpus it audits.

    All of these sit in the unparseable set `ap_binding_coverage` counts out
    loud, and are named in Issue #54 deferral D5. Do NOT read this rule's
    silence as a clean bill of health for the blind set. (AP #30 is sometimes
    cited here too; its body names exactly one stage, `Stage 3`, in its
    `**Enforcement**` line, and its tag already covers it. It never carried a
    Stage-1 claim to reject.)

    Returns a set of digit strings. Empty = no artifact-anchored binding.
    """
    gov: set[str] = set()
    in_fence = False
    for line in body.splitlines():
        if _FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if _NARRATIVE_FIELD_RE.match(line.lstrip()):
            continue
        if not _WIRING_ARTIFACT_RE.search(line):
            continue
        gov |= set(_STAGE_TOK_RE.findall(line))
        for run in _STAGE_RUN_RE.findall(line):
            gov |= set(re.findall(r"[1-5]", run))
    return gov


def extract_enforcement_stages(body: str) -> set[str]:
    """Recover the stages a `## Anti-Pattern` block declares it is ENFORCED at,
    from its `**Enforcement**:` line(s) only (dotfiles#516 Stage 5).

    The Enforcement line is a structured field naming WHERE the rule binds
    ("Leader.md Stage 3 step 4", "WORKFLOW.md Stage 5 CI pre-flight",
    "Leader.md Stage 3 + Stage 5 ... sub-prompt"). An AP tagged to load at a
    stage that EXCLUDES its enforcement stage is the AP #28 / AP #25 class:
    the agent at the enforcing stage never loads the anti-pattern that governs
    its work. `extract_governing_stages` cannot see this (it matches only
    heading-leading or parenthetical-enumerated stages, not Enforcement prose).

    Scoped to the Enforcement line(s) to stay low-false-positive: the rest of
    an AP body is narrative ("Stage 5 finds 'code written'") and must NOT
    register. Space form (`Stage N`) only — hyphenated cross-refs
    (`pre-Stage-3`, `Stage-4`) are pointers, not enforcement bindings.

    Returns a set of digit strings. Empty = no Enforcement stage binding found.
    """
    gov: set[str] = set()
    for line in body.splitlines():
        if line.lstrip().startswith("**Enforcement**"):
            gov |= set(_STAGE_TOK_RE.findall(line))
    return gov

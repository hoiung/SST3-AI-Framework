#!/usr/bin/env python3
"""
Single source of truth for operator-voice guard rules.

Canonical Python copy of the rules described in the human-readable companion
`dotfiles/voice/base/VOICE_PROFILE.md` Section 8 (anti-vocabulary) and Section 19
(banned phrases / AI tells the operator never makes).

This module is consumed by:
  - dotfiles/SST3/scripts/check-ai-writing-tells.py  (canonical hook)
  - hoiboy-uk/scripts/check-ai-writing-tells.py      (vendored byte-identical)
  - hoiboy-uk/scripts/voice_rules.py                 (vendored byte-identical)

Drift between canonical and vendored copies is enforced by a `cmp -s` bash
pre-commit hook in hoiboy-uk. There is no parsed mirror of VOICE_PROFILE.md;
the markdown is documentation, this file is the executable canonical.

Issue: hoiung/dotfiles#404
"""

from dataclasses import dataclass
from datetime import date
import re

# ---------------------------------------------------------------------------
# Cutoff date — hoiboy-uk legacy/new boundary
# ---------------------------------------------------------------------------
# Posts dated < this date are voice-sacred legacy and exempt from scanning.
# Posts dated >= this date are eligible (default still SKIP unless tagged).
HOIBOY_CUTOFF_DATE: date = date(2026, 4, 7)

# ---------------------------------------------------------------------------
# Markers (greenfield convention; HTML-comment form invisible in render)
# ---------------------------------------------------------------------------
MARKER_OPEN_HTML = "<!-- iamhoi -->"
MARKER_CLOSE_HTML = "<!-- iamhoiend -->"
MARKER_EXEMPT_HTML = "<!-- iamhoi-exempt -->"
MARKER_SKIP_OPEN_HTML = "<!-- iamhoi-skip -->"
MARKER_SKIP_CLOSE_HTML = "<!-- iamhoi-skipend -->"

MARKER_OPEN_HASH = "# iamhoi"
MARKER_CLOSE_HASH = "# iamhoiend"
MARKER_EXEMPT_HASH = "# iamhoi-exempt"
MARKER_SKIP_OPEN_HASH = "# iamhoi-skip"
MARKER_SKIP_CLOSE_HASH = "# iamhoi-skipend"

# ---------------------------------------------------------------------------
# Single characters / small char sets
# ---------------------------------------------------------------------------
EM_DASH: str = "\u2014"
SMART_QUOTE_CHARS: tuple[str, ...] = ("\u201c", "\u201d", "\u2018", "\u2019")
UNICODE_ARROW_CHARS: tuple[str, ...] = ("\u2192", "\u21d2", "\u2190", "\u21d0")

# ---------------------------------------------------------------------------
# KEEP list — authentic the operator vocabulary (NEVER add to BANNED_WORDS)
# ---------------------------------------------------------------------------
# These words are used sincerely by the operator 50+ times across his pre-AI corpus.
# Documented in dotfiles/voice/base/VOICE_PROFILE.md Section 8.
KEEP_LIST: tuple[str, ...] = (
    "passion",
    "passionate",
    "journey",
    "deeply",
    "truly",
    "navigate",
    "back to basics",
    "attention to detail",
    "fundamentals",
    "fall in love",
    # align* family — the operator's natural vocabulary for project timeline /
    # expectation management. Whitelisted 2026-04-22 per meta-rule
    # "if I type it, I use it" (see memory/feedback_if_i_type_it_i_use_it.md).
    "align",
    "alignment",
    "aligned",
    "aligning",
    "aligns",
    "alignments",
    # Additional whitelist 2026-04-22 — the operator confirmed these are his natural
    # vocabulary in the same conversation (enterprise/project words he uses
    # in emails, chats, prep). Same meta-rule as align*.
    "synergy", "synergies",
    "leverage", "leveraging", "leveraged",
    "robust",
    "landscape",
    "dynamic",
    "deliverable", "deliverables",
    "bandwidth",
    "actionable",
    # Third pass same day — Operator note: "why is stakeholder there? I use that word".
    # Same meta-rule. stakeholder/stakeholders moved here.
    "stakeholder", "stakeholders",
    # Direction-reset vocabulary (2026-04-23) — enablement lane target-role
    # keywords + Knowledge Academy Coaching & Mentoring cert (2025) domain.
    # Added per direction-reset Thread 7 + meta-rule "if I type it, I use it".
    # NOTE: facilitate/facilitating/facilitated STAYS BANNED despite semantic
    # proximity to enablement vocabulary — corporate-speak the operator does not use
    # naturally. Prefer coach / enable / run / lead instead.
    "teach", "teaching", "teaches", "taught",
    "mentor", "mentoring", "mentored", "mentors",
    "coach", "coaching", "coached", "coaches",
    "enable", "enabling", "enabled", "enables", "enablement",
    "capability", "capabilities",
    "upskill", "upskilling", "upskilled",
    "knowledge transfer",
    "AI literacy",
    "AI fluency",
    "AI adoption",
    "domain expert", "domain experts",
    "subject matter expert", "subject matter experts",
    "SME", "SMEs",
)

# ---------------------------------------------------------------------------
# Banned words — full Section 8 anti-vocabulary list (~60 entries)
# ---------------------------------------------------------------------------
# Multi-word entries are matched as whole phrases (the `\b...\b` regex around
# escaped strings handles spaces correctly). Inflections are listed explicitly
# for fail-fast behaviour rather than relying on stemming.
BANNED_WORDS: tuple[str, ...] = (
    # Single-word AI/CV-speak
    "delve", "delving", "delved",
    "spearhead", "spearheading", "spearheaded",
    "seamless", "seamlessly",
    "cutting-edge",
    "innovative",
    "impactful",
    "facilitate", "facilitating", "facilitated",
    "furthermore",
    "moreover",
    "pivotal",
    "tapestry",
    "realm",
    "underscore", "underscores", "underscoring",
    "meticulous", "meticulously",
    "beacon",
    "testament",
    "holistic", "holistically",
    "ecosystem",
    "iterate", "iterating",
    "unpack", "unpacking",
    "utilize", "utilizing", "utilized", "utilise", "utilising", "utilised",
    "commendable",
    "noteworthy",
    "invaluable",
    "resonate", "resonates", "resonating",
    "crucial",
    # Multi-word AI/CV-speak phrases
    "low-hanging fruit",
    "touch base",
    "circle back",
    "moving forward",
    "at scale",
    "gain traction",
    "reach out",
    "results-driven",
    "detail-oriented",
    "proven track record",
    "strategic initiative",
    "drive measurable impact",
    "committed to excellence",
    "dedicated team player",
    "cross-functional collaboration",
)

# Build-time guarantee: KEEP_LIST and BANNED_WORDS never overlap.
_keep_lower = {w.lower() for w in KEEP_LIST}
_banned_lower = {w.lower() for w in BANNED_WORDS}
_overlap = _keep_lower & _banned_lower
if _overlap:
    raise RuntimeError(
        f"voice_rules.py: KEEP_LIST and BANNED_WORDS overlap: {sorted(_overlap)}"
    )

# ---------------------------------------------------------------------------
# Banned phrases — VOICE_PROFILE Section 19 (case-insensitive)
# ---------------------------------------------------------------------------
BANNED_PHRASES: tuple[str, ...] = (
    "It's worth noting that",
    "It is worth noting that",
    "It's important to remember",
    "It is important to remember",
    "Throughout my career, I have",
    "I am excited to explore opportunities",
    "I am writing to express my interest",
)

# ---------------------------------------------------------------------------
# Compiled regex patterns (compiled once at module import)
# ---------------------------------------------------------------------------
# Banned words: single case-insensitive alternation, word-boundary anchored.
# Sorted longest-first so multi-word phrases match before their substrings.
_words_sorted = sorted(BANNED_WORDS, key=len, reverse=True)
BANNED_WORDS_PATTERN: re.Pattern[str] = re.compile(
    r"\b(?:" + "|".join(re.escape(w) for w in _words_sorted) + r")\b",
    re.IGNORECASE,
)

# Banned phrases: single case-insensitive alternation.
BANNED_PHRASES_PATTERN: re.Pattern[str] = re.compile(
    "(?:" + "|".join(re.escape(p) for p in BANNED_PHRASES) + ")",
    re.IGNORECASE,
)

# Bold-first bullet pattern: "- **Word:** description" or "* **Word:** description"
BOLD_BULLET_PATTERN: re.Pattern[str] = re.compile(
    r"^[\s]*[-*]\s+\*\*[^*]+\*\*:\s",
    re.MULTILINE,
)

# Negation framing: "It's not X, it's Y"
NEGATION_PATTERN: re.Pattern[str] = re.compile(
    r"[Ii]t'?s not .{3,30}, it'?s",
    re.IGNORECASE,
)

# Bold-first bullet thresholds. CV documents legitimately use bold-first
# bullets in Core Competencies sections; non-CV docs should not.
BOLD_BULLET_THRESHOLD_CV: int = 20
BOLD_BULLET_THRESHOLD_DEFAULT: int = 3

# Frontmatter date: stdlib regex, NOT PyYAML.
# Captures the YYYY-MM-DD prefix for date.fromisoformat() downstream.
# An optional RFC3339 time component (THH:MM:SS, fractional seconds, timezone)
# is allowed and silently ignored: Hugo accepts time-bearing dates natively and
# the site templates only render the calendar date, so authors can include a
# time component when they need to control same-day sort order without it
# leaking into the rendered display. The capture group stays YYYY-MM-DD only
# so the downstream date.fromisoformat() call is unchanged.
FRONTMATTER_DATE_PATTERN: re.Pattern[str] = re.compile(
    r"^date:\s*(\d{4}-\d{2}-\d{2})(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?\s*$",
    re.MULTILINE,
)

# ---------------------------------------------------------------------------
# Structural AI-tell detectors (dotfiles#517 Phase E)
# ---------------------------------------------------------------------------
# These three detectors target STRUCTURE, not vocabulary. They are tuned
# (thresholds below) so the authentic Hoi corpus (62 raws + 2 near-publish
# blogs + 3 drafts) produces ZERO flags, while an AI-structured sample is
# flagged. The load-bearing rule (dotfiles#517): "over-factual" is NOT
# "no numbers" — Hoi uses numbers as EVIDENCE; only stat-stacking is the tell.
# The fixture gate `sample_invocation_voice_detectors.py` (AC E.5) is the
# regression guard that keeps these tuned. If a detector cannot be tuned to
# 0 authentic-flags it must fall back to prose-only (documented), NOT ship
# false positives.

# --- markup-stripping (shared) ---
# Strip HTML tags, URLs, and markdown link targets BEFORE structural analysis —
# they carry incidental digits/short-lines that are not prose AI tells (the
# false-positive class found in the corpus: Amazon affiliate links, addresses).
HTML_TAG_PATTERN: re.Pattern[str] = re.compile(r"<[^>]+>")
URL_PATTERN: re.Pattern[str] = re.compile(r"https?://\S+|www\.\S+")
MD_LINK_TARGET_PATTERN: re.Pattern[str] = re.compile(r"\]\([^)]*\)")
# Lines that are list/inventory/reference content (not prose) — skipped by the
# paragraph splitter so packing lists / address blocks do not register as
# stat-stacking. Leading list marker OR a "N x item" quantity pattern.
LIST_LINE_PATTERN: re.Pattern[str] = re.compile(r"^\s*(?:[-*+]\s|\d+[.)]\s|\d+\s*x\s)")

# --- NUMERIC_DENSITY / STAT_STACK ---
# A "word" token: alphabetic run (for the density denominator).
WORD_TOKEN_PATTERN: re.Pattern[str] = re.compile(r"\b[A-Za-z][A-Za-z'-]*\b")
# STAT_STACK counts only UNIT-BEARING / hype-flavoured numbers: a figure with a
# %, x, or $ unit ("40%", "10x", "$200", "200-500%", "3x"). Bare integers
# (years, counts, addresses, postcodes) are NOT counted — that is what made the
# first pass false-positive on addresses + packing lists. Multiplier-hype
# ("3x faster, 40% more efficient, 10x ROI, 200% growth") is exactly unit-bearing.
NUMBER_TOKEN_PATTERN: re.Pattern[str] = re.compile(r"\$\d[\d.,]*|\b\d[\d.,]*\s?(?:%|x\b)")
# A paragraph is flagged ONLY if it is substantial prose (>= MIN_WORDS) AND
# carries several hype-numbers (>= MIN_NUMBERS) that are dense (ratio >= RATIO).
# Evidence-numbers in Hoi's narrative are sparse + bare; hype stat-stacks pile
# unit-numbers. Tuned to 0 flags on the 64-file authentic corpus.
# MIN_NUMBERS=5 (raised from 4, #517 Stage 5): a terse first-person trading recap
# ("I put 25% in, made 30%, lost 40%, then recovered 35%") carries 4 unit-numbers
# as AUTHENTIC evidence, not hype — the HARD constraint is over-factual != no-
# numbers. Marketing stat-stacks pile 5+ ("3x faster, 40% more, 10x ROI, 200%
# growth, 50% cheaper"). Requiring 5 keeps the AI signal while not punishing a
# 4-number evidence sentence. Corpus max is 3 unit-numbers, so 0-FP is preserved.
NUMERIC_DENSITY_MIN_WORDS: int = 8
NUMERIC_DENSITY_MIN_NUMBERS: int = 5
NUMERIC_DENSITY_RATIO: float = 0.10

# --- RULE_OF_THREE (abstract-noun triple) ---
# The AI scaffold "X, Y, and Z" where ALL THREE items are GENERIC AI-cliché
# abstract nouns ("presence, curiosity, and clarity"). Hoi DOES write tricolons,
# including domain-abstract ones ("sensitivity, awareness, perception" in dance;
# "radiation, evaporation, respiration" in bushcraft) — so a generic abstract-
# suffix rule over-fires on authentic Hoi. The detector therefore requires all 3
# items to be in a CURATED generic-AI-cliché set that deliberately EXCLUDES the
# domain-grounded abstract words Hoi actually uses. Lower recall, ~0 FPs — the
# JBGE trade the operator approved (build minimal, do not punish authentic).
GENERIC_AI_ABSTRACT: frozenset[str] = frozenset({
    "presence", "curiosity", "clarity", "authenticity",
    "mindfulness", "intentionality", "scalability", "efficiency",
    "connection", "empowerment", "resilience", "gratitude",
    "abundance", "transformation", "innovation", "creativity", "positivity",
    "wellness", "wholeness", "purpose", "serenity", "harmony",
    "engagement", "belonging", "fulfilment",
    "fulfillment", "mindset", "wellbeing",
})
# Build-time guarantee: GENERIC_AI_ABSTRACT never overlaps KEEP_LIST. An operator-
# authentic word (alignment / synergy / synergies live in KEEP_LIST per the
# 2026-04-22 whitelist) must NOT also sit in the AI-cliche set, or RULE_OF_THREE
# would false-positive on Hoi's natural vocab (e.g. "connection, alignment, and
# resilience"). Mirrors the KEEP_LIST/BANNED_WORDS guard above. (#517 Stage 5.)
_generic_lower = {w.lower() for w in GENERIC_AI_ABSTRACT}
_keep_generic_overlap = _keep_lower & _generic_lower
if _keep_generic_overlap:
    raise RuntimeError(
        "voice_rules.py: KEEP_LIST and GENERIC_AI_ABSTRACT overlap: "
        f"{sorted(_keep_generic_overlap)}"
    )
# Matches "word, word, and word" / "word, word and word" (3 single-word items).
RULE_OF_THREE_PATTERN: re.Pattern[str] = re.compile(
    r"\b([A-Za-z][A-Za-z'-]+),\s+([A-Za-z][A-Za-z'-]+),?\s+and\s+([A-Za-z][A-Za-z'-]+)\b"
)
# How many of the 3 items must be in GENERIC_AI_ABSTRACT to flag (all 3 = strict).
RULE_OF_THREE_MIN_ABSTRACT: int = 3

# --- RHYTHM_UNIFORM (smooth uniform sentence run) ---
# Flags a run of K+ CONSECUTIVE sentences all in the AI "smooth band"
# (LOW..HIGH words) with low length variance. Hoi's rhythm is lumpy. Tightened
# after the first pass FP'd on legitimate 6-sentence runs: longer run (8),
# narrower band (18-25), lower variance ceiling (2.0). AI text produces much
# longer, much flatter runs than authentic Hoi ever does.
SENTENCE_SPLIT_PATTERN: re.Pattern[str] = re.compile(r"(?<=[.!?])\s+")
RHYTHM_UNIFORM_RUN: int = 8           # consecutive sentences
RHYTHM_UNIFORM_LOW: int = 18          # words (inclusive band lower bound)
RHYTHM_UNIFORM_HIGH: int = 25         # words (inclusive band upper bound)
RHYTHM_UNIFORM_MAX_STDEV: float = 2.0  # population stdev of the run's lengths


# ---------------------------------------------------------------------------
# Finding dataclass — used by all checkers
# ---------------------------------------------------------------------------
@dataclass(frozen=True, slots=True)
class Finding:
    file: str
    line: int
    type: str
    detail: str


__all__ = [
    "HOIBOY_CUTOFF_DATE",
    "MARKER_OPEN_HTML", "MARKER_CLOSE_HTML", "MARKER_EXEMPT_HTML",
    "MARKER_SKIP_OPEN_HTML", "MARKER_SKIP_CLOSE_HTML",
    "MARKER_OPEN_HASH", "MARKER_CLOSE_HASH", "MARKER_EXEMPT_HASH",
    "MARKER_SKIP_OPEN_HASH", "MARKER_SKIP_CLOSE_HASH",
    "EM_DASH", "SMART_QUOTE_CHARS", "UNICODE_ARROW_CHARS",
    "KEEP_LIST", "BANNED_WORDS", "BANNED_PHRASES",
    "BANNED_WORDS_PATTERN", "BANNED_PHRASES_PATTERN",
    "BOLD_BULLET_PATTERN", "NEGATION_PATTERN", "FRONTMATTER_DATE_PATTERN",
    "BOLD_BULLET_THRESHOLD_CV", "BOLD_BULLET_THRESHOLD_DEFAULT",
    # Structural AI-tell detectors (dotfiles#517 Phase E)
    "HTML_TAG_PATTERN", "URL_PATTERN", "MD_LINK_TARGET_PATTERN", "LIST_LINE_PATTERN",
    "NUMBER_TOKEN_PATTERN", "WORD_TOKEN_PATTERN",
    "NUMERIC_DENSITY_MIN_WORDS", "NUMERIC_DENSITY_MIN_NUMBERS", "NUMERIC_DENSITY_RATIO",
    "GENERIC_AI_ABSTRACT",
    "RULE_OF_THREE_PATTERN", "RULE_OF_THREE_MIN_ABSTRACT",
    "SENTENCE_SPLIT_PATTERN", "RHYTHM_UNIFORM_RUN",
    "RHYTHM_UNIFORM_LOW", "RHYTHM_UNIFORM_HIGH", "RHYTHM_UNIFORM_MAX_STDEV",
    "Finding",
]

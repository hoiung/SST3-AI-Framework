# Stage 4 — Source-of-Intent Verification (AP #28 worked examples)

> Cluster file loaded by `load-stage-rules.sh 4`. Verbose worked-example catalogue for
> ANTI-PATTERNS.md AP #28 "Acting on Appearance or Memory Rather Than Source of Intent".
> The canonical rule lives in ANTI-PATTERNS.md; this file holds the worked examples
> (Append-vs-Extend). dotfiles#516 AC 4.1.

## The three recurring instances

### 1. Propagation-managed "duplicate" files
A file that *looks* duplicated across repos is often propagation-managed (mirror lane B / template
lane A). **Before consolidating**, read `SST3/drift-manifest.json` and confirm whether the apparent
duplicate is a registered mirror. Worked example: the flattened `scripts/` copies in the dotfiles
self-row are byte-identical mirrors of `../../scripts/` canonicals — consolidating them would break the
drift gate. Source of intent = the manifest, not the file-listing.

### 2. Pointer vs predicate references
Before a bulk cross-repo rewrite of a reference (e.g. `STANDARDS.md:N` → anchor), classify EACH
occurrence: a **pointer** (a navigational link the reader follows) tolerates a section-anchor rewrite; a
**predicate** (a line-number the code/gate actually asserts against) does NOT — rewriting it silently
breaks the assertion. Read the consuming code before rewriting.

### 3. Reversing a documented deferral
Before reversing a previously-documented deferral ("we deferred X because Y"), retrieve the rationale
comment URL and confirm it still applies. Memory of "we should do X now" is a hypothesis; the recorded
rationale is the source of intent. If the rationale no longer holds, say so explicitly with evidence —
do not silently reverse.

## State-machine / persistence-schema companion rule (STANDARDS.md "Code Quality")

Any PR shipping state-machine / crash-recovery / idempotency / atomicity logic MUST include a
state-diagram-as-comment enumerating all reachable states and valid transitions in the same commit.
Schema fields representing 3+ states MUST be string enums at design time — never a bool-with-a-magic-
third-state. (Canonical rule: STANDARDS.md "Code Quality".)

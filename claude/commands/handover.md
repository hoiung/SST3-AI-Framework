# /handover — pre-compact AI-to-AI handover

Invoke this right before you compact a long session. It writes ONE structured handover that the **next** (post-compact) context will read to resume cleanly, with no information loss. The handover is **AI-to-AI**: the writer is this context, the reader is post-compact Claude — so it is terse, evidence-anchored, and optimised against drift, not written as human prose.

Optional argument: `/handover <one-line note>` — a free-text hint folded into the summary.

## Why this exists

Compaction drops the conversation and keeps only a summary. Anthropic's own compaction schema keeps **state + next-steps + learnings** and preserves the latest user turn **verbatim** — because paraphrasing the goal is where post-compact drift starts. This command writes that, plus evidence anchors, into the two channels the harness actually re-surfaces after a compact:

1. the auto-memory index (its top section is auto-loaded into every new session), and
2. the `SessionStart` compact hook, which re-injects the verbatim task from `/tmp/sst3-current-task.txt`.

A handover file with no auto-loaded index pointer is **orphaned** — the post-compact context never learns it exists. So both writes below are mandatory, not optional.

## What to do when invoked (in order)

**Step 1 — Write the handover topic file.**
Write a new file `HANDOVER_<repo-or-topic-slug>_<YYYY-MM-DD>.md` into **your auto-memory directory** — the directory given in this session's auto-memory system reminder (do NOT hardcode an absolute path; use the path the harness provided this session). Give it this frontmatter, matching existing handover topic files:

```yaml
---
name: handover-<slug>-<date>
description: <one-line what-this-is>
metadata:
  node_type: memory
  type: project
  originSessionId: <this session id if known, else omit>
---
```

Then the body, using these **8 field labels VERBATIM** (this is the authoring contract — do not rename, do not drop):

1. `GOAL (verbatim)` — the operator's goal quoted word-for-word. Do NOT paraphrase. This is the single most important field; paraphrasing it is the #1 source of post-compact drift.
2. `STATE` — what is DONE vs IN-PROGRESS, each line carrying an evidence anchor (commit SHA / test count / file:line). Not "auth is mostly done" — "auth login flow done (commit a1b2c3d, 7/7 tests pass); refresh-token path IN-PROGRESS (src/auth.py:88)".
3. `NEXT ACTION` — the single concrete next step the reader should take first. One step, not a backlog.
4. `ANCHORS` — the real file:line / artifact paths the reader must re-open to continue. Pointers to source, so the reader verifies rather than trusts the summary.
5. `DECISIONS` — decisions already made, each with its rationale AND what was RULED OUT (so the reader does not re-litigate or undo them).
6. `CONSTRAINTS` — hard rules in force this session ("don't touch X", required format, branch safety) that would otherwise be lost with the conversation.
7. `OPEN` — open questions / blockers genuinely undecided (so the reader knows what is settled vs not).
8. `LEARNINGS` — gotchas discovered this session (e.g. "endpoint is side-effecting — use --head", "test harness needs RTH ticks"). Cheap to record, expensive to rediscover.

**Step 2 — Add the auto-loaded index pointer (loop-closure — do NOT skip).**
Add ONE line under the `## ⭐ Active / in-flight` section at the TOP of `MEMORY.md` (your auto-memory index), of the form:
`- [<≤180-char summary, lead with ⭐ and the repo/issue + resume verb>](HANDOVER_<slug>_<date>.md)`
Only this top section is auto-loaded into the next session (the index is truncated at session start, ~line 200) — the topic-file body is NOT auto-loaded. The bullet is what tells post-compact Claude the handover exists and where to read it. If a bullet already exists for this same work, UPDATE it in place rather than adding a duplicate.

**Index hygiene (MEMORY.md is large and the top is the only part that auto-loads).** Keep `## ⭐ Active / in-flight` **lean**. If `MEMORY.md` exceeds ~200 lines, in the SAME edit **demote** the oldest **closed / superseded** handover bullet down to the `## Recent audit-trail (closed work…)` section (or remove it), so adding a live entry never silently pushes another live entry past the ~200-line truncation boundary into the part that never loads.

**Step 3 — Update the compact-hook task file (deterministic re-surface).**
Write to `/tmp/sst3-current-task.txt` (the file the `SessionStart` compact hook reads and re-injects after a compact) the verbatim current task PLUS an explicit imperative — NOT a bare path — so the post-compact context is commanded to open the handover:

```text
<verbatim operator goal>
Post-compact: READ <full path to the HANDOVER_*.md file> IN FULL before resuming — it holds the goal/state/next-action.
```

The hook re-surfaces this text and a fixed "re-read CLAUDE.md/STANDARDS/ANTI-PATTERNS/WORKFLOW/Issue" directive, but it does NOT itself read the handover body — so the imperative above is what closes the loop.

**Step 4 — Report and confirm.**
Tell the operator: the handover file path, the index bullet you added (or updated), the task-file line, and a one-line "safe to compact now". Then stop — let the operator trigger the compact.

## Anti-patterns — do NOT do these

- **No prose-narrative summary.** A paragraph retelling the session strips the reasoning chain and is unverifiable. Use the 8 structured fields.
- **Not a raw-history dump.** Dumping everything adds noise and buries the signal (lost-in-the-middle). Write the high-leverage fields only.
- **Do not paraphrase the operator goal.** Quote it verbatim in field 1 — paraphrase is where drift begins.
- **Never drop the file:line anchors.** Anchors let the reader re-read source instead of trusting a summary; dropping them is the direct cause of post-compact hallucination.

## Relationship to the Issue-comment handover

For Issue-tied SST3 work, the canonical session checkpoint still goes to the GitHub Issue comment per `templates/chat-handover.md`. `/handover` complements that — it is the memory-channel handover for any pre-compact moment (Issue or not). Use both when on an active Issue.

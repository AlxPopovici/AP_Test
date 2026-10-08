# The interview

The questions the code cannot answer. Ask these in **batches**, each question carrying your
inference so the developer confirms or corrects instead of composing prose from nothing.

**Two standing rules:**

- **Never invent an answer.** Anything unresolved goes under **Open questions**, verbatim as a
  question. That section is a CI gate — it must be empty before the `master` PR merges — so an
  open question is a tracked debt, not a gap. A plausible invention is worse than a blank.
- **Don't ask what the code already says.** Deriving first and confirming second is the
  difference between a two-minute exchange and an interrogation. See
  [deriving-from-code.md](deriving-from-code.md).

---

## Batch 1 — Purpose and ownership

Everything here is required, and none of it is in the code.

1. **Why does this DAG exist?** Not what it does — the code says that. Who consumes the output
   and what decision does it feed? This becomes the second half of the elevator pitch.
2. **Who is the Reviewer?** Explicitly *"who signed off the guarantees, not who wrote the DAG"*.
   The `owner` in `default_args` is the author; it is not this field. If nobody has reviewed the
   guarantees yet, that is an Open question, not a name.
3. **Criticality** — `standard`, `on-duty documented`, or `on-call critical`? Default to
   `standard` and make them argue upward; see
   [criticality-and-rotations.md](criticality-and-rotations.md) for what each tier costs in
   required sections.
4. **Does it feed a critical pipeline?** Bring your DataHub hop chain and ask them to confirm it
   reaches (or doesn't reach) Daily Summaries or CRM. This is the single most valuable field in
   the template — see SKILL.md Step 4.

## Batch 2 — Guarantees

Lead each with the inference.

5. **Grain** — *"The MERGE keys say one row per X per day. Correct?"* If the code shows no
   deduplication, confirm the raw shape is intentional.
6. **Freshness** — *"What does a consumer get, and when?"* Push for a **relative** statement:
   "D-1 available same morning", "within 2h of upstream landing". If they answer with a clock
   time, ask what it is relative to — the cron is excluded precisely because it changes outside
   git.
7. **Idempotent** — confirm the write-mode inference. If they say yes but the write mode is
   `COPY INTO ... FORCE = TRUE` or a bare `INSERT`, that is a contradiction to resolve now, not
   to paper over.
8. **Late data** — *"A record arrives three days late. What happens to it?"* The honest answer
   is often "nothing, it's lost", and **"explicitly not handled" is a valid, useful answer** —
   far better than silence. A rolling-window reload handles it for free; say so.
9. **Markets, and which are deliberately excluded.** Code shows what runs; only the developer
   knows what was decided against.

## Batch 3 — Runbook

Required for new and changed DAGs, and for anything above `standard` criticality regardless of
age. Bring your list of code smells from `deriving-from-code.md` as the starting point.

10. **Safe to rerun?** Distinguish the two cases explicitly: rerunning a *failed* run, versus
    clearing and rerunning a run that already *succeeded*. They differ whenever the write is an
    append.
11. **Safe to trigger ad-hoc?** A separate question — *"can I fire this off-schedule right now
    for a logic change or a test run, or only on the schedule / after a clear?"* Then the
    catch-up half: *"if three runs fail and the fourth succeeds, is the missed data covered, or
    does each failed run need clearing?"* Neither is derivable from code, and both are what an
    on-call person actually needs at 22:00.
12. **What has actually broken before, and what fixed it?** Two or three modes. Real history
    beats speculation — check the DAG's incident history if they can't recall.
13. **Backfill** — confirm the mechanics you derived (`catchup`, `start_date`, windowing) and ask
    whether a backfill is *safe*, which is a different question from whether it *runs*. If a
    downstream merge dedupes, an append-mode backfill can still be safe; that's worth recording.

## Batch 4 — Design decisions and the rest

14. **Any decision here that would surprise a reader?** Mine the code's inline comments first —
    a comment like `FORCE=TRUE (guaranteed duplicates on rerun)` is a design decision already
    written down. Ask for the *reason*, and a Jira or Notion link if one exists.
15. **Non-goals** — *"What does this DAG deliberately not do, and where does that live instead?"*
    This is what stops the next person re-implementing something on purpose left out.
16. **Anything you know is wrong or unfinished?** Straight into Open questions.

---

## Mode-specific additions

**Mode A (migrated DAG).** The inline `doc_md` is your best raw material — harvest it before
asking anything. It usually covers purpose and often the design decisions. Then ask only what
it doesn't cover. Also worth asking: *"is anything in the old doc now untrue after the Airflow 3
conversion?"* — migrated prose frequently describes the pre-migration behaviour.

**Mode B (new DAG, doc-first).** The interview *is* the design conversation, so go deeper: the
answers become the spec that the implementation and its tests are written against. Each
Guarantees claim should have something that will prove it — a uniqueness test for grain, a
run-twice test for idempotency, a DataHub FRESHNESS assertion for freshness. Leave the README
at `Status: draft` and commit it alone.

**Mode C (update on change).** Don't re-interview everything. Read the diff, work out which
guarantees it touches, and ask only about those. Then:

- *"Does this change any guarantee?"* → decides MAJOR vs MINOR vs PATCH
  ([versioning.md](versioning.md)).
- *"Do the Inputs and Outputs tables still match the SQL?"* → the one review-checklist item that
  catches hand-written drift.
- If Open questions is non-empty, ask whether this change closes any of them.

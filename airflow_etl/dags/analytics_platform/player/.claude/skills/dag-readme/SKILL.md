---
name: dag-readme
description: Author, update, or audit a per-DAG README.md against the Player Data Squad DAG README standard (DPW-1835) — the Ownership / Guarantees / Inputs / Outputs / Runbook / Version sections plus the criticality-gated On-duty and On-call links. Derives inputs, outputs and write mode from the DAG file and sql/, interviews the developer for what code cannot supply (grain, freshness, idempotency, late data, criticality, runbook), wires doc_md to read the README, and version-bumps on change. Use when asked to "write the README for <DAG>", "document this DAG", "add a DAG README", "update the README for <DAG>", "the pipeline changed, update its docs", "does this README meet the standard", or when a player DAG has no README.md or still carries an inline doc_md string. Player Data Squad standard — apply to other squads' DAGs only on request.
---

# DAG README

**Write the README that makes a DAG trustworthy without opening its code.**

The Airflow 3 migration moves DAG documentation out of inline `doc_md` and into a per-DAG
`README.md`. The data tooling team's CI enforces that the file **exists**; it says nothing
about what goes in it. This skill owns that middle layer — the file saying something useful.

Standard: DPW-1835. Reference implementation:
`airflow_etl/dags/analytics_platform/player/profile/ing-cis-s3-snowflake/README.md`.

**Scope.** Player Data Squad DAGs under `airflow_etl/dags/analytics_platform/player/`. The
standard is a squad standard, not a platform one — applying it to another squad's DAG is fine
if asked, but don't volunteer it.

**Deliberately narrow.** The flow is: read the code → interview → write README → wire `doc_md`
→ hand back. It does **not** run pre-commit, commit, or open PRs. Those are explicit steps the
developer runs when ready (`/run-pre-commit`, `/commit-push-pr`).

---

## The two governing rules

Every judgment call in this skill resolves to one of these. Quote them when a developer wants
to add a field.

1. **If a field can change without a commit, it does not belong in the README.**
   This is why the cron, the alert routing target and the schedule are excluded — someone edits
   them outside git and the README silently becomes a lie.
2. **Anything identical across DAGs goes up a level, not into the template.**
   This is why On-duty and On-call are links rather than content. Restating a shared procedure
   across 84 DAGs produces 84 copies that drift from the live one.

---

## Three modes

Establish which one you're in before writing anything — they differ in where the content comes
from and what the Version block says.

| Mode | Trigger | Content source | Version / Status |
| --- | --- | --- | --- |
| **A — Migrated DAG** | DAG just came in from `data.airflow.dags`; has an inline `doc_md` string | Existing `doc_md` prose + code + interview | `2.0.0`, `Status: draft`, change = "Airflow 3 migration" |
| **B — New DAG (doc-first)** | Brand-new pipeline, no code yet or code being written now | Interview only — the README **is** the spec | `1.0.0`, `Status: draft` |
| **C — Update on change** | `dag.py` or `sql/` changed; README exists | The diff + targeted re-interview | Bump per [references/versioning.md](references/versioning.md) |

**Mode B is doc-first and belongs in plan mode.** Plan mode is a read-only permission boundary,
so the planning output has nowhere to go but a document. Explore neighbouring DAGs, interview,
then **approve only the README** — it is the first and only write. Implement in a fresh session
from the README, and review the final diff against it. Skip doc-first when the change fits in
one sentence (a one-line SQL tweak); it is for new DAGs and behaviour changes.

---

## Step 1 — Locate the DAG and read everything

```bash
DAG=airflow_etl/dags/analytics_platform/player/<sub-area>/<dag-name>
ls "$DAG" "$DAG/sql" 2>/dev/null
```

Read, in this order: the DAG `.py`, every file in `sql/`, the DAG's own `config.yaml`, then the
inherited `config.yaml` files up the tree (`player/`, `analytics_platform/`, `dags/`). Read the
`_test.py` too — it often names the expected task count and structure.

Do not skim. The Inputs and Outputs tables are only as good as your read of the SQL, and they
are the sections that carry the most weight (see Step 2).

## Step 2 — Derive what the code already knows

Fill these in yourself, then confirm the inferred ones with the developer rather than asking
cold. Full heuristics — SQL write-mode patterns, grain from `MERGE ... ON`, market detection,
backfill safety, failure-mode code smells — are in
[references/deriving-from-code.md](references/deriving-from-code.md).

| README field | Derive from |
| --- | --- |
| Title, cadence | `dag_id`, `schedule` → **words, never the cron** |
| Domain | Sub-area folder → confirm against the four real DataHub Player domains |
| Markets covered | `markets:` tag, SQL `DOMAIN_ID` filters, per-market task expansion |
| Inputs | `FROM` / `JOIN` in `sql/`, API source classes, KPO source config |
| Outputs + write mode | `MERGE INTO` / `INSERT OVERWRITE` / `COPY INTO` / `CREATE OR REPLACE` |
| Grain (draft) | `MERGE ... ON` keys, final `GROUP BY`, `QUALIFY ROW_NUMBER() PARTITION BY` |
| Idempotent (draft) | The write mode — `MERGE` yes, `COPY INTO ... FORCE = TRUE` no |
| Alert resolves | `IncidentIOConfig(notification_level=...)` — `dag` and `task` auto-resolve, `run` does not |
| Backfill (draft) | `catchup`, `start_date`, and whether SQL windows on `data_interval_start` |
| Common failures | `ON_ERROR`, `TRUNCATECOLUMNS`, missing HTTP timeouts, retries |

**Why Inputs and Outputs are required, not nice-to-have.** There are **zero Airflow entities in
DataHub** — `platform = airflow` returns nothing. The README is the only place a DAG-to-table
mapping exists in queryable form. It is also the missing hop on the on-call path: an assertion
fires naming a *table*, and reaching the runbook needs table → DAG → README. The Outputs table
is what supplies that hop. Hand-written tables will drift from the SQL; that is an accepted
tradeoff, mitigated by the Version coupling (a new source is a MINOR bump).

**Use DataHub for downstream consumers and the critical-pipeline check** — `search` for the
output table, then `get_lineage` on the URN it returns. Lineage stops at the table boundary
(no Airflow entities), so you get tables, not DAGs. Keep the consumer list short and label it
informational; it is a fact about *other people's* DAGs and goes stale on its own.

## Step 3 — Interview for what code cannot tell you

The interview is the point of this skill. Grain, freshness intent, late-data handling,
criticality and real failure modes are not in the code, and inventing them produces confident
fiction — the exact failure the standard exists to prevent.

**Ask in batches, not one question at a time.** Lead with your inference so the developer
confirms or corrects rather than composing from scratch: *"The MERGE keys say the grain is one
row per PLAYER_BONUS_ID per day — right?"*

The batched question set, with the reasoning behind each, is in
[references/interview-questions.md](references/interview-questions.md).

**Anything unanswered goes under Open questions — never guessed.** An honest open question is
worth more than a plausible invention, and the section is a CI gate: it must be empty before
the PR to `master` merges.

## Step 4 — Write the README

Copy [assets/README_template.md](assets/README_template.md) to `$DAG/README.md` and fill it in.
Per-section rules, phrasing constraints and the full exclusion list are in
[references/section-rules.md](references/section-rules.md). The three that get violated most:

- **Freshness must be relative, not an absolute clock time.** "D-1 available same morning"
  survives someone changing the cron in the Airflow UI. "Available by 06:00 CET" does not.
- **Fully qualified `SCHEMA.TABLE`, always**, in both tables. This makes a later transform to a
  DataHub URN mechanical.
- **`Platform` column on Inputs**, because inputs are not all Snowflake — a raw Betler Kafka
  topic or an HTTP API belongs in that table too.

**Delete the On-duty and On-call sections unless criticality earns them.** `standard` gets
Runbook only, and that covers nearly every DAG in the estate: only **two pipelines are on-call
critical platform-wide** (Daily Summaries and CRM), and the on-call page states that fixing
non-critical pipelines is optional. See
[references/criticality-and-rotations.md](references/criticality-and-rotations.md) for the
ladder, the two rotations and their real hours.

**`Feeds a critical pipeline?` is the load-bearing field.** The non-critical rule carries one
exception — *unless it blocks a downstream critical job* — and that is precisely what an on-call
person cannot determine at 22:00. Trace the hops in DataHub, name them, and say whether the
chain reaches Daily Summaries or CRM. This field converts an optional fix into a mandatory one.

## Step 5 — Run the consistency check

Two facts in the README are logically coupled to code, and nothing else catches a mismatch.
Report either as a finding — do not silently "fix" the DAG.

1. **Idempotency vs notification level.** Auto-resolve suits idempotent pipelines, where a
   successful run fixes the previous failure. A DAG whose Guarantees say `Idempotent: no` but
   which sets `IncidentIOConfig(notification_level="dag")` **or `"task"`** is **misconfigured** —
   the alert auto-resolves on the next success while duplicate or missing rows are still sitting
   in the table. **Non-idempotent pipelines want `run`**, which is the only level whose alert a
   later run cannot close. See
   [references/deriving-from-code.md](references/deriving-from-code.md#alert-resolution) — `task`
   auto-resolves too, just scoped to the task, so it is not the safe choice it looks like.
2. **Write mode vs the Idempotent claim.** `COPY INTO ... FORCE = TRUE`, or a bare
   `INSERT INTO` with no preceding delete of the window, cannot back an `Idempotent: yes`
   claim. If both appear, one of them is wrong.

## Step 6 — Wire `doc_md` to the README

One source of truth: the README renders in the Airflow UI, and the inline string goes away.
Match the pattern already in `ing-cis-s3-snowflake`:

```python
from pathlib import Path

doc_md_DAG = Path(__file__).parent.joinpath("README.md").read_text()

with DAG(
    ...
    doc_md=doc_md_DAG,
) as dag:
```

Delete the inline `doc_md_DAG = """..."""` block (Mode A) or the `__doc__` assignment, after
harvesting its prose into the README — that text is usually the best available raw material for
the elevator pitch, Design decisions and Common failures. Do not leave both: a surviving inline
string is a second copy that drifts.

> **Note the standing repo convention differs.** `airflow_etl/CLAUDE.md` (*DAG documentation*)
> still says to use a module docstring with `doc_md=__doc__`, and
> `.claude/skills/create-pipeline/assets/pipeline_template.py` still scaffolds that way. The
> README-import pattern is what DPW-1835 specifies and what the merged `ing-cis-s3-snowflake`
> does. Follow the README pattern here, and flag the divergence — reconciling
> `airflow_etl/CLAUDE.md` is a separate PR to the data tooling team's guidance, not something
> this skill should change silently.

## Step 7 — Gate on completeness, then hand back

**Required** — a README missing any of these is not done: title and one-liner with cadence,
Ownership, Guarantees, Inputs, Outputs, Version.

**Optional but expected** — Runbook, Design decisions, Open questions. Runbook and Design
decisions are the highest-value sections but cannot be honestly backfilled by someone who did
not write the DAG; mandating them on legacy DAGs produces fiction. They are **required for new
and changed DAGs, expected on legacy DAGs as they get touched** — with one exception: **any DAG
above `standard` criticality requires a Runbook regardless of age.** A DAG that pages someone
and has no runbook is the specific failure these sections exist to prevent.

Then report back, and stop:

- the README path, its mode, and the version/status it landed on
- which fields you **inferred** rather than were told — these need the developer's eye
- anything left under **Open questions**, called out as blocking the `master` PR
- any Step 5 consistency finding
- next steps: `/run-pre-commit`, then `/commit-push-pr`

**Landing it:** one feature branch, **two PRs — `stage` first, then `master`** (see
`airflow_etl/CLAUDE.md`, *Git workflow*). A README under `airflow_etl/` is inside the
CodeCommit-mirrored tree, so a master-only PR trips Super AI's stage-parity check. Never
auto-merge — merging is a deploy.

---

## What never goes in

Six exclusions, each with a named owner elsewhere. This list is what keeps the template
maintainable instead of becoming one more stale doc — reach for it whenever someone proposes an
addition.

| Excluded | Why | Owner instead |
| --- | --- | --- |
| Exact schedule / cron | Editable outside git, so it rots. Cadence in the one-liner is the right resolution | Airflow |
| Alert routing target | Would create a second place to update | incident.io |
| Task-by-task walkthrough | Rots on every refactor | Airflow graph view |
| Column-level schema | Already modelled, with history | DataHub |
| Full commit changelog | The Version table is capped at five rows for this reason | Git history + Airflow 3 DAG versioning |
| SQL explanation | Belongs next to the SQL | `sql/` |

Also out: **"can it wait until morning"** (answered globally by criticality, not per DAG),
**blast radius** (recorded per critical pipeline on the on-call page), and **per-assertion
runbook entries** (the DataHub routing-tag convention is essentially unadopted — 3 uses of
`trigger_incidentio` across 756 assertions — so don't build on it yet).

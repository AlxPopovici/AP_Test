# Section rules

Per-section constraints, and the reasoning behind each — quote the reasoning when a developer
pushes back, because most of these look arbitrary without it.

Both governing rules from SKILL.md apply throughout:

1. If a field can change without a commit, it does not belong in the README.
2. Anything identical across DAGs goes up a level, not into the template.

---

## Title and elevator pitch

`# <dag_id>` — the literal `dag_id`, so a search for the failing DAG name lands here.

Two or three sentences: what it does, its **cadence in words**, and why it exists. Cadence at
word resolution ("daily", "hourly", "event-triggered") is deliberate — the exact cron is
editable in the Airflow UI without a commit, so restating it guarantees eventual drift. Cadence
survives that; a cron doesn't.

## Ownership

- **Squad** — `Player Data Squad`, fixed.
- **Domain** — one of the four real DataHub Player domains. See
  [deriving-from-code.md](deriving-from-code.md#domain).
- **Reviewer** — who signed off the *guarantees*. Not the author, and not `default_args["owner"]`.
  The distinction is the point: it names someone accountable for the claims being true.
- **Criticality** — `standard` / `on-duty documented` / `on-call critical`. This field is what
  makes the required-sections rule mechanical rather than a judgment call, and it is what a CI
  check would key off. See [criticality-and-rotations.md](criticality-and-rotations.md).
- **Feeds a critical pipeline?** — see SKILL.md Step 4. Name the hop chain, not just yes/no.

## Guarantees

Named **Guarantees**, not "Contract" — "contract" already means a Kafka schema contract in normal
conversation here, and those sit upstream of these DAGs.

The purpose of the section is that **a breaking change shows up as a diff in review**. That only
works if the fields are stated in a form that a reviewer can check against the SQL.

- **Grain** — `one row per <KEY> per <period>`.
- **Freshness** — **relative, never an absolute clock time.** "D-1 available same morning"
  survives a cron change in the UI; "available by 06:00 CET" becomes a lie the moment someone
  reschedules. If the honest answer is a clock time, anchor it to something in git.
- **Idempotent** — `yes, <how>` or `no, <why>`. Must agree with the Outputs write mode, and with
  the incident.io notification level (SKILL.md Step 5).
- **Late data** — handled how, or **explicitly not handled**. The explicit negative is a real
  answer and more useful than omission.
- **Markets covered** — plus which are deliberately excluded.

## Inputs and Outputs

Required from day one, hand-written. The rationale for "required" rather than "nice-to-have" is
in SKILL.md Step 2 — zero Airflow entities in DataHub, so this is the only queryable DAG-to-table
mapping, and the missing hop on the on-call path.

- **Fully qualified `SCHEMA.TABLE`, always.** Makes a later transform to a DataHub URN mechanical.
- **`Platform` column on Inputs**, because inputs are not all Snowflake — a Kafka topic, an HTTP
  API or an external MSSQL server all belong in that table.
- **`Write mode` on Outputs**, because it is what makes the Idempotent guarantee checkable.
- **Known downstream consumers** is *informational and never required.* Inputs and outputs are
  facts about **this** DAG; downstream consumers are facts about **other people's** DAGs, so the
  list goes stale whenever someone else builds something. Label it informational, keep it short,
  and never let it block. If every DAG declares its inputs, the downstream graph is derivable
  anyway.

**Accepted tradeoff:** hand-written tables drift from the SQL. Mitigated by the Mode C review
question and the Version coupling — a new source is a MINOR bump, so it leaves a visible mark.
Automating these tables from task-level `inlets`/`outlets` is the top follow-up in DPW-1835, not
part of this standard.

## Runbook

Written for someone paged at 22:00 who has never seen this DAG. Four fields:

- **Safe to rerun?** — and the failed-run vs succeeded-run distinction if they differ.
- **Alert resolves** — automatically, or manually and must be closed in incident.io. Record the
  *action*, never the routing target (routing lives in incident.io and would become a second
  place to update). This matters because an open alert suppresses new alerts sharing its
  deduplication key, so a forgotten manual close is an active blind spot.
- **Common failures** — two or three known modes and the fix.
- **Safe to trigger ad-hoc?** — a *different* question from "safe to rerun", which is about a run
  that already failed. This one is about firing the DAG off-schedule for a logic change or a test
  run: can someone do that at any time, or only on the schedule / after a clear? Pair it with the
  catch-up question — if several runs fail and one then succeeds, does that success cover the
  missed intervals, or must each failed run be cleared individually? Both are on the platform's
  own list of what on-call should learn from a DAG's docs (`airflow_etl/CLAUDE.md`, *DAG
  documentation*), and neither is answerable from the code alone.

**Backfill** — a command, a link, or an honest "not supported". Include the constraint that
bites: `catchup=False`, the `start_date` floor, and whether the SQL windows on
`data_interval_start` or on `CURRENT_DATE`.

## On-duty and On-call

**Delete both sections unless criticality earns them**, and when kept, **link — do not restate.**

The on-duty and on-call pages already hold per-pipeline documentation, known issues, DAGs and
scripts, and DQ checks. Restating any of it across 84 DAGs produces 84 copies that drift from the
live procedure. For the ordinary DAG the generic flows already *are* the procedure, so per-DAG
content would be pure duplication.

## Design decisions

One line per decision, each with its **reason**, and a Jira or Notion link where one exists. Mine
the code's inline comments first — they are often design decisions already written down, just in
the wrong place.

**Non-goals** belongs here: what this DAG deliberately does not do, and where that lives instead.
It is what stops the next person re-implementing something intentionally left out.

## Open questions

**Must be empty before the PR to `master` merges** — a deterministic CI gate.

Write them as questions, with enough context to be actionable by someone else. When empty, say
so explicitly (`_None._`) rather than deleting the heading, so the reader can tell the section
was considered rather than dropped.

## Version

At the **bottom**, deliberately: it is the least-read and most-appended section, so it belongs
where growth does no damage.

Rules, bump semantics and the five-row cap are in [versioning.md](versioning.md).

---

## The exclusion list

The most important part of the standard. Six things kept out, each with a named owner elsewhere —
this is what makes the template maintainable rather than one more doc that goes stale.

| Excluded | Why | Owner instead |
| --- | --- | --- |
| Exact schedule / cron | Editable outside git, so it rots | Airflow |
| Alert routing target | Would create a second place to update | incident.io |
| Task-by-task walkthrough | Rots on every refactor | Airflow graph view |
| Column-level schema | Already modelled, with history | DataHub |
| Full commit changelog | Version table is capped for this reason | Git history + Airflow 3 DAG versioning |
| SQL explanation | Belongs next to the SQL | `sql/` |

Three more fields that look useful and are deliberately absent:

- **"Can it wait until morning?"** — answered globally by criticality, not per DAG. Non-critical
  means optional, and Monday is fine.
- **Blast radius** — already recorded per critical pipeline on the on-call page.
- **Per-assertion runbook entries** — the DataHub routing-tag convention is essentially
  unadopted (`trigger_incidentio` appears on 3 of 756 assertions). Either most alerting is
  configured outside DataHub tags or the convention is new; the data can't distinguish those, so
  don't build on it yet.

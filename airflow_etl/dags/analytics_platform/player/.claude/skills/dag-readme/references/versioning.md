# The Version section

The Version block tracks **guarantees**, not code. Its purpose is visibility: a migration or a
source switch should leave a visible mark against the DAG, and today nothing does that.

```markdown
## Version
**2.1.0** | **Status:** active | **Last reviewed:** 2026-09-02

| Version | Date | Change | Ref |
| --- | --- | --- | --- |
| 2.1.0 | 2026-09-01 | NG_RO remapped to identity_id | DPW-1471 |
| 2.0.0 | 2026-08-15 | Airflow 3 migration, KPO executor | DPW-1658 |
| 1.3.0 | 2026-06-02 | SB_PL source switched to Betler | DPW-1722 |
```

---

## Bump rules

| Bump | When |
| --- | --- |
| **MAJOR** | A guarantee changes — grain, schema break, freshness moved, market removed |
| **MINOR** | Additive — new market or column, new source, migration completed |
| **PATCH** | Bug fix, guarantees unchanged |

The deciding question in Mode C is always *"does this change a guarantee?"* If yes, MAJOR. If it
adds without changing what a consumer could already rely on, MINOR. If a consumer would notice
nothing except that a wrong number became right, PATCH.

**Do not log** refactors, SQL formatting, or config tweaks. Git history already covers those, and
a Version table that records them stops being read.

**Cap the table at five rows.** Older entries live in git history. A twenty-row table is a
changelog — explicitly excluded by the standard — and nobody reads it.

## Status

One of `draft`, `active`, `deprecated`.

- **`draft`** — supports the doc-first workflow. A Mode B README is committed alone at `draft`
  before any implementation exists; a Mode A migration README stays `draft` until the DAG has
  soaked on stage and someone has reviewed the guarantees.
- **`active`** — guarantees reviewed and believed true. Promote to `active` when the Reviewer
  field names a real person who has actually signed off, and Open questions is empty.
- **`deprecated`** — gives the retirement path a handle, which nothing else currently provides.
  Note that a retirement *process* doesn't exist yet; this field is a start, not the process.

## Last reviewed

The date a human last checked the guarantees are still true — **not** the date the file last
changed. Git gives you the latter for free. If you are editing the README without re-checking
the guarantees, leave this date alone.

## Starting values by mode

| Mode | Version | Status | First row's Change |
| --- | --- | --- | --- |
| **A** — migrated DAG | `2.0.0` | `draft` | "Airflow 3 migration from data.airflow.dags" |
| **B** — new DAG | `1.0.0` | `draft` | "Initial README (doc-first)" |
| **C** — update | bump per the table above | usually unchanged | the actual change, one line |

Mode A starts at `2.0.0` because the Airflow 3 migration is itself the MAJOR event — the DAG's
pre-migration life is version 1.x even though no README recorded it. Keep the `Ref` column
pointing at the migration epic (DPW-1658) so the mark is traceable.

---

## Why this coexists with Airflow 3 DAG versioning

**Airflow 3 has native DAG versioning, which tracks code. This tracks guarantees.** They will
diverge, and that is correct: a pure refactor bumps Airflow's version and not this one; a
freshness change that touches only a cron bumps this one and not Airflow's.

State this if anyone reports the mismatch as a bug — it is the intended behaviour, not drift.

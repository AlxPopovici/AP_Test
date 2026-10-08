# Criticality and the two rotations

`Criticality` decides which sections a README must carry. It is the field that makes the
required-sections rule mechanical instead of a judgment call, and the one a CI check would key
off — so it needs to be set honestly, not defensively.

**Default to `standard` and make the case for anything higher.** Nearly all 84 Player DAGs are
`standard`.

---

## The ladder

| Criticality | Sections required | Expected count |
| --- | --- | --- |
| `standard` | Runbook only | Nearly all 84 |
| `on-duty documented` | Runbook + **On-duty** link | A handful |
| `on-call critical` | Runbook + **On-duty** + **On-call** links | Daily Summary DAGs only |

Delete the On-duty and On-call headings entirely at tiers that don't require them. An empty
section invites someone to fill it with a copy of the shared procedure, which is exactly what
governing rule 2 forbids.

**One exception to the "expected on legacy DAGs" leniency:** any DAG above `standard`
**requires** a Runbook regardless of age. A DAG that pages someone and has no runbook is the
specific failure these sections exist to prevent — and since only two pipelines are on-call
critical estate-wide, that is a small and enforceable set.

---

## Two rotations, different hours and scopes

Conflating these was the original drafting mistake in DPW-1835. They are separate teams covering
different hours with different obligations.

| | Team on-duty | Platform on-call |
| --- | --- | --- |
| **Team** | Player Data Squad | Analytics Platform |
| **Hours** | One of three CET shifts: 07:00–15:00, 08:00–16:00, or 09:00–17:00 | Weekdays 07:00–09:00 and 17:00–23:00 CET; weekends and holidays 07:00–23:00 |
| **Scope** | All Airflow errors, Acryl DQ, data contracts, external source gaps, `#data-support` triage | Two critical pipelines only |
| **Non-critical failures** | In scope | **Optional** — can wait until Monday unless it blocks a downstream critical job |
| **Escalation** | Domain specialists | 10 min no ack → reminder; 30 min → whole rotation; critical unresolved → phone the EM/IC |
| **Response target** | 1 hour on `#data-support` | Under 30 minutes |

### Why most DAGs need only a Runbook

Only **two pipelines are on-call critical across the entire Analytics Platform area**:

| Pipeline | Priority | Critical period |
| --- | --- | --- |
| Daily summaries | P1 | 05:10–06:20 UTC |
| CRM pipelines | P1 | 05:50–09:30 UTC |

Everything else is explicitly non-critical, and the on-call page states that fixing non-critical
pipelines is **optional**. The on-duty page is structured the same way: it documents the most
critical pipelines and those with repeatable problems individually, then handles everything else
through a generic Airflow flow — acknowledge with 👀, copy the error and root cause, fix, run DQ
checks, close the alert.

So for the ordinary DAG **the generic flows already are the procedure.** Per-DAG on-duty or
on-call content would be duplication that drifts from the live page.

For the Player squad, `on-call critical` covers the Daily Summary DAGs and essentially nothing
else.

### The one exception that makes `Feeds a critical pipeline?` load-bearing

The non-critical rule carries a single carve-out: *optional **unless it blocks a downstream
critical job***.

That is precisely what an on-call person cannot determine at 22:00. They have a failing DAG name
and no way to reach Daily Summaries from it: there are **no Airflow entities in DataHub**, so
lineage can't answer "which DAG writes this", and the Outputs table shows only one hop.

`Feeds a critical pipeline?` is per-DAG knowledge available nowhere else, and it converts an
optional 22:00 fix into a mandatory one. Fill it by tracing hops in DataHub and naming the chain
— *"yes → `X` → `Y` → Daily Summaries"* — rather than answering bare yes/no. If the chain depends
on schedule timing rather than a real dependency (a common shape here: two DAGs an hour apart
with no sensor between them), say that too; it changes what the on-call person should do.

### A shift-dependent coverage gap

Platform on-call starts at 17:00, so whether there is a gap depends on which on-duty shift is
running that day:

| On-duty shift | Uncovered window |
| --- | --- |
| 09:00–17:00 | **None** — on-duty hands off exactly as on-call starts |
| 08:00–16:00 | 16:00–17:00 |
| 07:00–15:00 | 15:00–17:00 |

So the gap is a property of the roster, not a permanent hole. A DAG failing inside one has no
owner until the next morning. Worth knowing when someone argues a DAG is safe at `standard` —
but don't state it in a README as a standing fact, because it changes with the shift.

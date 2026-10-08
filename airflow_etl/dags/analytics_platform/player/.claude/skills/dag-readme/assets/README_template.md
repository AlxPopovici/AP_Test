# <dag_id>

<Elevator pitch: what this DAG does, its cadence (daily / hourly / event-triggered), and why it
exists. Two or three sentences. State the cadence in words — never restate the cron.>

## Ownership
- **Squad:** Player Data Squad
- **Domain:** <one of the four DataHub Player domains — see references/deriving-from-code.md#domain>
- **Reviewer:** <who signed off the guarantees, not who wrote the DAG>
- **Criticality:** <standard | on-duty documented | on-call critical>
- **Feeds a critical pipeline?** <no | yes, Daily Summaries | yes, CRM — plus the hop chain>

## Guarantees
- **Grain:** one row per <KEY> per <period>
- **Freshness:** <D-1 available same morning | within Nh of upstream landing>
- **Idempotent:** <yes, full partition reload | no, and why>
- **Late data:** <handled how, or explicitly not handled>
- **Markets covered:** <SB_RO, SB_PL, NG_BE ... and which are deliberately excluded>

## Inputs

| Table | Platform | Notes |
| --- | --- | --- |
| `DWH.F_PLAYER_BONUS` | snowflake | driver, per PLAYER_BONUS_ID |
| `DWH.D_BONUS` | snowflake | dimension lookup |

## Outputs

| Table | Platform | Write mode |
| --- | --- | --- |
| `DM_PLAYER.F_PLAYER_BONUS_COST` | snowflake | full partition reload |

**Known downstream consumers:** informational, not exhaustive.
- `DM_PLAYER.F_PLAYER_BONUS_COST_SPLIT_DAILY`

## Runbook

**If the DAG failed**
- Safe to rerun? <yes | no, and why>
- Alert resolves: <automatically | manually, must be closed in incident.io>
- Common failures: <2 to 3 known modes and the fix>

**Safe to trigger ad-hoc?**
- <yes, any time | only on schedule / after a clear — and why not>
- <If several runs fail and then one succeeds: does that success cover the missed intervals, or must each failed run be cleared?>

**Backfill**
- <command, or link, or "not supported">

## On-duty
<!-- Keep this section ONLY if Criticality is `on-duty documented` or higher. Link, do not restate. -->
- **On-duty page section:** <link to the relevant toggle>
- **DQ verification after a fix:** <what to run, or link>

## On-call
<!-- Keep this section ONLY if Criticality is `on-call critical`. Link, do not restate. -->
- **On-call page entry:** <link to the critical pipeline table>
- **Critical period:** <e.g. 05:10 to 06:20 UTC>

## Design decisions
- <Decision, one line, with the reason.> (<Jira or Notion link>)
- **Non-goals:** <what this DAG deliberately does not do, and where that lives instead>

## Open questions
- <Must be empty before the PR to master merges.>

---

## Version
**1.0.0** | **Status:** draft | **Last reviewed:** <YYYY-MM-DD>

| Version | Date | Change | Ref |
| --- | --- | --- | --- |
| 1.0.0 | <YYYY-MM-DD> | <initial README, or "Airflow 3 migration" if migrated> | <DPW-nnnn> |

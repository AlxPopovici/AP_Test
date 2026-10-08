---
name: create-pipeline
description: Scaffold a brand-new Airflow 3 pipeline in this repo, written from scratch — not migrated from the old data.airflow.dags repo. Picks an area/sub-area folder by business domain, copies in a DAG template using RenderedSQLExecuteQueryOperator for SQL, sets up config.yaml/Snowflake identity and the structured tag convention, generates the mandatory smoke test, and leaves incident.io alerting scaffolded but commented out. Stops there for the developer to review. Use when asked to "create a new pipeline", "scaffold a new DAG", "start a brand-new pipeline", "I want to build a pipeline from scratch", or similar — not for moving an existing DAG in from the old repo (use migrate-dag / migrate-pipeline instead).
---

# create-pipeline

**Scaffold a new pipeline that starts life in this repo — no legacy DAG involved.**

Deliberately simple, mirroring `migrate-dag`'s shape: branch → scaffold → generate test →
hand back. It does **not** run pre-commit, commit, or open a PR — those are separate,
explicit steps the developer runs when ready (see Step 6).

If the developer actually wants to move something in from `data.airflow.dags`, stop and
point them at `migrate-dag` / `migrate-pipeline` instead — this skill assumes there is no
source DAG to convert.

---

## Prerequisites (check once, before starting)

Confirm the developer holds the right **Teleport role** and is a member of the matching
**GitHub team** for the area they're about to write into — Airflow edit rights and the
CODEOWNERS-gated PR review/merge rights both come from that, not from anything this skill
can grant. The five areas map 1:1 to the five teams: `data_tooling`↔`data-tooling`,
`data_products`↔`data-products`, `compliance`↔`data-compliance`,
`analytics_platform`↔`data-analytics-platform`, `swe`↔`data-swe`. Full mapping across AD /
Teleport / Airflow / GitHub / AWS IAM, and how to request a missing role, is in
`.claude/skills/onboarding/references/access-and-teams.md`.

This mapping doubles as a practical hint for **Step 2.2** below: in practice the *area* a
new pipeline lands in is usually the developer's own team (that's where they actually have
edit/review access), even though the *sub-area* underneath it is still chosen by business
domain, not team.

---

## Step 1 — Isolate the work

This isn't the migration-flow exception in the root `CLAUDE.md` (no sibling old-repo path
is involved), so follow the general rule: do this in its own worktree on a dedicated
branch, not directly on `master`.

```bash
git checkout master && git pull origin master
```

Then create a worktree (`EnterWorktree` tool, or `git worktree add <path> -b feat/pipeline-<name>`)
before touching any files.

---

## Step 2 — Gather inputs

Ask the developer for these, in one short pass rather than one question at a time:

1. **Pipeline name and one-line purpose.** The name becomes the folder name and `dag_id`
   — pick something in the style of its future siblings (see step 3).

2. **Area** — one of the five fixed top-level areas:

   ```
   analytics_platform   # DWH, reporting, gaming, sport, retail, finance, social, player
   compliance           # Regulatory, AML, responsible gambling, fraud
   swe                  # App-specific pipelines: gaming, sport, retail, social, player
   data_tooling         # Platform infrastructure, shared utilities
   data_products        # ML, personalization, martech, experimentation, data science
   ```
   If they're unsure, suggest one based on the purpose and ask them to confirm — and check
   it against the Prerequisites section above: it's usually the area matching their own
   Teleport role/GitHub team.

3. **Sub-area** — an existing business-domain folder under that area, or a new one. List
   what's already there so they can pick or name a new one:

   ```bash
   ls airflow_etl/dags/<area>/
   ```
   **Name it after the domain, never the team** — see
   [references/area-subarea-guide.md](references/area-subarea-guide.md) for the full rule
   and the current sub-area list per area. A sub-area named after a team goes stale the
   moment that team reorganizes.

4. **Owning team** — becomes the mandatory `owner:<team>` tag and the `default_args["owner"]`
   value. Don't guess this; ask.

5. **Pure SQL, or does it need custom Python logic?** Decides whether the template's `@task`
   example gets kept/adapted or deleted. Either is a valid Airflow 3 pattern here — a
   pure-SQL pipeline using `RenderedSQLExecuteQueryOperator` needs no TaskFlow at all
   (same stance as the `modernize-airflow3-dag` skill: TaskFlow is recommended wherever
   there's Python-callable logic, never mandated for its own sake).

6. **Snowflake identity** — does this pipeline need its own `default_sf_user`, or does the
   chosen sub-area already set one? Check before adding a new `config.yaml`:

   ```bash
   cat airflow_etl/dags/<area>/<sub_area>/config.yaml 2>/dev/null
   ```
   If `default_sf_user` is already set there (under `ALL:`), the new pipeline inherits it —
   don't duplicate it in a pipeline-level `config.yaml`.

---

## Step 3 — Scaffold the folder

Same per-pipeline package layout every pipeline in this repo uses:

```
airflow_etl/dags/<area>/<sub_area>/<pipeline>/
  <pipeline>.py
  config.yaml   # only if this pipeline needs its own default_sf_user or another override
  sql/          # only if it runs SQL
```

Copy [assets/pipeline_template.py](assets/pipeline_template.py) in as `<pipeline>.py`, and
[assets/config_template.yaml](assets/config_template.yaml) in as `config.yaml` only if
Step 2.6 found the pipeline needs its own Snowflake identity.

---

## Step 4 — Fill in the template

- **Documentation** — fill the module docstring at the top of `<pipeline>.py`
  (purpose, audience, what it does / does not do, how to verify, catch-up vs
  clear+rerun, whether an ad-hoc trigger is safe, external deps, known
  oddities). Leave `doc_md=__doc__` so the
  Airflow UI shows it. `description=` stays a one-liner.
  See `airflow_etl/CLAUDE.md` → "DAG documentation".
- **Tags** — set `owner:<team>` from Step 2.4 (the only mandatory key); add
  `business_area` / `source_schema` / `destination_schema` / `source_system` / `component` /
  `markets` only where relevant, per the table in `airflow_etl/CLAUDE.md`'s "DAG Tags"
  section — don't re-derive that table here, read it directly.
- **SQL task(s)** — one `RenderedSQLExecuteQueryOperator` per statement, `conn_id` from
  `get_sf_conn_id(cfg)`, SQL text in a file under `sql/`, referenced via
  `template_searchpath`. Never a `KubernetesPodOperator` shelling out to a Docker-image SQL
  executor — see the "SQL execution" rule in `airflow_etl/CLAUDE.md`.
- **Python logic** — if Step 2.5 said yes, keep and adapt the template's commented `@task`
  example; if the pipeline is pure SQL, delete it entirely rather than leaving dead code.
  Shared *cross-pipeline* helpers go in `include/` (`from include....`).
  Pipeline-local packages under `lib/` are fine (see `migration_tracker`); add
  a nested `.airflowignore` with `lib/` so the DAG processor does not import
  them — see `airflow_etl/CLAUDE.md` → "DAG discovery".
- **Executor routing** — follow `airflow_etl/CLAUDE.md`'s **Executors** section;
  leave routing unset by default and use `executor=` only for an explicit override.
  Size a KubernetesExecutor task through `executor_config`; size a KPO workload
  through `container_resources` or its pod template.
- **Alerting** — leave the incident.io block **commented out**. This is the default for a
  brand-new pipeline: no notifications fire until the developer deliberately turns it on.
  The template uses the `attach_to()` style (the only style this skill documents — see
  [references/alerting-scaffold.md](references/alerting-scaffold.md)), not
  `on_failure_callback`/`on_success_callback`. Don't uncomment it on the developer's behalf.
- **Date/time values** — if anything filters or partitions by date, use
  `data_interval_start` / `data_interval_end`, never `ds`/`execution_date`/`logical_date` —
  those were redefined in Airflow 3 (see the "Date & time variables" section of
  `airflow_etl/CLAUDE.md`). This applies to new pipelines just as much as migrated ones.
- **S3 writes** — if the pipeline writes to S3 directly, go through a shared helper
  (`PyOpsS3Client` or an `api_connect_consumer` S3 consumer) so the cross-account ACL is
  handled automatically. Only hand-roll boto3/s3fs if none of those fit, and never hardcode
  the ACL string — call `cross_account_acl(bucket_name)` instead (applies
  `bucket-owner-full-control` only where ACLs are supported, and skips ACL on
  `BucketOwnerEnforced` buckets; see the "S3 writes (cross-account ACL)" section of
  `airflow_etl/CLAUDE.md`).
**Advanced, opt-in only:** if the pipeline needs to pick a Snowflake compute-warehouse tier
dynamically (e.g. for cost/performance reasons at high row volumes), that's a separate,
non-default pattern — see
[references/warehouse-tier-advanced.md](references/warehouse-tier-advanced.md). Don't bring
it up unless the developer's use case actually calls for it.

---

## Step 5 — Generate the mandatory smoke test

Every pipeline folder carries a `<pipeline>_test.py`. For a brand-new pipeline it's
generated by hand, not written:

```bash
python3 dev_tools/dag_tests/generate.py airflow_etl/dags/<area>/<sub_area>/<pipeline>/<pipeline>.py
```

Then run it:

```bash
DEPLOYMENT_ENV=STAGE .venv/bin/python airflow_etl/dags/<area>/<sub_area>/<pipeline>/<pipeline>_test.py
```

If there's no `.venv` yet or Airflow isn't importable, run the `setup-test-venv` skill
first. Don't hand back to the developer with a failing or ungenerated test.

---

## Step 6 — Hand back to the developer

Report what was scaffolded (folder, tags, whether `config.yaml` was added, whether the
`@task` example was kept or removed) and that the smoke test passes. The remaining steps
are theirs to run when ready — point them at the relevant skills, same handoff shape as
`migrate-dag`:

- **Formatting/lint** — run the `run-pre-commit` skill before committing.
- **Commit + PR** — once they're happy with the review, commit and open the PR themselves
  (`commit-push-pr` skill). Remember the root `CLAUDE.md` guardrail: merging a PR is a
  deploy (`stage`/`preprod`/`master`) — never auto-merge; hand back the PR link.
- **Alerting** — if/when they want notifications, point them at
  `references/alerting-scaffold.md` to uncomment and configure the incident.io block.

---

## Gotchas

- **Don't invent a naming prefix scheme.** Existing pipeline names in a sub-area (e.g. a
  `tran-` prefix on several data_tooling pipelines) may or may not be a deliberate
  convention for that area — look at real siblings in the chosen sub-area and match their
  style rather than assuming a repo-wide rule.
- **Don't skip Step 2.6.** Adding a pipeline-level `config.yaml` with a `default_sf_user`
  that duplicates one already inherited from the area/sub-area breaks the "keep configs DRY"
  rule in `airflow_etl/CLAUDE.md` and creates two sources of truth.
- **This skill doesn't touch `rewrite-tags` or `rewrite-secrets`.** Those exist to fix up
  *migrated* DAGs carrying legacy freeform tags/secret names — a pipeline scaffolded by this
  skill starts with the structured tag convention and team-prefixed secrets already, so
  there's nothing for those skills to do here.

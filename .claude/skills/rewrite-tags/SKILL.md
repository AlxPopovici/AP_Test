---
name: rewrite-tags
description: Convert a pipeline's freeform tags=[...] list into the structured key:value convention (owner, markets, source_schema, destination_schema, business_area, source_system, component). Recommended, not mandatory — skip only if the pipeline's tags already match the convention. Use as a step in migrating a pipeline from data.airflow.dags (ideally right after migrate-dag, before rewrite-secrets), or any time you want an already-migrated pipeline's tags brought up to the current convention. Triggers: "rewrite/migrate tags for <pipeline>", "convert <pipeline>'s tags", "apply the tag convention to <pipeline>".
---

# Rewrite Tags

Rewrite a pipeline's `tags=[...]` list from bare, freeform strings (`'dp-player-wallet'`, `'external-db-loader'`, `'sb_ro'`) into the structured `key:value` convention documented in [airflow_etl/CLAUDE.md - DAG Tags](../../../airflow_etl/CLAUDE.md#dag-tags):

```python
tags=['dp-player-wallet', 'external-db-loader', 'external_db (MSSQL server)', 'icore', 'ods_igp_dwh_ro', 'sb_ro', 'snowflake']
```
becomes
```python
tags=['owner:dp-player-wallet', 'component:external-db-loader', 'source_system:mssql', 'source_schema:ods_igp_dwh_ro', 'markets:sb_ro']
```

**Recognized keys:** see [airflow_etl/CLAUDE.md - DAG Tags](../../../airflow_etl/CLAUDE.md#dag-tags) for the canonical list. `owner` is required — every DAG must end up with one. `markets` is comma-separated if a DAG spans more than one (e.g. `markets:sb_ro,sb_pl`). A tag that doesn't fit any recognized key can stay as a freeform `key:value` (propose a sensible key) rather than being forced into the wrong bucket.

**Recommended, not mandatory.** Unlike `rewrite-secrets` (functional — legacy secret names break) or `run-pre-commit` (required before commit — not CI-enforced, but expected every time), skipping this step leaves the DAG running fine; it only stays off the tag convention (harder to filter/query in the Airflow UI). Skip it only when the pipeline's tags are already fully `key:value` with `owner` set, or the developer explicitly asks to defer tag cleanup to a later pass — otherwise run it as the usual step right after `migrate-dag`.

**Guardrails (never violate):**
- Never write a file without an explicit `y` confirmation.
- Never edit directly on `master`/`stage`/`preprod`, and never edit the primary checkout if you're not already isolated in a dedicated branch or worktree — see "Where to run this" below.
- Never guess `owner`. If the existing tags don't clearly identify the owning team, ask the user rather than picking the closest-looking tag.
- Never silently drop information. If an old tag has no clean mapping (see [references/tag-mapping.md](references/tag-mapping.md)), list it and ask whether to drop it, keep it as a freeform `key:value`, or fold it into an existing key — don't decide unilaterally.
- Don't invent new canonical values. If a tag's value looks like a typo or one-off (e.g. a market spelled out as `romania` instead of `sb_ro`), ask which existing value it should become instead of normalizing it yourself.
- Snowflake schema tags: only map to `source_schema` / `destination_schema` if you can tell which side it's on from the DAG's SQL/operators (e.g. `RenderedSQLExecuteQueryOperator` `sql=` targets, `template_searchpath`). If it's not obvious, ask.

## Where to run this

Two contexts:

1. **As a migration step** (the common case) — invoked by `migrate-pipeline` (or manually, right
   after `migrate-dag`) on a pipeline that already lives on a `feat/migrate-<pipeline>` branch. Reuse
   that branch; do not create another one.
2. **Standalone**, against a pipeline already on `master`. Per this repo's CLAUDE.md ("Concurrent
   sessions — isolate your work"), create a dedicated worktree/branch first — never edit the primary
   checkout or `master`/`stage` directly:
   ```bash
   git worktree add ../data.monorepo.wt-rewrite-tags-<pipeline> -b rewrite-tags/<pipeline> origin/master
   ```

## Usage

- `/rewrite-tags airflow_etl/dags/data_products/martech/ing-skrill-reports-s3/ing-skrill-reports-s3.py` — one pipeline
- `rewrite tags for tran-seon-daily and ing-skrill-reports-s3` — a small batch (a handful at a time, not the whole repo in one pass)

## No path provided

If called without a pipeline path, respond with this prompt (do not run any git commands):

> **Which pipeline(s) do you want to rewrite tags for?**
>
> You can specify one file or a small batch, e.g. `airflow_etl/dags/<area>/<sub_area>/<pipeline>/<pipeline>.py`

Then wait for the user to reply before proceeding.

## Workflow

Propose first, apply only on confirmation, then verify. Do not edit any file before Step 2.

### Step 1 — Read the current tags

Find the `tags=[...]` list in each target file. Note the pipeline's area/sub-area from its path
(`airflow_etl/dags/<area>/<sub_area>/<pipeline>/`) too — useful for sanity-checking `owner`
against the domain it lives under.

If the tags are already fully `key:value` with `owner` set, report that and stop — no changes
needed (see the skip note above). If `tags=[]` or the list is missing entirely, don't treat that
as nothing to do — propose a minimal set starting with `owner`, asking the user if it's not
inferable from the path or DAG content.

### Step 2 — Map each tag

For every existing tag, classify it using the reference table in
[references/tag-mapping.md](references/tag-mapping.md) — open it now, it covers most tags
seen in practice along with the judgment calls each one needs. For anything not in the table,
look at how the tag is used elsewhere (`grep -rn "'<tag>'" airflow_etl/dags/` in this repo, and
`grep -rn "'<tag>'" dags/` in a sibling `data.airflow.dags` checkout if it's still unmigrated there)
to judge whether it's a market, a system, an owner, etc. — but confirm with the user before
committing to an unlisted mapping.

### Step 3 — Build the proposal (do NOT edit yet)

Per file, show:
- **Kept/mapped:** old tag → new tag, one line each.
- **Dropped:** old tags proposed for removal (generic/noise), with the reason.
- **Needs your input:** anything ambiguous (unclear `owner`, unresolved market, schema direction unclear, unlisted tag) — ask explicitly rather than guessing.
- **Final `tags=[...]`** the file would end up with, confirming `owner` is present.

Then ask: **`Apply? [y/N]`** and wait.

### Step 4 — Apply (only on explicit `y`)

Re-confirm you're on the right branch/worktree (see "Where to run this"). Edit the `tags=[...]`
list in place with `Edit`. Don't touch anything else in the file.

### Step 5 — Verify

```bash
python3 -c "import ast; ast.parse(open('<file>').read())"   # syntax still valid
```

Confirm the new tags list only contains `key:value` entries (aside from any explicitly-agreed
freeform exception) and that `owner` is set. If the pipeline has its generated
`<pipeline>_test.py`, run it too.

## Reference

- Tag convention: [airflow_etl/CLAUDE.md - DAG Tags](../../../airflow_etl/CLAUDE.md#dag-tags).
- Full old-tag → new-tag lookup table: [references/tag-mapping.md](references/tag-mapping.md).
- Domain/team mapping for `owner` sanity-checks: `data.airflow.dags`'s
  `CLAUDE.md#team-domains` (the old repo's team-domain table still applies while pipelines are
  mid-migration).

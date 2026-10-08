---
name: migrate-pipeline
description: >-
  End-to-end guided pipeline for migrating ONE DAG from data.airflow.dags into this Airflow 3
  monorepo, out to a stage PR for QA, then a master PR after sign-off. Orchestrates the existing
  steps — stage_master__diff + parametrize_dag + create-missing-stage-tables (old repo), then
  migrate-dag, rewrite-tags, rewrite-secrets, optionally modernize-airflow3-dag, run-pre-commit
  (this repo) — and manages the stage→master promotion. Use for the FULL flow: "run the full migration for DAG X", "migrate DAG X
  end to end", "take DAG X to stage", "promote the migrated DAG X to master", "what's the status of
  DAG X's migration", or "resume migrating DAG X". For the single copy+convert step only, use
  migrate-dag instead.
---

# migrate-pipeline

**The front door for migrating one DAG all the way from `data.airflow.dags` to a merged master PR.**

This skill is a *thin orchestrator*. It owns only three things: **sequencing**, the two **human
checkpoints** (QA on stage, sign-off before master), and **cross-repo bookkeeping**. Every real
step is delegated to a skill or script that already exists — this skill must never reimplement
their logic, so when a leaf step changes, the orchestrator stays correct by delegating.

Plain "migrate DAG `<name>`" (no "end to end" / "full") means the single-step **migrate-dag** skill,
not this one.

Scope is **one DAG per run**. A feature branch `feat/migrate-<pipeline>` carries it: **PR #1 →
`stage`** for QA, then after sign-off **PR #2 → `master`** from the same branch.

---

## How this skill delegates (read this first)

- **This-repo steps are Skill-tool skills.** Invoke `migrate-dag`, `rewrite-tags`,
  `rewrite-secrets`, and `run-pre-commit` via the Skill tool as normal. They are the single source
  of truth for how each step works — do not paraphrase or duplicate their steps here.
- **Old-repo steps are NOT loaded in this session.** This session is rooted in `data.monorepo`, so
  `../data.airflow.dags/.claude/` skills and commands are *not* available to the Skill tool. For
  each one, **read the file and follow it inline**, running its git/shell commands with the old
  repo as the working directory:
  - `../data.airflow.dags/.claude/commands/stage_master__diff.md`
  - `../data.airflow.dags/.claude/commands/parametrize_dag.md`
  - `../data.airflow.dags/.claude/skills/create-missing-stage-tables/SKILL.md`
    (+ its bundled `create_missing_stage_tables.py`)
- **Never auto-merge. Merges are deploys.** Merging PR #1 deploys to the **stage** AWS account;
  merging PR #2 deploys to **prod** (both via the CodeCommit mirror). Open PRs and hand back the
  links. Merge only when the developer explicitly asks.

---

## On entry: detect the phase (resume-safe)

One invocation can't wait days for QA, so this skill is resumable with **no state file** — it reads
git + GitHub state. Derive `<pipeline>` from the DAG name — the source file's stem, or the
**package name** for package-style sources (`dags/<pkg>/dag.py`; see migrate-dag's package-style
gotcha) — then:

```bash
git branch --list feat/migrate-<pipeline>
git ls-remote --heads origin feat/migrate-<pipeline>
gh pr list --head feat/migrate-<pipeline> --base stage  --state all
gh pr list --head feat/migrate-<pipeline> --base master --state all
```

The PR checks dominate: a missing *local* branch alone proves nothing (fresh clone, different
machine, deleted local branch) — never restart a migration whose branch or PRs exist remotely.

- **No branch (local or remote) and no PRs** → start **Phase A** at step 0.
- **Branch exists (local or remote), no stage PR (or stage PR still building)** → resume
  **Phase A** at whatever step is unfinished (inspect the working tree / branch).
- **Stage PR open or merged, no master PR** → you are at the **QA checkpoint** → **Phase B**.
- **Master PR exists** → the pipeline is essentially done; report its status.

---

## Phase A — build → stage PR

### 0. Pre-flight (once, fail loud with the fix)

```bash
ls ../data.airflow.dags/dags/                          # old repo present as a sibling
git status --short                                     # THIS repo's tree is clean
git -C ../data.airflow.dags status --short -- <target> # old repo: target DAG file has no tracked edits
ruff --version                                         # required by the Airflow 3 conversion
pre-commit --version                                   # required by the lint step
gh auth status                                         # required to open PRs
```

- If **this repo's** tree is dirty → stash or commit first.
- If the old repo is missing → both repos must be siblings under the same parent.
- If **the target file** has uncommitted tracked edits in the old repo → have the developer resolve
  them first. **Ignore unrelated untracked files** in the old repo — it is a working checkout and is
  expected to be dirty; only the target DAG file matters. Never run `git clean` on it.
- `ruff` is not optional — without it the conversion silently skips its import-rewrite pass and
  produces a half-converted DAG (`pip install ruff`).
- If `pre-commit` is missing, invoke `install-pre-commit` before continuing.
- Only if the missing-tables step (step 3) will run: `SNOWFLAKE_USER` must be set to the developer's
  Snowflake SSO username.

### 1. Scope

Confirm the single DAG. Defer area/sub-area entirely to `migrate-dag`'s own prompts — do not ask
for them here. Then ask one gating question:

> **Are stage and prod already aligned for this DAG — same code, and no tables missing in the STAGE Snowflake DB?**

If **yes** → skip steps 2 and 3, go straight to step 4. If unsure → don't skip.

### 2. (skippable) Consolidate stage vs master in the old repo

Only if the DAG may still hardcode env-specific values (`if database == 'STAGE'` ternaries, divergent
stage/master copies). Working directory is `../data.airflow.dags`.

1. **Optional check** — read `stage_master__diff.md` and follow it for this DAG to see whether it is
   flagged `ENV` / `ENV-ONLY`. If the DAG isn't flagged (no env divergence), there is nothing to
   parametrize — skip the rest of this step.
2. **Parametrize** — read `parametrize_dag.md` and follow it for the target DAG path. Per its own
   guardrails it will create a throwaway feature branch `parametrize/<dag_id>` off `origin/master`
   in the old repo and apply edits there (uncommitted). This is a **working-tree-only** use — we
   only need the converged file to copy; we deliberately do **not** commit the convergence back, and
   the old repo stays un-converged (it is a read-only source being decommissioned).

Leave the old repo checked out on the `parametrize/<dag_id>` branch for now — step 4 reads the
converged file from this checkout. Step 4 cleans it up.

### 3. (skippable, always confirm before creating) Create missing STAGE tables

Only if the DAG references tables that may be missing in the STAGE Snowflake DB. Working directory is
`../data.airflow.dags`. Read `create-missing-stage-tables/SKILL.md` and follow it inline:

1. Enumerate the SQL files the DAG executes (that skill's reasoning step).
2. **Dry run first** — run its bundled script with `DRY_RUN=Y` and absolute SQL paths:
   ```bash
   SNOWFLAKE_USER=<sso-user> DRY_RUN=Y python3 \
     ../data.airflow.dags/.claude/skills/create-missing-stage-tables/create_missing_stage_tables.py \
     /abs/sql/a.sql /abs/sql/b.sql
   ```
3. Show the developer the summary — `to_create`, and `missing_in_prod_too` (cannot be created).
   **Get an explicit confirmation**, then re-run **without** `DRY_RUN` to create the tables in STAGE.

### 4. Migrate into the monorepo

Invoke the **migrate-dag** skill (Skill tool). It branches `feat/migrate-<pipeline>` off master in
*this* repo, runs `move_dag.py` reading the converged file from the old repo's current checkout,
generates the smoke test, rewrites Snowflake refs and legacy alerting callbacks to `attach_to()`,
and syntax-checks. Surface its Snowflake / Alerting / SQL / config review notes **verbatim** and
apply the manual items.

**If `move_dag.py` exits 2**, an `ACTION NEEDED` date-macro box was printed (`logical_date` /
`ds` / `execution_date` / `ts` / `next_execution_date` / `execution_date_fn` / etc. no longer
mean the data interval in Airflow 3). Treat it as a hard stop, same as a syntax error: for each
hit, look up the exact pattern in `dev_tools/airflow3_migration/DATE_VARIABLES.md` and either
apply its replacement (usually `data_interval_start`/`data_interval_end`) and re-run
`migrate.py <file> --dry-run` to confirm exit `0`, or — if it's just a label/timestamp — carry
a one-line justification (`logical_date at <file>:<line> — label only, not a filter.`) into the
**stage PR description** you open in step 7, since that's the first PR this flow produces.
Full recipe in `RULES.md`'s "Resolving a finding" section.
Do not let it ride through to the stage PR unaddressed — it's a silent-wrong-date bug, not
something QA will necessarily notice.

Then **clean up the old repo** (only if step 2 created a parametrize branch): discard its edits and
return it to a clean `master`.

```bash
git -C ../data.airflow.dags checkout -f master        # discards parametrize's tracked edits only
git -C ../data.airflow.dags branch -D parametrize/<dag_id>
```

`checkout -f` touches only tracked files (parametrize's edits) — unrelated untracked files are left
alone. Confirm `git -C ../data.airflow.dags status --short -- <target>` is now empty.

### 5. Rewrite tags (recommended, not mandatory)

Invoke the **rewrite-tags** skill (Skill tool) on the new file — it's already on the
`feat/migrate-<pipeline>` branch from step 4, so reuse it (don't create another branch/worktree).
Follow its proposal → confirm → apply flow; resolve anything it flags as ambiguous with the
developer rather than guessing. Per rewrite-tags's own skip note, it's fine to skip only when the
pipeline's tags are already fully `key:value` with `owner` set, or the developer explicitly asks
to defer tag cleanup — otherwise run it, same as any other step in this chain.

### 6. Rewrite secrets

Invoke the **rewrite-secrets** skill (Skill tool) on the new file. Follow its own "Required
follow-up" section in full — don't rely on a paraphrase here, it's exactly the kind of detail that
goes stale.

### 7. (optional) Modernize to Airflow 3 best practices

Ask the developer if they want the pipeline brought up to current TaskFlow style now (PythonOperator
→ `@task`, imports moved into task bodies) rather than as a separate later pass. If yes, invoke the
**modernize-airflow3-dag** skill (Skill tool) on the new file, still on `feat/migrate-<pipeline>`.
Run it before lint (next step) so pre-commit covers its output. If no, skip straight to step 8.

### 8. Lint, commit, open the stage PR

1. Invoke the **run-pre-commit** skill (Skill tool) on the changed files; resolve any yamllint
   violations it can't auto-fix. sqlfluff failures on templated DAG SQL are usually **false
   positives** — don't rewrite the SQL to satisfy the linter (see migrate-dag's templated-SQL
   gotcha).
2. Commit with a conventional-commit message, e.g.
   `feat(<area>): migrate <pipeline> to Airflow 3`.
3. Push and open PR #1 **to stage**:
   ```bash
   git push -u origin feat/migrate-<pipeline>
   pr_url=$(gh pr create --base stage --head feat/migrate-<pipeline> \
     --title "feat(<area>): migrate <pipeline> to Airflow 3" --fill \
     --label stage)
   gh pr edit "$pr_url" --body "$(gh pr view "$pr_url" --json body -q .body)

   ## Before merging
   - [ ] Pause \`<pipeline>\` on the Airflow 2 deployment
   "
   ```
   This checklist item is migration-specific — there's an old DAG to pause. Skip it entirely for
   brand-new pipelines (the `create-pipeline` skill never reaches this step).
4. Give the developer the PR link. **Do not merge.**

### 9. Stop at the QA checkpoint

Tell the developer: validate the DAG on stage, then come back with **"it works"** (→ Phase B
sign-off) or **a list of issues** (→ Phase B fixes). End the run here — this is where days may pass.

---

## Phase B — resume after QA

Reached when `feat/migrate-<pipeline>` exists and a stage PR is open or merged.

- **Issues reported** → fix on the *same* branch, re-run pre-commit, commit, `git push`. If the stage
  PR was already merged, the pushed fixes need a fresh merge to `stage` (only if the developer asks).
  Stay at the QA checkpoint.
- **Signed off** → open PR #2 **to master** from the same branch:
  ```bash
  pr_url=$(gh pr create --base master --head feat/migrate-<pipeline> \
    --title "feat(<area>): migrate <pipeline> to Airflow 3" --fill \
    --label PROD)
  gh pr edit "$pr_url" --body "$(gh pr view "$pr_url" --json body -q .body)

  ## Before merging
  - [ ] Pause \`<pipeline>\` on the Airflow 2 deployment
  "
  ```
  Give the link. Master requires a CODEOWNER review and a **merge commit** — squash and rebase
  are disabled at the repo level (see *Why every PR is a merge commit* in `airflow_etl/CLAUDE.md`).
  **Merge only if asked.** Same rule as the stage PR: the pause-old-DAG item is migration-only.
- **Repush after `stage`/`master` moved.** If `git push` on the fix (above) is rejected or the PR
  shows a conflict, `master`/`stage` moved underneath the branch since it was cut — `git fetch` and
  rebase or merge as the developer prefers, then re-push. Don't force-push without asking.

---

## Gotchas

- **`stage`, not `stage/master`.** The long-lived deploy branches are exactly `master`, `preprod`,
  `stage`, `dev`. PR bases are `--base stage` and `--base master`.
- **Label every PR by env.** `--base stage` → `--label stage`; `--base master` → `--label PROD`.
  (`--base preprod` → `--label preprod`, if a preprod PR is ever opened here.)
- **Two PRs, one branch.** PR #2 to master is opened from the same `feat/migrate-<pipeline>` branch
  after the stage PR — it is not a promotion merge between long-lived branches.
- **The old repo is expected to be dirty.** Scope every cleanliness check to the target DAG file;
  never gate on a fully clean old-repo tree and never `git clean` it.
- **parametrize_dag is used off-label.** Its designed intent is to permanently converge stage+master
  in the old repo; here we only borrow the converged file and throw the branch away. Don't commit the
  convergence back unless the developer explicitly wants the old repo converged too.
- **Batch is out of scope.** One DAG per run. For several DAGs, run this skill once per DAG — each
  gets its own branch, PRs, and independent QA.
- **`feat/migrate-<pipeline>` is a contract.** See migrate-dag's own note on this branch-naming
  contract — don't rename the convention in one place without the others.
- **A step fails mid-Phase-A.** Stop and report the error to the developer rather than retrying
  blindly or skipping ahead. Leave the branch and working tree as they are so the failure stays
  inspectable — nothing in this flow rolls back automatically.
- **Primary checkout by design.** This flow is the documented exception to the worktree rule in the
  root `CLAUDE.md` — its tooling reads the old repo at the sibling path `../data.airflow.dags`.
  Don't wrap it in a worktree; coordinate so only one migration runs at a time.

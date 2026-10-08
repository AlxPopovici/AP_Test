# data.monorepo

The Superbet **data department monorepo** — intended as the central place for everything the
data team versions: Airflow, lambdas, Snowflake management, shared scripts and utilities, and
whatever comes next. Each such project lives in its own top-level directory.

**Today there is one project: the Airflow 3 deployment under `airflow_etl/`.** The Airflow 2 → 3
migration is the sole focus for roughly the next six months; other projects will be added as
top-level siblings later. Until then, effectively everything in this repo is about Airflow.

## Working here

- **New to the Airflow side?** The **`onboarding`** skill is the go-to orientation — why we're
  migrating, the architecture, the gitflow/environments, and how to migrate a pipeline. Point
  newcomers there before diving into specifics.
- **Airflow / DAGs / the migration** — the authoritative guide is **`airflow_etl/CLAUDE.md`**
  (repo structure, config hierarchy, secrets, Snowflake, git workflow, executors, and the
  migration chain). Read it first for any Airflow work. All Airflow runtime code lives under
  `airflow_etl/`; the CodeCommit mirror flattens `airflow_etl/` → its root, so pods see
  `dags/ include/` at the top level.
- **Martech** (`airflow_etl/dags/data_products/martech/`): before starting any
  Martech work, read `airflow_etl/dags/data_products/martech/CLAUDE.md`. It is
  the area guide for dbt, its trigger DAGs, and standalone pipelines.
- **`dev_tools/`** — repo tooling behind the skills: `airflow3_migration/`, `secrets_migration/`,
  `dag_tests/`, `airflow3_chart_rollout/`, and the `deploy_airflow3_env/` runbook.
- **`.claude/skills/`** — the skills that drive migration and linting.
- **Adding a new kind of project?** Give it its own top-level directory (a sibling of
  `airflow_etl/`) with its own `CLAUDE.md`, rather than growing this root file.

## Airflow 3 Helm charts (data.gitops) — required skill

**Always use the `airflow3-chart-rollout` skill**
(`.claude/skills/airflow3-chart-rollout/SKILL.md`) when the work touches
Airflow 3 Helm charts in **data.gitops**: isolating a chart change to
airflow3-dev / stage / preprod / prod, forking `_charts/airflow-v3*`,
overwriting an env symlink, promoting a chart to the next env, or collapsing
a feature copy back to the canonical chart.

Do **not** improvise `cp -a` / `rm` / `ln -s` from memory. Run that skill
(and `dev_tools/airflow3_chart_rollout/chart.sh`); it owns the colleague
symlink process (one feature directory; promote by retargeting the next env
at the **same** directory). data.gitops PRs target **`master` only** — there
is no gitops `stage` branch (that flow is this monorepo's DAG gitflow, not
gitops).

## Concurrent sessions — isolate your work

Assume you are **not** alone. Multiple agents and people routinely work in this repo at the
same time, in other sessions you can't see. Never treat the primary checkout as yours alone —
editing it directly races other sessions and corrupts their state.

- **Before changing anything, move your work into its own git worktree on a dedicated branch** —
  don't edit files directly in the primary checkout or on `master`/`stage`. **Always cut that
  branch from `origin/master`**, never from `stage`. In this harness use the Agent tool's
  `isolation: "worktree"` (or the `EnterWorktree` tool); by hand it's
  `git worktree add <path> -b <branch> origin/master`. Read-only exploration doesn't need one.
- **Exception — the migration flow.** `migrate-pipeline` / `migrate-dag` run in the primary
  checkout on their dedicated `feat/migrate-<pipeline>` branch by design: their tooling reads the
  old repo at the sibling path `../data.airflow.dags`, which a worktree under `.claude/worktrees/`
  would break. Coordinate so only one migration runs at a time, and return the checkout to
  `master` when done.
- **Clean up after yourself.** Once the branch is pushed / PR opened / work abandoned, remove your
  worktree (`git worktree remove <path>`) and prune stale entries (`git worktree prune`). Stray
  `agent-*` trees under `.claude/worktrees/` from dead sessions are fair game to prune.
- `.claude/worktrees/` is gitignored — worktrees are local scratch, never commit one.

## Migrating a pipeline

One front door: the **`migrate-pipeline`** skill (copy+convert → stage PR → QA → master PR).
The ordered step chain and every skill behind it are in `airflow_etl/CLAUDE.md`
(*Migration pipeline — which skill, in order*).

## Airflow deploy guardrail

Specific to the Airflow project: **merging a PR is a deploy** — PR → `stage` deploys to the
stage AWS account, PR → `master` to prod, both via the CodeCommit mirror. Never auto-merge:
open PRs and hand back the links; merge only when the developer explicitly asks.

**Emergency break-glass, `master` only.** During an incident, a member of
`@superbet-group/data-on-call` can merge a PR to `master` without a CODEOWNER review by
adding the `oncall-emergency` label — a GitHub Actions workflow, mediated by the
`data-on-call-emergency` App, does the merge and posts to the PR and Slack. See
`.github/oncall-emergency-merge.md`. This is a human, on-call-only action — an agent must
never apply this label itself.

## PR review (Super AI)

**Super AI** (`agentic-pr-bot`) auto-reviews only PRs whose **base** is
`master` (`COMMENTED`, never a merge blocker). PRs to `stage`, `preprod`, or
any other base are skipped unless someone comments `/super-ai review` — do
that on the stage PR if you want the bot's notes before merging to stage.
The GitHub App matches the **repo once**. The S3 guidance routes **product
folders** (`airflow_etl/` today; later `tableau/` + `CLAUDE.md`) vs **root**
(`dev_tools/`, `.claude/`, `.github/`, `CLAUDE.md`, `CODEOWNERS`). Do not
apply Airflow DAG rules to root or to another product. Structure comments as
**Critical Issues** / **Warnings** / **Suggestions**.

Guidance: `superbet-group/agentic.gitops` →
`services/pr-bot/guidance/data-monorepo-guidance.md`. In-repo Airflow design
docs: `airflow_etl/docs/` (not Notion). SQL layout is sqlfluff. Re-run:
`/super-ai review`.

**Root (every PR, thin):** merge-commit gitflow, no secrets, no auto-merge.
**PRs to `master` and `preprod`:** Airflow runtime `*.py` / `*.sql` / `*.yaml`
/ `*.yml` — the `stage-parity.yml` workflow (`.github/scripts/verify-stage-parity.sh`,
imported verbatim from `superbet-group/data-git-flow-testing`, scoped here
via `PATHSPECS`) computes the actual 3-way merge result (`git merge-tree`
against the target's current tip, not the PR head) and checks it, jointly
across every changed file, against `origin/stage`'s full history within a
60-day freshness window. **Any** mismatch — a path that never existed on
stage, an older/superseded match, or files that each existed individually
but never coexisted — fails the check with the exact wording from the
source repo. This check is **not** in `required_status_checks` on
`master`/`preprod` (only "Wiz Secret Scanner" is), so today it's advisory:
it can go red without blocking the merge. “Merging is a deploy” is Airflow
CodeCommit, not every folder.

The `pr-review-checker` skill is an optional extra pass, not the automatic reviewer.

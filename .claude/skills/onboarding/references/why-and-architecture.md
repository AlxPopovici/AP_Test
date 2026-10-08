# Why Airflow 3, and the architecture

Synthesized from the Notion **[Airflow3] Solution Proposal (Internal)** — the canonical, living
source. When something here matters to a decision, open the proposal:
https://www.notion.so/superbet/Airflow3-Solution-Proposal-Internal-fffe87f205b74662b8c8b126c019e34a

## Contents
- [Why (context and drivers)](#why-context-and-drivers)
- [Deployment and code distribution](#deployment-and-code-distribution)
- [Environments](#environments)
- [Repo structure, ownership, guardrails](#repo-structure-ownership-guardrails)
- [Access control](#access-control)
- [Secrets model](#secrets-model)
- [Explicitly out of scope](#explicitly-out-of-scope)

## Why (context and drivers)

We are moving from **Airflow 2.x to 3.x**, but this is **not a version bump** — it's the
occasion to fix reliability, developer experience, and operational guardrails at scale:
~500 DAGs, 60+ data engineers, a multi-team development model, and adoption expanding beyond the
data org.

The drivers behind the decisions below:
- **Reduce environment drift** — stop copy/pasting code between environment branches.
- **Avoid GitHub outages impacting production scheduling** (this has bitten us repeatedly).
- **Support high-frequency deployments** — on the order of ~100 stage deployments per day.
- **Improve developer experience without reducing safety.**
- **Scale ownership** so more teams can build pipelines without endangering critical workflows.

## Deployment and code distribution

**Feature-Based Promotion (the gitflow).** Developers branch from `master` and deploy by opening
PRs from feature branches directly to `stage`, `preprod`, or `master` (prod). Because every new
piece of work starts from `master`, production-ready code "flows down" instead of being
hand-copied between long-lived branches. PRs are not mandatory for `stage`/`preprod`; `master`
requires a CODEOWNER review.

**Internal Git mirror (AWS CodeCommit) — the reliability keystone.** Developers still collaborate
in GitHub. A GitHub Action mirrors the environment branches to **AWS CodeCommit** (OIDC + IAM).
Airflow uses **GitDagBundle** and points *only* at the CodeCommit mirror — so if GitHub is down,
running pipelines are unaffected.

**Execution code locking.** GitDagBundle lets workers pull the specific commit a run started with,
so long-running pipelines finish on the same code they began with.

**Executor strategy (hybrid).**
- **CeleryExecutor (default)** — resource-light tasks: SQL to Snowflake, orchestration. Scales
  horizontally via worker replicas.
- **KubernetesExecutor** — resource-intensive or long-running tasks; each runs in its own pod with
  a custom ECR image, preventing scheduler resource contention. Heavy processing continues via
  KubernetesPodOperator.

## Environments

- **Prod** — as today.
- **Preprod** — a clone of prod (realistic data and performance).
- **Stage** — connected to *other services'* lower environments.

**Airflow UI links** (Teleport-gated):
- Prod: https://airflow3-prod.teleport.happening.dev/
- Stage: https://airflow3-stage.teleport.happening.dev/
- Dev: https://airflow3-dev.teleport.happening.dev/

Dev is Data Tooling's own environment for testing platform changes (it predates Stage) — for
pipeline QA during a migration, use **Stage**, not Dev.

Data availability on stage is intentionally partial: the tooling team does not synthesize stage
data beyond what exists organically, and there is a script/skill to create **missing empty
tables** so a DAG can at least be exercised. Team agreement: **do not use prod data in lower
envs.** If data isn't on stage, either create the missing (empty) objects to test basic
functionality, or use preprod for realistic logic and performance.

## Repo structure, ownership, guardrails

A **functional-area monorepo** so ownership and navigation scale with 500 DAGs and 60+
contributors. Ownership boundaries are enforced with **CODEOWNERS** at the functional-area level;
shared foundations stay protected by the platform team. Best practices are made the default via
**templates + shared utilities**, enforced by **GitHub Actions / CI**.

A functional area is meant to have: clear team ownership and on-call, a predictable internal
layout (DAG + docs + tests + optional shared sub-area), and minimal coupling to other areas.

Guardrails the CI intends to enforce: allowed paths and required files; secrets referenced only
through approved helpers and naming; standard Snowflake user / namespace / config resolution; and
Airflow parsing safety (no heavy top-level imports or non-deterministic DAG generation), with
failures pointing at the exact file and rule.

> The concrete, current folder layout and the area/sub-area rules live in
> **`airflow_etl/CLAUDE.md`** — that is the source of truth, not the illustrative tree in the
> proposal.

## Access control

Airflow 3 has no out-of-the-box multi-tenant authoring controls, so access is approximated with
**Teleport roles + Airflow roles + a cluster DAG policy**. Every user gets **global viewer**
access to all DAGs (read-only baseline); **edit** access is scoped per team to that team's paths.
A cluster policy injects `access_control` based on the DAG's file path; `webserver_config.py` maps
Teleport groups to Airflow roles.

Edit scopes by area: `analytics_platform` → `dags/analytics_platform/**`; `data_products` →
`dags/data_products/**`; `compliance` → `dags/compliance/**`; engineering/app pipelines →
the `swe` area; `data_tooling` → `dags/data_tooling/**`.

The same five teams also exist as AD roles, GitHub teams, and AWS IAM roles, with rules for who
should hold each one and how those systems are (and aren't) kept in sync. See
**[access-and-teams.md](access-and-teams.md)** for the full picture.

## Secrets model

The goal is to balance team autonomy (on stage *and* prod) against production safety and tooling
overhead. The preferred model: **per-team Teleport access + IAM roles, with secrets prefixed by
owning team** (`<team>__<secret_name>`). Teams manage their own secrets; other teams can see
secret metadata but not cross-use secrets unless explicitly allowed. Legacy secret names are
rewritten to the new prefixes by automation — in this repo that's the `rewrite-secrets` skill and
`dev_tools/secrets_migration/`.

## Explicitly out of scope

- **S3 bucket migration** — buckets stay in the current account. They have many internal/external
  stakeholders, migration is high-effort and largely independent, and it would add risk to an
  already complex migration. Revisit later if a clear need emerges.

---
name: onboarding
description: >-
  Onboarding and general orientation for the data.monorepo Airflow 3 repo, aimed at data
  engineers arriving to move a pipeline from the old Airflow 2 repo (data.airflow.dags) into
  this one. Explains why the migration is happening, the architecture, how the repo folders are
  organized and navigated, how the gitflow and environments work, and how to actually migrate a
  pipeline (the migrate-pipeline entry-point skill and the step chain behind it). Use when a new
  engineer asks to "onboard me on this repo", "give me an overview", "where does my pipeline go",
  "why are we migrating to Airflow 3", "how does the gitflow work here", or "how do I migrate my
  DAG" — and as the go-to reference for general questions about how this repo works.
---

# Onboarding: the Airflow 3 monorepo

This is `data.monorepo` — Superbet's **Airflow 3** DAG monorepo, and the target of the
Airflow 2 → 3 migration (~500 DAGs, 60+ engineers). Pipelines move here, one at a time, from
the old Airflow 2 repo `data.airflow.dags`. The **data platform tooling team** owns the repo
structure, CI guardrails, and shared utilities; each team owns its own functional area under
`airflow_etl/dags/`.

Use this skill to orient a data engineer who is new to the repo. Give a short spoken-language
overview of whichever topic they ask about, then point them at the authoritative source for
detail. **Do not paste large chunks of the reference docs** — summarize and link, so answers
stay current as those docs change.

## The four things a newcomer needs

### 1. Why we're doing this, and the architecture
It is **not** a version bump — the migration is the moment to fix reliability, developer
experience, and guardrails. The headline decisions: feature-based Git promotion (branch from
`master`, PR down to environments), an AWS **CodeCommit mirror** so GitHub outages never touch
running pipelines, prod/preprod/stage environments, per-team secrets and DAG-edit access, and a
functional-area monorepo layout enforced by CODEOWNERS + CI.

→ Full rationale and each decision: **[references/why-and-architecture.md](references/why-and-architecture.md)**.
The canonical source is the Notion **[Airflow3] Solution Proposal**:
https://www.notion.so/superbet/Airflow3-Solution-Proposal-Internal-fffe87f205b74662b8c8b126c019e34a

Access itself (who should hold which team's role, and how AD/Teleport/Airflow/GitHub/AWS IAM stay
in sync) is its own topic — see **[references/access-and-teams.md](references/access-and-teams.md)**
if someone asks "how do I get access" or "why can I view but not edit this DAG".

### 2. How the repo is structured and navigated
All Airflow runtime code lives under `airflow_etl/` (`dags/`, `include/`). DAGs sit
in `dags/<area>/<sub-area>/<pipeline>/`, where the top-level **areas** (`analytics_platform`,
`data_products`, `compliance`, `swe`, `data_tooling`) are fixed and tooling-owned, while
**sub-areas are team-owned** — group them by business domain, not by team name. Config is
hierarchical `config.yaml` deep-merged by folder; secrets are `<team>__<name>`; reach Snowflake
only through `include.airflow.snowflake`.

→ The authoritative, always-current reference is **`airflow_etl/CLAUDE.md`** (sections: *Repo
structure*, *Configuration*, *Secrets*, *Snowflake connections*, *Executors*). Read it before
answering structure/config/secrets questions in depth, then summarize the relevant part.

### 3. How the gitflow and environments work
Branch from `master`. PRs can target `stage`, `preprod`, or `master` directly — production-ready
code "flows down" because new work always starts from `master`. `master` = prod, `preprod` = a
prod clone, `stage` = wired to other services' lower environments. Airflow reads from the
**CodeCommit mirror** (synced by GitHub Actions), never GitHub directly. **Merging a PR is a
deploy**: PR → `stage` deploys to the stage account, PR → `master` deploys to prod.

→ Detail lives in **`airflow_etl/CLAUDE.md`** (*Git workflow*) and, for the reasoning,
**[references/why-and-architecture.md](references/why-and-architecture.md)**.

### 4. How to actually migrate a pipeline
There is one **front door**: the **`migrate-pipeline`** skill. It's an end-to-end guided flow
for moving ONE DAG from `data.airflow.dags` to a stage PR for QA, then a master PR after
sign-off. It doesn't reimplement anything — it sequences the existing steps (`migrate-dag`,
`rewrite-tags`, `rewrite-secrets`, optionally `modernize-airflow3-dag`, `run-pre-commit` in this
repo, plus a few old-repo prep steps) and manages the two human checkpoints.

→ Walkthrough of the flow and what each step does: **[references/migration-path.md](references/migration-path.md)**.
When the engineer is ready to migrate, tell them to run **`migrate-pipeline`** and follow its
prompts.

## How to answer onboarding questions

- **"Onboard me" / "give me an overview"** → walk through the four topics above briefly, then
  ask which they want to go deeper on.
- **A specific topic** → give the one-paragraph summary here, read the linked source if you need
  detail, and answer from it. Prefer the in-repo docs (`airflow_etl/CLAUDE.md`, the skills) over
  restating — they are the source of truth and this skill only orients.
- **"How do I migrate my pipeline?"** → point them to `migrate-pipeline` and offer to start it.

# How to migrate your pipeline

There is **one front door**: the **`migrate-pipeline`** skill. Tell the engineer to run it and
follow its prompts. Everything below is orientation — what the flow looks like and what each step
does — so a newcomer knows what to expect. The `migrate-pipeline` SKILL.md is the source of truth
for the exact commands and checkpoints; don't reproduce them here.

## The mental model

- **Scope is one DAG per run.** For several DAGs, run the flow once per DAG — each gets its own
  branch, PRs, and independent QA.
- **One feature branch, two PRs.** `feat/migrate-<pipeline>` carries the work:
  **PR #1 → `stage`** for QA, then after sign-off **PR #2 → `master`** from the *same* branch.
- **Merging is deploying.** Merging PR #1 deploys to the stage AWS account; merging PR #2 deploys
  to prod (both via the CodeCommit mirror). The skills **never auto-merge** — they open PRs and
  hand back the links. You merge when you're ready.
- **`migrate-pipeline` is a thin orchestrator.** It owns only sequencing, the two human
  checkpoints, and cross-repo bookkeeping. Every real step is a skill or script that already
  exists — so when a step changes, the orchestrator stays correct.
- **The old repo is a read-only source being decommissioned.** Pipelines are copied *fresh* from
  `data.airflow.dags`. The old repo is expected to be dirty; the flow only cares about the target
  DAG file.

## The flow at a glance

**Phase A — build → stage PR** (runs in one sitting): after a pre-flight check (repos side by
side, clean tree, `ruff` / `pre-commit` / `gh` available), the flow optionally converges any
stage-vs-master divergence and creates missing STAGE tables in the old repo, then chains the
this-repo skills in the canonical order — `migrate-dag` → `rewrite-tags` → `rewrite-secrets` →
optionally `modernize-airflow3-dag` → `run-pre-commit` — commits, and opens **PR #1 → `stage`**.
The run ends at the **QA checkpoint**:
validate the DAG on stage; days may pass.

**Phase B — resume after QA** (resume-safe: the skill re-derives its phase from git + GitHub
state, no state file). Issues found → fix on the same branch, re-lint, push, stay at the
checkpoint. Signed off → open **PR #2 → `master`** from the same branch; master needs a
CODEOWNER review and a merge commit (squash/rebase are disabled repo-wide) — merged only when
you ask.

The exact steps, commands, and checkpoint mechanics live in the `migrate-pipeline` SKILL.md —
read that rather than relying on this summary.

## The skills behind the flow

Each is its own skill you *can* run directly, but `migrate-pipeline` chains them for you, in this
order: `migrate-dag` → `rewrite-tags` → `rewrite-secrets` → optionally `modernize-airflow3-dag` →
`run-pre-commit`.

The **canonical order and one-line purpose of each lives in `airflow_etl/CLAUDE.md`**
(*Migration pipeline — which skill, in order*) — read that for what each step actually does, or
the skill's own SKILL.md for how to run it standalone. Don't rely on a paraphrase here; it's the
kind of detail that goes stale.

`migrate-airflow-3` is **not a step in the flow** — it's the Airflow 2→3 transform that
`migrate-dag` runs under the hood; invoke it directly only to re-convert files already in
the repo.

## What to tell an engineer who's ready

> Run **`migrate-pipeline`** for your DAG and follow its prompts. It'll take you to a stage PR,
> pause for you to QA on stage, then open the master PR once you sign off. It won't merge anything
> — you stay in control of both deploys.

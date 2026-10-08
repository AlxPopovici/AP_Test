---
name: run-pre-commit
description: Run this repo's pre-commit hooks (Black, sqlfluff, yamllint, trailing-whitespace) on demand against changed files, specific files, or the whole repo — auto-fixing what it can and surfacing the rest. Use to lint/format before committing, or when asked to "run pre-commit", "run the hooks", "lint the files", "check formatting", or "fix formatting". For the one-time git-hook installation on a fresh machine, use the install-pre-commit skill instead.
---

# run-pre-commit

Run pre-commit checks on the current working tree and auto-fix any fixable violations.

This is the last step of the per-pipeline migration chain — after the optional
`modernize-airflow3-dag` — typically invoked by `migrate-pipeline` right before commit. It's
equally usable standalone any time you want to lint/format before committing.

## Steps

### 1. Check pre-commit is installed

```bash
pre-commit --version
```

If that fails, invoke the **install-pre-commit** skill to set it up, then continue here.

### 2. Run the hooks on the changed files

Bare `pre-commit run` sees **staged files only** — unstaged edits and (critically) untracked new
files like a freshly migrated pipeline are skipped entirely and report green. Default to passing
the changed + untracked files explicitly:

```bash
pre-commit run --files $(git diff --name-only HEAD) $(git ls-files --others --exclude-standard)
```

If the user asks to check ALL files in the repo (e.g. "run pre-commit on everything"):

```bash
pre-commit run --all-files
```

If the user passes specific files (e.g. "run pre-commit on airflow_etl/dags/foo/bar.py"):

```bash
pre-commit run --files airflow_etl/dags/foo/bar.py
```

### 3. Stage any auto-fixed files

Black, sqlfluff-fix, and trailing-whitespace write fixes in-place. After pre-commit runs, stage
**exactly the files the hooks ran on** so the next commit picks the fixes up:

```bash
git add <the files passed to --files above>
```

Never blanket-`git add` everything modified in the tree — that would silently stage the user's
unrelated edits alongside the hook fixes.

### 4. Report results

Tell the user:
- Which hooks passed / failed / made fixes.
- If **sqlfluff-lint** is still failing after auto-fix, check the templated-SQL caveat below
  first — on migrated DAG SQL these are usually false positives, not violations to fix.
- If **yamllint** failed, surface those lines too — yamllint has *no* auto-fix, so any `config.yaml` / `.yaml` violation needs a manual edit.
- If Black changed files, the fixes are already staged (per step 3).

## Templated DAG SQL — expect sqlfluff false positives

The repo's sqlfluff config uses the `placeholder`/`dollar` templater, which does **not** resolve
Airflow Jinja. Two known false-positive classes on migrated DAG SQL:

- bare `{{ params.x }}` in an identifier/value position → `PRS` "unparsable section";
- Snowflake session vars like `$ROW_CNT AS ROW_CNT` → `AL09` self-alias.

The SQL is correct — Airflow renders the Jinja at runtime. **Never rewrite the SQL to satisfy the
linter** (auto-fixing the AL09 deletes the alias and corrupts the query; bare numeric templates
can't be quoted). Report these as expected linter noise, not as violations. Details: *Templated
SQL confuses sqlfluff* in `airflow_etl/CLAUDE.md`.

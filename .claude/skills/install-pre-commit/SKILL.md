---
name: install-pre-commit
description: One-time per-machine setup that installs this repo's pre-commit git hooks (Black, sqlfluff, yamllint, trailing-whitespace) so they run automatically on every commit, then surfaces any existing violations. Use when asked to "set up pre-commit", "install pre-commit hooks", or "install the git hooks". For on-demand lint/format runs after setup, use the run-pre-commit skill instead.
---

# install-pre-commit

Install pre-commit hooks for this repository and surface any existing violations.

The configured hooks are: **Black** (Python formatting, auto-fix), **sqlfluff-fix / sqlfluff-lint** (SQL, fix + lint), **yamllint** (YAML lint, *no* auto-fix), and **trailing-whitespace** (auto-fix).

Only `pre-commit` itself needs to be installed — it downloads and manages Black, sqlfluff, and yamllint in isolated hook environments, so there's no need to `pip install black` / `sqlfluff` separately.

## Steps

### 1. Check pre-commit is installed

```bash
pre-commit --version
```

If that fails (command not found), offer to install it — `pip install pre-commit` (or `pipx install pre-commit` / `brew install pre-commit` if the user prefers an isolated/global install). Install it with the user's go-ahead, then continue; only stop if the install fails or is declined. On some macOS Python setups, plain `pip install` fails with an externally-managed-environment error — prefer `pipx` or `brew` in that case rather than passing `--break-system-packages`.

### 2. Install the git hooks

Run from the repo root:

```bash
pre-commit install
```

This overwrites any existing `.git/hooks/pre-commit` file. If the repo already uses another hook
manager (e.g. husky, a custom script), check first and warn the user before overwriting it.

### 3. Run against all files (surface existing violations)

```bash
pre-commit run --all-files
```

### 4. Report results

Tell the user:
- That `pre-commit install` wired up the git hook (future commits will run the checks automatically).
- Whether `pre-commit run --all-files` found any violations, and which hooks fired.
- If violations were found, note that the auto-fix hooks (Black, sqlfluff-fix, trailing-whitespace) have **already written their fixes to the working tree** during step 3 — the developer just needs to review and `git add` them.
- That **yamllint** violations are never auto-fixed and need a manual edit. **sqlfluff-lint** failures may clear on a re-run (this repo's config runs lint *before* fix, so fixable rules show as lint failures on the first pass); anything still failing after a re-run needs a manual look — and on templated DAG SQL expect the false positives described in the run-pre-commit skill, not real violations.

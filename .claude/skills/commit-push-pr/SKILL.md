---
name: commit-push-pr
description: Commit changes, push to remote, and create a pull request. Use for completing features or fixes ready for review. Triggers when user wants to commit and create PR, mentions Jira tickets, asks to push changes for review, or says things like "ready to PR", "create pull request", "open PR for review".
---

# Commit, Push, and Create PR

> Repo note: in `data.monorepo` this skill is Claude-only (no `.cursor/skills/` copy). If a `.cursor/skills/commit-push-pr/SKILL.md` is ever added, keep it in sync with this file in the same PR.

End-to-end workflow for committing, pushing, and creating a pull request with Jira integration, Technical Why reasoning, and structured PR body.

## Pre-computed Context

Run these in parallel as the very first step:

```bash
git branch --show-current
git status --short
git log --oneline -10
git diff --stat
git branch -vv | head -5
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

## Phase 1: Branch Readiness

> **`data.monorepo` git workflow (read `airflow_etl/CLAUDE.md` → Git workflow + merge commits).**
> This repo disables "Squash and merge" and "Rebase and merge" at the repo level — every PR
> lands as a two-parent **merge commit**, which is what keeps `master`↔`stage` ancestry fresh.
> Consequences for this skill:
> - **Branch from `master`.** Never cut a feature branch from `stage`. Never rebase a feature
>   branch onto `stage` (it rewrites the base and breaks the master-ancestry the merge relies
>   on). To refresh, **merge** the target in.
> - **Flow:** `master` → feature branch → PR/merge to `stage` → more fixes on the **same**
>   branch → PR/merge that same branch to `master` (prod). Do not create a separate prod branch.
> - PRs can target `stage`, `preprod`, or `master`. Route through `stage` first where practical;
>   if something goes straight to `master`, backport to `stage` as part of finishing the change.
> - **This file is the source of truth** for commit/push/PR in this repo. Agents must follow
>   this skill (not a home-directory copy) when opening PRs.

### Check divergence

```bash
git fetch origin
git rev-list --count origin/<target>..HEAD   # ahead
git rev-list --count HEAD..origin/<target>   # behind
```

### Decision tree

| Situation | Action |
|-----------|--------|
| Clean, <10 behind | \`git merge origin/<target>\` (do NOT rebase — see note above) |
| 10-49 behind | \`git merge origin/<target>\` (do NOT rebase — see note above) |
| Up to date | Proceed directly |
| >50 behind or mixed merge commits | **Cherry-pick clean branch** (see below) |
| Worktree based on \`stage\`, PR targets \`master\` | **Cherry-pick clean branch** |

### Cherry-pick clean branch (preferred for diverged branches)

**NEVER rebase a branch >50 commits behind. Always cherry-pick.**

```bash
# 1. Identify your feature files (only YOUR commit, not full stage-vs-master diff)
git diff --name-only HEAD~<N>..HEAD   # where N = number of your feature commits

# 2. Create clean branch from target
git checkout -b <branch>-clean origin/<target>

# 3. Bring feature files — BUT distinguish new vs modified:
#    a) NEW files (don't exist on target): safe to checkout directly
git checkout <original-branch> -- path/to/new_file.py

#    b) MODIFIED files (exist on both stage and target with different content):
#       DO NOT checkout from feature branch — that brings the stage base, not target base.
#       Instead, read the target version (already on clean branch) and surgically
#       apply ONLY your additions/changes on top of it.
#       Use StrReplace / manual edits to add your changes to the target version.

# 4. Single clean commit
git add -A
git commit -m "feat: descriptive message

Refs: TICKET-123, TICKET-456"

# 5. Push (always use explicit branch name, never HEAD)
git push -u origin <branch>-clean
```

**Critical: stage-vs-master file divergence.** When your worktree is based on `stage` and the PR targets `master`, shared files (like DAG definitions) will have diverged between the two branches. The feature branch version is `stage-base + your changes`, NOT `master-base + your changes`. Blindly checking out modified files from the feature branch contaminates the clean branch with all stage-only differences.

**How to handle modified files:**
1. After creating the clean branch (step 2), the file already has the master version
2. Read master's version of the file to understand its current state
3. Identify the minimal surgical changes your feature adds (import, task def, wiring)
4. Apply only those changes with targeted edits — do NOT wholesale replace the file

If cherry-pick conflicts on "deleted" files → prerequisite PR not merged to target → use file checkout instead.

## Phase 2: Pre-commit Hooks

1. **Prefer hooks when the expected diff is small**: let hooks run naturally for focused changes.
2. **Avoid large formatting diffs mixed with functional work**: if hooks rewrite unrelated or many existing lines, restore the functional diff, commit with `--no-verify`, then create a separate `style:` commit for formatting if the user wants it.
3. **Auto-fixes that only touch your files** (black, sqlfluff): re-stage and commit again.
4. **Jinja/sqlfluff false positives**: try the Jinja templater before skipping hooks:
   ```bash
   sqlfluff lint --templater jinja <file.sql>
   ```
   Use `--no-verify` only when the failure is a known false positive or the formatting diff would obscure the functional review.
5. **Formatting noise on other people's code**:
   ```bash
   git show origin/<base>:<filepath> > <filepath>
   # re-apply only your functional changes
   git commit --amend --no-edit --no-verify
   git push --force-with-lease  # NEVER --force
   ```

## Phase 3: Gather PR Details

Ask the user with a structured form tool first (prefer Cursor `AskQuestion` / inform tool when available). If the form tool is unavailable, ask conversationally.

**Structured form batching rule:** `AskQuestion` supports at most 4 questions per call. This limit cannot be bypassed in the tool schema. Do not pad to 4 questions. Ask only the blocking questions, with 4 as the maximum, not the target.

If more details are needed, ask in small batches:

**Batch 1: required blockers**
1. **Base branch** — auto-detect from \`git symbolic-ref refs/remotes/origin/HEAD\`, confirm with user
2. **PR title** — suggest from recent commits, let user refine
3. **Jira tickets** — always ask the user; if a ticket is detected from branch name, suggest it for confirmation
4. **Draft or ready** — default: draft

**Batch 2: PR content, only if not inferable**
1. **Technical Why** — ask what the reasoning/motivation is (not what changed, but WHY)
2. **Tested on stage?** — confirm whether changes were tested on the stage environment; if yes, ask for the actual stage Airflow DAG run/log URL used during testing
3. **Intended to be promoted to prod?** — confirm production intent
4. **Known limitations or follow-ups?** — ask what is intentionally out of scope

**Batch 3: optional, only if relevant**
1. **Reviewers** — or skip / add later
2. **Notion link** — if there is a design/spec/review page
3. **Airflow DAG/run link** — ask for the stage/prod DAG URL when the PR touches an Airflow DAG or pipeline, and prefer the actual stage run/log URL when available
4. **Deployment checklist items** — DDL, pause DAGs, backups, backfills, cleanup

If still relevant after Batch 3, ask a follow-up for reviewers or "If not mergeable yet, reason" instead of padding the previous batch.

Ask only the batches that are needed. Do not ask non-critical questions if they can be confidently inferred from git diff, commits, or PR context, except Jira: always ask for Jira confirmation.

**Practical workaround for complex PRs:** If `AskQuestion` would require too many structured questions, ask a single conversational question instead, listing the missing details in plain text. Example: "I can infer most of this from the diff. Please confirm Jira, stage testing, prod intent, and any known follow-ups." This avoids forcing multiple structured-form calls when a normal reply is easier.

**Adaptive loop:** If more than 4 structured questions are truly needed, loop over batches sequentially: ask up to 4 via `AskQuestion`, wait for answers, re-evaluate what is still missing, then ask the next batch. Later batches must depend on previous answers. Stop as soon as enough information is available.

**Important:** If the structured form tool (`AskQuestion`) is not available (e.g. in Claude Code CLI), ask these questions as plain text in your response using the same batched structure. Do NOT skip the questions — ask conversationally and wait for the user's reply before proceeding.

## Phase 4: Generate PR Body

**Structure by DWH entity/table, NOT by file.** Use the exact format below.

### PR Body Format

Use this template structure:

- Title with emoji and business context
- Summary (pull from Jira description when possible)
- Technical Why (the reasoning behind the change)
- Jira and Notion links
- Environment Clarity (stage testing, prod intent)
- Known Limitations & Follow-ups
- DAG Flow in a dedicated collapsible toggle
- Key Changes per Entity in a dedicated collapsible toggle
- Additional Information in a dedicated collapsible toggle (dependencies, pre-merge checklist, rollback, data impact, config, scheduling)

**Mandatory collapsible layout:** Render exactly three standalone `<details>` sections in this order:
1. `🏗️ DAG Flow`
2. `🗃️ Key Changes per Entity`
3. `📎 Additional Information`

Do not nest one section inside another. Do not merge these three sections into a single toggle.

**IMPORTANT: Never include "Added files" or "Modified files" lists.** Organize changes by logical entity/table/feature, not by file path.

**Jira Description as Summary:** If the branch name contains a Jira ticket ID (e.g. `GUJD-113`), try to pull the ticket's description for the PR summary rather than writing one from scratch. The Jira description is the single source of truth for "what" — the PR body adds "why" and "how".

Example structure:

```
## 🏷️ [Concise Title — What & Why]

[1-2 sentence overview — ideally pulled from Jira description]

📋 **Jira:** [TICKET-1](url) · [TICKET-2](url)
📖 **Notion:** [doc name](url)

---

### 💡 Technical Why

[2-4 sentences explaining the technical reasoning behind this change.
Why this approach? What problem does it solve? What was the alternative considered?
This is NOT a description of what changed — it's the reasoning for WHY it changed.]

---

### 🌍 Environment Clarity

- **Tested in stage?** Yes / No / Dry-run only
  - [Include short explanation based on the user's answer]
  - **Stage execution:** [Airflow DAG run/log URL, if tested in stage]
- **Intended to be promoted to prod?** Yes / No
- **If not mergeable, reason:** _N/A or documented reason_

---

### ⚠️ Known Limitations & Follow-ups

- [What's intentionally out of scope]
- [Deferred work or known gaps]
- [Follow-up PRs planned]

---

<details>
<summary><h3>🏗️ DAG Flow</h3></summary>

\`\`\`mermaid
graph LR
    A["extract_retail_data"] --> B["transform_gaming"]
    A --> C["transform_sportsbook"]
    B --> D["load_to_dwh"]
    C --> D
    D --> E["old_legacy_task"]
    D --> F["data_quality_checks"]

    classDef added fill:#d4edda,stroke:#28a745,stroke-width:2px;
    classDef removed fill:#f8d7da,stroke:#dc3545,stroke-width:2px,stroke-dasharray: 5 5;

    class A,B,C,F added;
    class E removed;
\`\`\`

_🟢 Green = Added in this PR | 🔴 Red = Removed/deprecated_

</details>

<details>
<summary><h3>🗃️ Key Changes per Entity</h3></summary>

Table with changes organized by entity/table/feature

</details>

---

<details>
<summary><h3>📎 Additional Information</h3></summary>

#### Dependencies

| Direction | What | Details |
|-----------|------|---------|
| ⬆️ Upstream | [upstream DAG/service] | [what it provides] |
| ⬇️ Downstream | [downstream DAG/service] | [impact or "NOT affected"] |

#### Author Pre-check

- [ ] SQL is readable and formatted
- [ ] Hardcoding is avoided, or documented where intentional
- [ ] DAG follows existing patterns
- [ ] Naming is consistent and meaningful

#### Pre-merge Deployment Checklist

> ⚠️ **[Critical prerequisite if any — e.g., requires DDL changes before deploy]**

##### 1. 🔒 Pause conflicting DAGs
- [ ] `dag-name` — reason

##### 2. 💾 Backup existing tables
- [ ] Clone `DWH.TABLE` → `SBX_DP.TABLE_BKP`

##### 3. 🏗️ Create new tables
- [ ] `SCHEMA.NEW_TABLE`

<details>
<summary>DDL</summary>

\`\`\`sql
CREATE OR REPLACE TRANSIENT TABLE SCHEMA.NEW_TABLE (
    -- include actual DDL derived from INSERT statements or existing tables
);
\`\`\`

</details>

##### 4. ➕ Add new columns
- [ ] `TABLE` — `COL_A`, `COL_B`

##### 5. 🔄 Migrate existing data
- [ ] Backfill `COLUMN` from `SOURCE`

##### 6. 🚀 Deploy & verify
- [ ] Merge PR → verify DAG in Airflow UI
- [ ] Trigger run if needed
- [ ] Verify row counts and integrity

##### 7. 🧹 Cleanup
- [ ] Resume paused DAGs
- [ ] Drop backup tables after validation

#### Rollback Plan
- [How to revert safely]

#### Data Impact
- [New/modified/deleted data]
- [Impact on existing records]

#### Configuration Changes
- [New connections, variables, env vars, or "None"]

#### Scheduling
- [When/how this runs in production]
- **DAG link:** [Airflow DAG URL, if applicable]
- **Stage execution:** [Airflow DAG run/log URL, if tested in stage]

</details>

```

### Mermaid Rules (GitHub)

- \`graph LR\` (left-to-right) or \`graph TD\` (top-down)
- Node labels in **double quotes**: \`A["my label"]\`
- **NEVER** put emojis inside node labels — GitHub can't render them
- Keep it simple: one node per task group, not per task

**Color coding for changes:**
- 🟢 **Green** for added nodes/edges: \`class A,B added;\`
- 🔴 **Red** for removed nodes/edges: \`class C,D removed;\`
- Default (no class) for existing unchanged nodes

**Example with color coding:**

\`\`\`mermaid
graph LR
    A["new_task_group"] --> B["existing_task"]
    B --> C["old_task_being_removed"]
    B --> D["another_new_task"]

    classDef added fill:#d4edda,stroke:#28a745,stroke-width:2px;
    classDef removed fill:#f8d7da,stroke:#dc3545,stroke-width:2px,stroke-dasharray: 5 5;

    class A,D added;
    class C removed;
\`\`\`

**How to identify changes:**
1. Compare DAG file in current branch vs base branch
2. Look for new task definitions (added in this PR) → mark green
3. Look for deleted task definitions (present in base, removed in PR) → mark red with dashed border
4. Show both old and new in the diagram to illustrate the migration path
5. For replaced tasks, show both: old (red) and new (green) with annotation

### Analyzing the Diff

Read the git diff to understand:
- Which tables/schemas are affected
- New vs modified vs removed components
- DAG structure changes
- The **technical reasoning** behind the change (why, not just what)

**For Mermaid diagrams:**
- Compare DAG file in current branch vs base branch (use \`git diff origin/<base>..HEAD -- path/to/dag.py\`)
- Identify added task groups/tasks (lines with \`+\`) → mark green in diagram
- Identify removed task groups/tasks (lines with \`-\`) → mark red with dashed border
- Show the migration path: old (red) → new (green)

Organize the PR body by **entity** (DWH tables), not by file path. For example:
- ✅ "New table \`DWH.RETAIL_SALES\`"
- ❌ "Modified \`dags/retail/sales.py\`"

**NEVER list files as "Added" or "Modified".** GitHub already shows the file diff — the PR body should explain intent and impact at the entity/business level.

### Environment Clarity Guidelines

- Ask whether the change was tested in stage; do not assume.
- Include the CR fallback explanation only when the user says stage data is unavailable, dummy data is not feasible, or the change was dry-run only:
  - "Data is not readily available in stage; dry run validated the flow and logic."
  - "Data validation/testing will be carried out in Production using real data."
  - "Any required logic adjustments can be addressed through subsequent PRs."
- If the change was fully tested in stage, replace the fallback explanation with the actual test evidence.
- If the change was not tested, state the reason briefly and document the validation plan.

### Checklist Guidelines

The Pre-merge Deployment Checklist lives inside the collapsible "Additional Information" section. Follow these rules:

- Split into **numbered phases** with emojis
- Each item is a **checkbox** `- [ ]`
- Include actual table/object names, not placeholders
- **Only include phases that are relevant** — skip phases that don't apply (e.g. no "Pause DAGs" if nothing needs pausing)
- Standard phase order: pause → backup → DDL → migrate → deploy/verify → cleanup
- Use `<details><summary>DDL</summary>...</details>` for CREATE TABLE statements (derive columns from INSERT statements in the codebase)
- Use `<details><summary>SQL</summary>...</details>` for long migration/backfill scripts

### Jira and Notion Links

Format Jira links:
```
📋 **Jira:** [PROJ-123](https://jira.company.com/browse/PROJ-123) · [PROJ-456](https://jira.company.com/browse/PROJ-456)
```

If Notion URL provided:
```
📖 **Notion:** [Retail Pipeline Migration](https://notion.so/...)
```

## Phase 5: Preview & Execute

Show summary block:
```
Branch:     feat/GUJD-113-retail-pipeline
Base:       master
Title:      feat: Retail gaming daily pipeline — Syswin migration
Commits:    3
Draft:      yes
Reviewers:  alice, bob
```

Then show full PR body with proper markdown rendering.

Ask: **"Look good? (yes / edit / cancel)"**

If confirmed, execute in single response with parallel tool calls:

```bash
# Push branch
git push -u origin "$(git branch --show-current)"

# Create PR with heredoc to preserve formatting
gh pr create \\
  --base <base> \\
  --title "<title>" \\
  --body "\$(cat <<'EOF'
<rendered body>
EOF
)" \\
  --label "<env-label>" \\
  [--draft]  # include only when user chose "draft"; omit when user chose "ready"
```

**Env label is mandatory.** This repo runs separate PRs per environment, and each must carry the
matching label so it's identifiable at a glance: base `master` → label `PROD`, base `stage` →
label `stage`, base `preprod` → label `preprod`. Set `--label` from `<base>` every time — never
omit it and never guess a different mapping.

If reviewers specified:
```bash
gh pr edit <pr-number> --add-reviewer <users>
```

Return the PR URL.

## Key Rules

1. **Entity-centric** — organize by DWH table/entity, NOT by file path. Never list "Added files" or "Modified files".
2. **Technical Why** — every PR must explain the reasoning, not just describe what changed
3. **Emojis** — use in section headers and table rows for scanning
4. **Three-toggle layout is mandatory** — keep `🏗️ DAG Flow`, `🗃️ Key Changes per Entity`, and `📎 Additional Information` in separate standalone `<details>` sections
5. **Preserve formatting** — when touching other people's code, only functional changes
6. **Cherry-pick over rebase** — for diverged branches, always
7. **\`--force-with-lease\`** — after amending, never \`--force\`
8. **Single response** — execute all bash commands in parallel tool calls in one message
9. **Heredoc for PR body** — use \`cat <<'EOF'\` to preserve markdown formatting
10. **No Co-authored-by trailers** — NEVER add \`--trailer "Co-authored-by: ..."\` or any Co-authored-by trailer to \`git commit\` commands. Do not include Co-authored-by in commit messages in any form.
11. **Env label is mandatory** — every \`gh pr create\` must set \`--label\` matching the base branch: \`master\` → \`PROD\`, \`stage\` → \`stage\`, \`preprod\` → \`preprod\`.

## Error Handling

**Pre-commit hook failures:**
- Keep functional and formatting changes separate.
- Re-stage and commit again when auto-fixes only touch the intended files.
- If hooks create broad formatting noise, restore the functional diff and use `--no-verify`; add a separate `style:` commit only if requested.
- For Jinja/sqlfluff issues, try `sqlfluff lint --templater jinja <file.sql>` before treating it as a false positive.
- Document why you're skipping hooks if you do.

**Merge conflicts:**
- Cherry-pick to clean branch instead of rebasing
- Identify feature-specific files only
- Create single clean commit on target base

**Missing information:**
- Ask user for Jira tickets if not in branch name
- Ask for Notion doc URL if referenced
- Ask for the Technical Why if not obvious from the diff

## Context Awareness

This skill is designed for data engineering workflows involving:
- Airflow DAGs
- DWH (Data Warehouse) tables
- SQL migrations
- Kafka pipelines

Adapt the PR body format if working on different types of projects (web apps, APIs, etc.), but maintain the structure:
- Clear title with business context
- Technical Why section (reasoning, not description)
- Issue tracking links (Jira/GitHub issues)
- Visual diagrams where helpful
- Change summary by logical component (never file lists)

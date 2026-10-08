---
name: pr-review-checker
description: >-
  Review pull request code changes against data engineering standards and post review
  comments directly to GitHub. Checks correctness, safety, maintainability, consistency,
  and promotion readiness. Use when user provides PR number to review.
---                                                                                                            
                                                                                                                 
  # PR Review Checker                                                                                            
                                                                                                                 
  Automated code review for data engineering pull requests. Reviews code and posts findings directly as PR       
  comments.

  **Automatic first pass:** Super AI (`agentic-pr-bot`) comments on PRs
  (`COMMENTED`, never `REQUEST_CHANGES`), Critical / Warning / Suggestion.
  Airflow DAG rules only for `airflow_etl/`; `dev_tools/` / `.claude/` /
  `.github/` / root files use the shared **root** checklist. Optional deeper
  pass — do not duplicate Super AI nits.
                                                                                                                 
  ## When to Use                                                                                                 
   
  Trigger phrases:                                                                                               
  - "review PR #123"
  - "check PR 456"                                                                                               
  - "review pull request 789"                                                                                    
  - "/pr-review-checker 123"                                                                                     
                                                                                                                 
  ## Phase 1: Fetch PR Context                                                                                   
                                                                                                                 
  ### Parse PR number from user input                                                                            
                  
  Extract PR number from phrases like:                                                                           
  - "review PR #123" → 123
  - "check PR 456" → 456                                                                                         
  - "/pr-review-checker 789" → 789                                                                               
                                                                                                                 
  ### Load project documentation standards
  
  **CRITICAL**: Before analyzing code, load the latest standards from `.claude` folder:
  
  ```bash
  # Read current documentation (run these in parallel)
  # data.monorepo consolidates all DAG/SQL/alerting/config standards into two CLAUDE.md
  # files — there is NO .claude/docs or .claude/rules tree here.
  cat CLAUDE.md                 # repo-wide: git workflow (merge-commit only), deploy guardrail, envs
  cat airflow_etl/CLAUDE.md     # DAG standards: code style, executors, config.yaml, secrets, tags, Snowflake, SQL
  cat airflow_etl/docs/data-design-guidelines.md
  cat airflow_etl/docs/snowflake-object-naming.md
  cat airflow_etl/docs/sql-formatting.md   # sqlfluff owns formatting — do not nitpick
  cat dev_tools/airflow3_migration/DATE_VARIABLES.md
  ```
  
  These standards live in `airflow_etl/CLAUDE.md` (DAG-level), `airflow_etl/docs/`, and repo-root `CLAUDE.md`:
  - **Code style & formatting**: naming conventions, code standards, team-specific rules
  - **Migration pipeline / Executors**: DAG structure, environment handling, executor routing
  - **Alerting**: IncidentIO integration requirements (`attach_to()`)
  - **Configuration (`config.yaml`)**: YAML config patterns, connection IDs
  - **SQL execution**: RenderedSQLExecuteQueryOperator; formatting is sqlfluff
  - **DAG documentation**: module docstring + `doc_md=__doc__`
  - **Secrets / Snowflake connections / DAG Tags**: team-prefixed secrets, connection ids, tagging
  - **Git workflow (root `CLAUDE.md`)**: merge-commit-only, branch-from-master, route via stage
  
  Use these docs as the **source of truth** for your review criteria. The embedded examples in this skill are fallback guidance only.
                                                                                                                 
  ### Gather PR information                                                                                      
                                                                                                                 
  Run these in parallel:                                                                                         
                  
  ```bash                                                                                                        
  # Get PR metadata
  gh pr view <pr-number> --json number,title,baseRefName,headRefName,url,body                                    
                                                                                                                 
  # Fetch PR diff                                                                                                
  gh pr diff <pr-number>                                                                                         
                                                                                                                 
  # Get changed files list with stats                                                                            
  gh pr view <pr-number> --json files --jq '.files[] | {path: .path, additions: .additions, deletions:           
  .deletions}'
  ```

  ## Phase 2: Analyze Against Standards
  
  **Apply loaded documentation standards first**, then use the examples below as supplementary guidance.
  
  ### Key Standards from Documentation
  
  When reviewing, prioritize rules from:
  1. `airflow_etl/CLAUDE.md` → "Code style & formatting" - naming, structure, team conventions
  2. `airflow_etl/CLAUDE.md` → "Migration pipeline" / "Executors" - DAG structure & executor routing
  3. `airflow_etl/CLAUDE.md` → "Alerting" - required IncidentIO `attach_to()` usage
  4. `airflow_etl/CLAUDE.md` → "SQL execution" / "Configuration (`config.yaml`)" - operator & config patterns

  **Check for documentation drift**:
  - If PR introduces new patterns not covered, suggest updating `airflow_etl/CLAUDE.md`
  - If PR contradicts the CLAUDE.md standards, flag it as either incorrect code OR outdated docs
  
  Review code changes across 4 dimensions:                                                                       
                  
  ### 1. Correctness & Safety                                                                                        
                  
  Check for:                                                                                                     
  - ✅ Logic matches PR description
  - ⚠️  Risk of data duplication (same data inserted multiple times)                                              
  - ⚠️  Risk of data deletion (DROP, DELETE, TRUNCATE without safeguards)
  - ⚠️  Unintended backfills (missing date filters, full table scans)                                             
  - ✅ Filters are explicit (no implicit date ranges, clear WHERE clauses)                                       
  - ✅ Joins have clear conditions (no accidental cross joins)                                                   
  - ⚠️  Idempotency: can the DAG/SQL run multiple times safely? (exclude Snowflake stream consumers — appending is their intended pattern)                                                   
                                                                                                                 
  Red flags:                                                                                                     
  - DELETE FROM table without WHERE clause                                                                       
  - TRUNCATE on production/DWH schemas (DWH, DM_PERF, etc.) without safeguards — flag as red
  - TRUNCATE on staging schemas (STAGE_DWH, STAGE_PLAYER, etc.) is normal load pattern — do not flag                                                                       
  - Joins without ON conditions or with ambiguous keys
  - Date filters using CURRENT_DATE in daily scheduled jobs — prefer {{ ds }} or execution context for correct historical re-runs; CURRENT_DATE is acceptable for non-scheduled or non-daily jobs                                                 
  - INSERT INTO without INSERT OVERWRITE or deduplication logic — except when consuming Snowflake streams, where appending is intentional to preserve history                                                  
  - Backfill logic that doesn't respect {{ ds }} or {{ execution_date }}                                         
                                                                                                                 
  Example issues to flag:                                                                                        
  # BAD: Deletes all data                                                                                        
  DELETE FROM dwh.sales WHERE 1=1                                                                                
                                                                                                                 
  # GOOD: Deletes specific partition                                                                             
  DELETE FROM dwh.sales WHERE date = '{{ ds }}'                                                                  
                                                                                                                 
  # BAD: Can insert duplicates on retry                                                                          
  INSERT INTO dwh.sales SELECT * FROM staging.sales                                                              
                                                                                                                 
  # GOOD: Idempotent operation                                                                                   
  INSERT OVERWRITE dwh.sales PARTITION (date='{{ ds }}')                                                         
  SELECT * FROM staging.sales WHERE date = '{{ ds }}'                                                            
                                                                                                                 
  ### 2. Maintainability                                                                                             
                                                                                                                 
  Check for:                                                                                                     
  - ✅ Code is readable (clear variable names, logical structure)                                                
  - ⚠️  Duplicated patterns (same logic copy-pasted across files)                                                 
  - ✅ Comments explain WHY, not WHAT                           
  - ⚠️  Complex logic without explanation                                                                         
  - ⚠️  Hardcoded values (magic numbers, literal dates)                                                           
  - ✅ Reusable components extracted (macros, utility functions)                                                 
                                                                                                                 
  Red flags:                                                                                                     
  - Same SQL query repeated in multiple files with minor variations                                              
  - DAG task groups with identical structure but different table names within the same domain or pipeline — only suggest templating for related jobs, not across unconnected pipelines                                           
  - Complex date manipulation without comments                        
  - Hardcoded table names across multiple files (should be config)                                               
  - Long functions/queries (>100 lines) without logical sections                                                 
                                                                                                                 
  Example issues to flag:                                                                                        
  # BAD: Duplicated logic                                                                                        
  # File: dags/retail_sales.py                                                                                   
  def validate_sales_data():                                                                                     
      query = "SELECT COUNT(*) FROM sales WHERE date = '{{ ds }}'"                                               
      result = execute_query(query)                                                                              
      if result < 1000:                                                                                          
          raise Exception("Data quality check failed")                                                           
                                                                                                                 
  # File: dags/retail_inventory.py                                                                               
  def validate_inventory_data():                                                                                 
      query = "SELECT COUNT(*) FROM inventory WHERE date = '{{ ds }}'"                                           
      result = execute_query(query)                                                                              
      if result < 1000:                                                                                          
          raise Exception("Data quality check failed")                                                           
                                                                                                                 
  # GOOD: Extract to shared utility                                                                              
  # File: utils/validators.py                                                                                    
  def validate_min_row_count(table, min_rows=1000):                                                              
      query = f"SELECT COUNT(*) FROM {table} WHERE date = '{{{{ ds }}}}'"                                        
      result = execute_query(query)                                                                              
      if result < min_rows:                                                                                      
          raise Exception(f"Data quality check failed for {table}")                                              
                                                                                                                 
  ### 3. Consistency & Standards
  
  **CRITICAL**: Use naming conventions from `airflow_etl/CLAUDE.md` ("Code style & formatting"), NOT the examples below.
  
  Check for:                                                                                                     
  - ✅ Follows folder structure from project docs
  - ✅ Naming conventions match `airflow_etl/CLAUDE.md` ("Code style & formatting") patterns
  - ✅ DAG pattern matches branch context (master = PROD-only, stage = multi-env factory)
  - ✅ Uses `attach_to()` for alerting (not manual callbacks)
  - ✅ Uses existing patterns for similar problems                                                               
  - ⚠️ Deviates from standards without explanation                                                               
                                                                                                                 
  To check naming patterns:                                                                                      
  # Check if similar DAGs exist                                                                                  
  find dags/ -name "*<domain>*" 2>/dev/null | head -5                                                            
                                                                                                                 
  # Check naming patterns for similar tables                                                                     
  grep -r "dwh\." tasks/ 2>/dev/null | grep -i "<entity>" | head -5                                              
                                                                                                                 
  # Check if similar transformations exist                                                                       
  grep -r "<pattern>" tasks/ -A 5 2>/dev/null | head -20                                                         
                                                                                                                 
  ### 4. Promotion Readiness                                                                                         
                                                                                                                 
  Check for:                                                                                                     
  - ✅ No hardcoded environment-specific values                                                                  
    - No prod, stage, dev in table/schema names                                                                  
    - No hardcoded hostnames or credentials    
  - ✅ Configuration externalized (Airflow variables, connections, YAML config files in `dags/configs/`)                                         
  - ✅ Stage-to-prod promotion path is clear
  - ✅ **Paths exist on stage first** (for master PRs). Content may differ
    during a soak; that is a warning, not a blocker.
  - ⚠️ Environment-specific logic without documentation
  
  **CRITICAL - Stage Branch Verification** (for PRs targeting master/main):
  
  If `baseRefName` is `master` or `main`, verify changes exist in stage branch:
  
  ```bash
  # Fetch stage branch once before the loop
  git fetch origin stage:stage 2>/dev/null || true

  # For each changed file, check if it exists in stage
  for file in $(gh pr view <pr-number> --json files --jq '.files[].path' | grep -E '\.(py|sql|yaml)$'); do
    # Check if file exists in stage branch
    git show origin/stage:"$file" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "⚠️  File not found in stage: $file"
    else
      # Compare content - check if stage already has this PR's specific changes
      # (compare the PR branch, not origin/master, which is master's state before this PR merges)
      git diff origin/stage HEAD -- "$file" | head -20
    fi
  done
  ```
  
  Flag in review if:
  - 🔴 **CRITICAL**: A changed `airflow_etl` `*.py` / `*.sql` / `*.yaml` path
    is **absent** on `origin/stage` — never tested on stage. Do not promote.
  - ⚠️ **WARNING**: File exists on both but content differs. Stage soak
    (new data source, whole-system migration) is expected; do not block if
    the author is promoting a subset.
  - 💡 **INFO**: Blobs match stage (clean promotion).
                                                                                                                 
  Red flags:                                                                                                     
  - IF environment == 'prod' THEN ... (logic should be consistent)                                               
  - Table names like dwh_stage.sales (should use variables)
  - Airflow connections hardcoded in DAG code
  - **New runtime files on a master PR that do not exist on stage**
    (never ran there). Content diffs vs stage are a warning only.                                                                    
                                                                                                                 
  Example issues to flag:                                                                                        
  # BAD: Environment-specific table names                                                                        
  table = "dwh_stage.sales" if ENV == "stage" else "dwh.sales"                                                   
                                                                                                                 
  # GOOD: Use Airflow variables                                                                                  
  table = "{{ var.value.dwh_schema }}.sales"                                                                     
                                                                                                                 
  # BAD: Hardcoded connection                                                                                    
  conn = "snowflake_prod_connection"                                                                             
                                                                                                                 
  # GOOD: Use connection ID from variables                                                                       
  conn = "{{ var.value.snowflake_connection }}"                                                                  
                                                                                                                 
  ## Phase 3: Generate Review Report                                                                                
                                                                                                                 
  Structure the output as markdown for GitHub:                                                                   
                                                                                                                 
  ## 🤖 AI Code Review                                                                                           
                                                                                                                 
  **Reviewer**: PR Review Checker                                                                                
  **Reviewed at**: <timestamp>                                                                                   
                                                                                                                 
  ---                                                                                                            
                                                                                                                 
  ### ✅ Correctness & Safety                                                                                    
                  
  <List of findings with severity emoji>                                                                         
                  
  **Example:**                                                                                                   
  🔴 **CRITICAL** - `tasks/load_sales.sql:15`
  ```sql                                                                                                         
  DELETE FROM dwh.sales WHERE date >= '2024-01-01'
  Issue: Hardcoded date will delete increasingly more data over time                                             
  Suggestion: Use WHERE date = '{{ ds }}' to delete only today's partition
  ```

  ---                                                                                                            
  ⚠️  Maintainability
                                                                                                                 
  Example:        
  ⚠️  DUPLICATION - dags/retail_sales.py:45-67 + dags/retail_inventory.py:45-67                                   
                                                                                                                 
  Both DAGs have identical data validation logic.                                                                
  Suggestion: Extract to utils/validators.py as a shared function                                                
                                                                                                                 
  ---             
  💡 Consistency & Standards                                                                                     
                                                                                                                 
  Example:
  💡 NAMING - dags/new_retail_pipeline.py                                                                        
                                                                                                                 
  DAG ID uses hyphens: retail-pipeline-new                                                                       
  Existing retail DAGs use underscores: retail_sales_daily, retail_inventory_daily                               
  Suggestion: Rename to retail_pipeline_new for consistency                                                      
                                                                                                                 
  ---                                                                                                            
  ### 🚀 Promotion Readiness                                                                                         
                                                                                                                 
  Example:
  ✅ GOOD: No hardcoded environment values detected                                                              
  ✅ GOOD: All configs externalized to Airflow variables
  
  **Stage Branch Check** (for master PRs):
  🔴 **CRITICAL** - Files not in stage branch:
  - `dags/tran-new-pipeline.py` - New file added directly to master
  - `scripts/tran/new_logic.sql` - SQL script missing from stage
  
  ⚠️ **WARNING** - Significant differences from stage:
  - `dags/existing-pipeline.py:45` - Logic differs from stage version
  
  💡 **Recommendation**: Deploy to stage first, validate there, then promote to master                                                         
                                                                                                                 
  ---                                                                                                            
  Summary                                                                                                        
                                                                                                                 
  ┌─────────────────────────┬─────────────┬─────────────┬────────────────┐
  │        Category         │ Critical 🔴 │ Warnings ⚠️  │ Suggestions 💡 │                                       
  ├─────────────────────────┼─────────────┼─────────────┼────────────────┤                                       
  │ Correctness & Safety    │ 1           │ 2           │ 0              │                                       
  ├─────────────────────────┼─────────────┼─────────────┼────────────────┤                                       
  │ Maintainability         │ 0           │ 1           │ 1              │                                       
  ├─────────────────────────┼─────────────┼─────────────┼────────────────┤                                       
  │ Consistency & Standards │ 0           │ 0           │ 2              │                                       
  ├─────────────────────────┼─────────────┼─────────────┼────────────────┤                                       
  │ Promotion Readiness     │ 0           │ 0           │ 0              │
  ├─────────────────────────┼─────────────┼─────────────┼────────────────┤                                       
  │ Total                   │ 1           │ 3           │ 3              │
  └─────────────────────────┴─────────────┴─────────────┴────────────────┘                                       
                  
  🎯 Recommendation                                                                                              
                  
  <1-2 sentence summary>                                                                                         
                  
  Examples:                                                                                                      
  - REQUEST CHANGES: Fix the critical data deletion issue in load_sales.sql before merging.
  - APPROVE WITH COMMENTS: No blocking issues. Consider addressing the duplication and naming suggestions in a   
  follow-up PR.                                                                                               
  - APPROVED: All checks passed. Code follows standards and is safe to merge.                                    
                  
  ---                                                                                                            
  Automated review by PR Review Checker. Please verify critical findings manually.
                                                                                                                 
  ## Phase 4: Post Review Comment

  **Before posting**, show the full review report to the user and ask:
  > "Ready to post this review to PR #<number>? (yes/no)"

  Only proceed with the `gh pr comment` command after explicit confirmation.

  Execute in single response after confirmation:                                                                                    
                                                                                                                 
  ```bash                                                                                                        
  # Post the review as a PR comment
  gh pr comment <pr-number> --body "$(cat <<'EOF'                                                                
  <full review report markdown>                                                                                  
  EOF                                                                                                            
  )"
  ```

  Return confirmation message:                                                                                   
  ✅ Review posted to PR #<number>
  🔗 <PR URL>                                                                                                    
                                                                                                                 
  Summary: <count> critical, <count> warnings, <count> suggestions                                               
                                                                                                                 
  ## Key Rules                                                                                                      
                                                                                                                 
  1. **Always load documentation first** - Read `CLAUDE.md` + `airflow_etl/CLAUDE.md` before analyzing code
  2. **Ask before posting** - Show the review to the user first and ask for confirmation before running `gh pr comment`                                        
  3. **Verify stage deployment** - For master PRs, check if changes exist in stage branch first
  4. **Line-specific feedback** - Cite file:line_number for every issue                                              
  5. **Actionable suggestions** - Not just "this is wrong", show the fix                                             
  6. **Code blocks** - Use triple backticks with language for code examples                                          
  7. **Severity levels**:
    - 🔴 CRITICAL: Data safety risks, deployment order violations, must fix before merge
    - ⚠️ WARNING: Maintainability issues, should fix before merge
    - 💡 SUGGESTION: Nice-to-have improvements, can defer to follow-up
  8. **Context-aware** - Compare against existing patterns in the codebase
  9. **Concise** - Each finding should be 2-3 sentences max
  10. **Focus on impact** - Explain WHY something is risky, not just WHAT is wrong                                    
                                                                                                                 
  What NOT to Review                                                                                             
                                                                                                                 
  - PR body formatting (that's commit-push-pr's job)                                                             
  - Code style/formatting if linters pass (trust pre-commit hooks)
  - Personal preference issues (tabs vs spaces, bracket placement)                                               
  - Minor performance optimizations (unless obvious N+1 or full table scan)                                      
                                                                                                                 
  Error Handling                                                                                                 
                                                                                                                 
  PR not found:                                                                                                  
  gh pr view <pr-number> 2>&1
  # If exits with error, return:                                                                                 
  "❌ PR #<number> not found. Please check the PR number and try again."                                         
                                                                                                                 
  Large diff (>50 files or >1000 lines):                                                                         
  - Focus review on high-risk files: SQL, DAG definitions, backfill scripts                                      
  - Add note in review:                                                                                          
  ⚠️  Large PR detected (X files, Y lines). Review focused on high-risk areas.                                    
  Consider splitting future changes into smaller PRs for easier review.                                          
                                                                                                                 
  No issues found:                                                                                               
  ## 🤖 AI Code Review                                                                                           
                                                                                                                 
  ✅ **All checks passed!**                                                                                      
                                                                                                                 
  No critical issues, warnings, or major suggestions found.                                                      
                                                                                                                 
  ### Summary     
  - Code follows data engineering standards                                                                      
  - No safety risks detected               
  - Consistent with existing patterns                                                                            
  - Ready for promotion to prod                                                                                  
                                                                                                                 
  **Recommendation**: APPROVED                                                                                   
                                                                                                                 
  ---                                                                                                            
  *Automated review by PR Review Checker*                                                                        
                                         
  Optimization Tips                                                                                              
                                                                                                                 
  Parallel analysis:                                                                                             
  When analyzing multiple files, group checks by type and run them conceptually in parallel:                     
  1. All safety checks across all files                                                                          
  2. All duplication checks across all files                                                                     
  3. All naming checks across all files                                                                          
  4. All promotion readiness checks across all files                                                             
                                                                                                                 
  This provides a holistic view rather than file-by-file review.                                                 
                                                                                                                 
  Pattern detection:                                                                                             
  Use grep/find to detect patterns across the codebase:                                                          
  # Find similar DAG structures                                                                                  
  find dags/ -type f -name "*.py" -exec grep -l "PythonOperator" {} \; 2>/dev/null                               
                                                                                                                 
  # Find table naming patterns                                                                                   
  grep -r "dwh\." tasks/ --include="*.sql" 2>/dev/null | cut -d: -f2 | sort -u                                   
                                                                                                                 
  # Find existing validation patterns                                                                            
  grep -r "def validate" utils/ dags/ --include="*.py" 2>/dev/null                                               
                                                                                                                 
  Context Awareness                                                                                              
                                                                                                                 
  This skill is optimized for data engineering workflows:                                                        
  - Airflow DAGs (Python)                                                                                        
  - SQL transformations (dbt, raw SQL, Jinja templates)                                                          
  - DWH table operations (Snowflake, BigQuery, Redshift)
  - ETL/ELT pipelines                                                                                            
                                                                                                                 
  File type priorities:                                                                                          
  1. High risk (review thoroughly): SQL files, backfill scripts, DELETE/TRUNCATE operations                      
  2. Medium risk (review structure): DAG definitions, data validation logic                                      
  3. Low risk (quick scan): Config files, utility functions                                                      
                                                                                                                 
  Adjust for other domains:                                                                                      
  If reviewing non-data-engineering PRs:                                                                         
  - Web apps: Check for XSS, SQL injection, auth bypass                                                          
  - APIs: Check for breaking changes, backwards compatibility                                                    
  - Infrastructure: Check for resource limits, rollback plans 
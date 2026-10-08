# Promoting the canary suite to production

**Status: done, except images.** PR #139 (`feat/canary-suite-prod-phase1`: RBAC, cross-tier,
alerting) and PR #141 (`feat/canary-suite-prod-phase2`: s3, secrets, scaling) merged to `master`
on 2026-08-04. RBAC, cross-tier-denied, alerting, s3, secrets, and scaling canaries are all on
`master` now and run against `airflow3-prod` the same way the stage originals run against
`airflow3-stage`. `canary_stage_secret_tier0`/`tier1` were renamed to `canary_secret_tier0`/
`tier1` in the port (no more `stage_` in the prod name).

**Outstanding: `canary_images_tier0`/`tier1`.** Still stage-only — not on `master`. Before
porting:
- The PROD section of `dags/config.yaml` was deliberately left with the old `-amd64` image tags
  when PR #92/#106 fixed STAGE (prod wasn't deployed yet, so this was treated as a later
  app-version bump, not urgent). Fix PROD's image tags first.
- Confirm prod worker nodes are actually arm64/Graviton like stage — don't assume the
  architecture carries over.

Once those two are addressed, port `canary_images_tier0`/`tier1` the same way the other tiers
were ported in #139/#141, and this file's status line can drop the "except images" caveat.

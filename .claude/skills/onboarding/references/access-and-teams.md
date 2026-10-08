# Access & team model: AD, Teleport, Airflow, GitHub, AWS IAM

There are **five teams**, and each one shows up under a similar (but not identical) name in five
different systems. This doc is the map between them, and the rules for who should hold which
team's role. For the Teleport→Airflow *mechanics* (the actual config that turns a Teleport role
into Airflow permissions), see `dev_tools/deploy_airflow3_env/reference.md`
(*Teleport → Airflow role mapping*) — this doc covers the org/identity side, that one covers the
implementation.

## The five teams, across systems

Same group of people, different name per system:

| Team                     | AD role                              | Teleport role              | Airflow role                | GitHub team          | AWS IAM role                            |
|--------------------------|---------------------------------------|-----------------------------|------------------------------|-----------------------|-------------------------------------------|
| Data Tooling             | `[Teleport] data-tooling`             | `data-tooling`               | `data-tooling`                | `Data Tooling`         | `data-tooling-developer`                   |
| Data Products            | `[Teleport] data-products`            | `data-products`              | `data-products`               | `Data Products`        | `data-products-developer`                  |
| Data Compliance          | `[Teleport] data-compliance`          | `data-compliance`            | `data-compliance`             | `Data Compliance`      | `data-compliance-developer`                |
| Data Analytics Platform  | `[Teleport] data-analytics-platform`  | `data-analytics-platform`    | `data-analytics-platform`     | `Data Analytics`       | `data-analytics-platform-developer`        |
| Data SWE                 | `[Teleport] data-swe`                 | `data-swe`                   | `data-swe`                    | `Data SWE`             | `data-swe-developer`                       |

Don't assume the strings line up 1:1 when auditing access (e.g. AD's `[Teleport] data-products`
vs. GitHub's `Data Products`) — match by team, not by literal name.

These same five names are also the CODEOWNERS-facing GitHub teams (`@superbet-group/data-tooling`
etc.) and the Airflow DAG areas under `airflow_etl/dags/` — see `.github/CODEOWNERS` and
`airflow_etl/CLAUDE.md`.

## Who should hold which role (reporting-line rules)

- **data-tooling** — direct reports of **Nikola Kljajo**.
- **data-products** — anyone (direct or indirect report) under **Richard Wartell**, *except*
  those who are also under Nikola Kljajo or Isak Kazazic (org overlap — those two take priority).
- **data-compliance** — direct reports of **Colin Millar**.
- **data-analytics-platform** — anyone under **Isak Kazazic**, at any depth (not just direct
  reports).
- **data-swe** — open to anyone in product & tech, but **not granted by default** — it's opt-in
  even for eligible people; someone has to ask for it.

These rules govern AD role assignment; everything downstream (Teleport, IAM, Airflow) should
follow from the AD role per the sync rules below. GitHub team membership is the one exception —
see below.

## How the systems sync — and where they don't

1. **AD → Teleport**: expected, but not guaranteed to happen automatically. If someone has the AD
   role but not the matching Teleport role, they request it via the **IT Support Slack workflow**
   — routed according to the reporting-line rules above.
2. **Teleport → AWS IAM**: automatic. Holding a Teleport role gives access to that team's IAM role
   on the `aws-data-prod` and `aws-data-stage` accounts, via the Teleport app (not directly through
   the AWS console). This is the **go-to path for setting secrets** in those accounts.
3. **Teleport → Airflow**: automatic. Teleport roles map to Airflow (FAB) roles via
   `TELEPORT_ROLE_TO_AIRFLOW_ROLES` in `webserver_config.py` (mechanics in
   `dev_tools/deploy_airflow3_env/reference.md`). An Airflow role grants **edit** access to that
   team's own DAGs, but **view** access to every DAG in the org.
4. **Teleport/Airflow → GitHub**: **not automatic** — the one manual step. Someone has to be added
   to the GitHub team by that team's maintainer (the team's manager, tech lead, or similar).
   GitHub team membership is what CODEOWNERS uses (`.github/CODEOWNERS`), so it gates PR edit /
   review rights per functional area — a separate axis from Airflow UI edit rights in (3).

## Caveats

- The reporting-line rules describe who *should* get a role; nothing in this repo enforces that
  end-to-end. The AD→Teleport gap is the known weak link, closed manually via the IT Support Slack
  workflow.
- `data-swe` is opt-in — eligibility (being in product & tech) does not imply the role is held.
- This doc will drift as org structure changes (managers, team names). If you're relying on it for
  an access decision, confirm the reporting line is still current before acting on it.

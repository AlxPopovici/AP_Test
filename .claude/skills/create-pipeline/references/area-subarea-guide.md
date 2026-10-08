# Area / sub-area placement guide

The five top-level areas under `airflow_etl/dags/` are fixed and tooling-owned — don't add
or rename one. Sub-areas are team-owned, free to create or drop, and should always be named
by **business domain**, never by team (teams reorganize; domains don't).

## Access maps to area, not sub-area

The five areas are also the five team boundaries for Teleport roles, Airflow edit rights,
and GitHub (CODEOWNERS) teams — see the full AD/Teleport/Airflow/GitHub/AWS IAM mapping in
`.claude/skills/onboarding/references/access-and-teams.md`. In practice this means the area
a new pipeline lands in is usually whichever one matches the developer's own Teleport
role/GitHub team, since that's where they can actually get a PR reviewed and merged. The
**sub-area** underneath is still chosen by business domain, not team — the two questions
are independent.

## The five areas

| Area | Covers |
|---|---|
| `analytics_platform` | DWH, reporting, gaming, sport, retail, finance, social, player |
| `data_products` | ML, personalization, martech, experimentation, data science |
| `compliance` | Regulatory, AML, responsible gambling, fraud |
| `swe` | App-specific pipelines: gaming, sport, retail, social, player |
| `data_tooling` | Platform infrastructure, shared utilities (tooling team) |

## Current sub-areas per area

Snapshot for orientation — always confirm with `ls airflow_etl/dags/<area>/` since teams add
and drop sub-areas as needed.

- **analytics_platform**: `app_analytics`, `commercial`, `crm`, `customer_support`,
  `data_quality`, `exchange_rates`, `finance`, `gaming`, `lucky7`, `player`, `retail`,
  `shared`, `social`, `sport`
- **data_products**: `data_science`, `experimentation`, `martech`, `ml`, `personalization`
- **compliance**: `aml`, `fraud`, `regulatory`, `responsible_gambling`
- **swe**: `gaming`, `player`, `retail`, `social`, `sport`
- **data_tooling**: `acryl`, `blueprint` (see
  [warehouse-tier-advanced.md](warehouse-tier-advanced.md))

## Picking or creating a sub-area

1. Ask what business domain the pipeline serves (what it's *about*, not who currently
   maintains it) — e.g. a wallet/payments pipeline is `player` or a `payments` sub-area, not
   `dp-player-wallet-squad`.
2. Check if an existing sub-area already fits. Reuse it — don't fragment a domain across two
   near-identical folders.
3. If none fits, create a new one named after the domain. It's low-friction: the sub-area
   list above is "what's likely to live there today," not a fixed set.
4. If genuinely unsure between two domains, ask the developer rather than guessing — the same
   rule `rewrite-tags` follows for the `owner` tag applies here: a wrong placement is more
   costly to unwind later than a short question now.

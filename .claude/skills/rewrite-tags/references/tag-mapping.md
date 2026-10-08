# Tag mapping reference

Old-tag → new-tag lookup for Step 2 of the `rewrite-tags` workflow. Derived from tag frequency
across `data.airflow.dags` — not exhaustive, extend as needed. For anything not listed here,
grep for the tag's usage and confirm the mapping with the user before committing to it (see
SKILL.md Step 2).

| Old tag(s) | New tag |
|---|---|
| `dp-player-wallet` | `owner:dp-player-wallet` |
| `martech` | `owner:martech` |
| `crmSquad`, `crm` | `owner:crm` |
| `crmCritical` | **not an ownership tag** — always co-occurs with `crmSquad`, and flags priority/criticality, not the owner. Mapping it to `owner` would silently discard that signal. Ask whether to drop it or keep it as a freeform tag (e.g. `priority:critical`) |
| `player` (when it's the owner, not the business area) | `owner:player` |
| `sport` (owner context) | `owner:sport` |
| `gaming` (owner context) | `owner:gaming` |
| `dp-gaming`, `di-gaming` | distinct from the `dm_gaming` datamart schema tag below (never co-occur with it) — likely separate owners ("Data Products"/"Data Integration" gaming). Ask before assuming they're synonyms; propose `owner:dp-gaming` / `owner:di-gaming` respectively |
| `social` (owner context) | `owner:social` |
| `ex-retail-squad` | `owner:ex-retail-squad` |
| `retail-sport` | almost always co-occurs with `ex-retail-squad` — once `owner:ex-retail-squad` is set this is usually redundant; propose dropping, or `business_area:retail-sport` if the user wants to keep the distinction |
| `data-science` | `owner:data-science` |
| `dwh` (when identifying the owning team, not the data warehouse schema) | `owner:dwh` |
| `dataops`, `data-tooling` | `owner:data-tooling` |
| `sb_ro`, `sb_pl`, `sb_br`, `sb_rs`, `sb_gr`, `ng_be`, `ng_ro` | `markets:<value>` (comma-join if several appear on one DAG) |
| `all_markets` | `markets:all` — confirm the exact literal with the user |
| `romania`, `online`, `retail` used as a market qualifier | ask — usually resolves to one of the `sb_*`/`ng_*` codes above, don't guess which |
| `snowflake` | usually redundant (every pipeline here touches Snowflake) — drop unless it's genuinely the *source* system, then `source_system:snowflake` |
| `s3` | `source_system:s3` (or drop if S3 is an intermediate export target, not the source — check the DAG) |
| `external_db (MSSQL server)`, `mssql` | `source_system:mssql` |
| `external_db (MySQL)` | `source_system:mysql` |
| `clickhouse` | `source_system:clickhouse` |
| `sftp`, `sftp-to-s3-connector` | `source_system:sftp` |
| `google-api`, `google` | `source_system:google` |
| `nsoft`, `nuvei`, `zendesk`, `income_access`, `income-access`, `lucky7`, `betler` | `source_system:<same-name>` |
| `api` | `source_system:api` — only if it's genuinely the ingestion source; otherwise drop |
| `external-db-loader`, `external-db-sync` | `component:<same-name>` |
| `custom_report`, `s3export`, `feast-feature-store`, `data_migration`, `reconciliation` | `component:<same-name>` |
| `ods_igp_dwh_ro`, `ods_payment`, `ods_smdc_ro`, `ods_igp_ro`, any `ods_*`/`raw_*` schema name | `source_schema:<schema>` |
| `dm_martech`, `dm_crm`, `dm_player`, `dm_sport`, `dm_gaming`, `dm_social`, any `dm_*` schema name | `source_schema:<schema>` — `dm_` marks a **datamart schema name**, not the owner, even though it can look like an owner name (e.g. `dm_crm` next to `crmSquad`). Never map a `dm_*` tag to `owner` |
| `dwh` (schema context — the data warehouse schema itself) | `source_schema:dwh` — same ambiguity as `dm_*`: don't map to `owner` when `dwh` is naming the schema being read from, not the owning team |
| schema names matching a DWH/mart target (e.g. `dpsp`, `dpsb` if confirmed as schemas, not owners) | `destination_schema:<schema>` — confirm which side before mapping |
| `social`, `sports`/`sport`, `gaming`, `retail`, `crm`, `player` used as a domain descriptor rather than the owner | `business_area:<same-name>` |
| `etl`, `transformation`, `ingestion`, `ing`, `tran`, `daily`, `monthly`, `daily-load`, `prod`, `test`, `v2`, `dc`, `comp` | generic/noise — propose **dropping**, don't force into a key |
| `k8s` | no clean key (it's compute, not a source/owner/market) — propose dropping unless the user wants a `component:k8s` |

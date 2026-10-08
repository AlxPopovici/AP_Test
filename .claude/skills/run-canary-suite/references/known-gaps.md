# Known pre-existing gaps

Recognize these rather than re-diagnosing them as new bugs when writing the Step 7 report.

- **S3 canaries failing on some buckets** — the legacy-account (`483222828597`)
  bucket-policy grants for the tier worker roles are applied bucket-by-bucket by hand;
  a partial failure usually means a bucket that hasn't gotten its grant yet, not a
  regression (see the `legacy-s3-buckets-cross-account` memory). This gap has been
  standing since the canary's introduction, which means a *new* regression on the one
  bucket that currently passes (`raw`) is easy to miss if you only skim for "still 3 of
  4 failing" — diff the specific failing task set against last run's, don't just count.
- **Images canary failing on an amd64-only image** — as of PR #107 the image list is
  resolved live from `dags/config.yaml` via `get_config()` (no more DAG-local copy that
  could silently drift), so a failure here now means the image key in `config.yaml`
  itself still points at (or regressed to) a non-multi-arch tag — treat it as current
  and real, not a known-stale artifact. Also worth remembering what this canary does
  *not* prove: the probe overrides the entrypoint with `echo pulled ok`, so it only
  proves the image pulls and has a shell — a subtly broken arm64 build of an image
  (e.g. missing a native dependency the real entrypoint needs) would still pass.
- **Secrets canaries failing on `read_tooling_secret` / `read_experimentation_secret`**
  — see the Secrets note in `canary-catalog.md`; check whether it's `CANARY READ FAILED`
  (missing IRSA grant) or `CANARY MISCONFIGURED` (secret doesn't exist yet under the
  `stage/` prefix) before treating it as an isolation bug.
- **No tier-1 → tier-0 equivalent of `canary_cross_tier_denied_tier0`** — the suite only
  tests that a tier-0 (data_tooling) task can't launch a pod into tier-1's namespace.
  There's no counterpart proving tier-1 can't reach tier-0. Don't report cross-tier pod
  isolation as fully verified from this suite; it's verified in one direction only.

# repcheck-db-migrations

RepCheck Liquibase migration runner.

This repository owns the authoritative PostgreSQL schema for the RepCheck
platform and produces a Cloud Run Job Docker image that applies the changesets
against a target database: AlloyDB in staging and prod, Cloud SQL in dev, and
AlloyDB Omni (Docker) for local development and integration tests.

## What lives here

- `repcheck-db-migrations/src/main/resources/db/changelog/` — the Liquibase
  master changelog and its per-changeset SQL files (`001-initial-schema.sql`
  through `009-scoring-architecture.sql`).
- `repcheck-db-migrations/src/main/scala/repcheck/db/migrations/` —
  - `MigrationApp` — the IOApp Cloud Run entry point.
  - `MigrationRunner` — a Liquibase CommandScope wrapper used by the app and
    by downstream projects that need to apply migrations in tests.
  - `ConnectionRetry` — exponential-backoff JDBC connect used to tolerate
    AlloyDB Omni container startup ordering.
- `repcheck-db-migrations/src/test/scala/repcheck/db/migrations/` — unit tests
  (H2-backed) plus `DockerPostgresSpec`, a reusable trait that spins up an
  AlloyDB Omni container and applies migrations before each suite.
- `schema-diagram.mermaid` — the canonical ER diagram.

## Running migrations locally

Against an AlloyDB Omni container started by the votr
`docker-compose-local-dev.yml`:

```bash
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export DATABASE_NAME=repcheck
export DATABASE_USER=postgres
export DATABASE_PASSWORD=postgres
sbt "repcheckdbmigrations/run"
```

The runner retries with exponential backoff until the database is reachable,
then applies all pending changesets and exits.

## Tests

```bash
sbt test
```

Runs four specs:

- `ChangelogValidationSpec` — parses the changelog YAML and validates it
  against an in-memory H2 database. No Docker required.
- `ConnectionRetrySpec` — exercises the retry logic against H2 and a bogus
  URL. No Docker required.
- `MigrationRunnerSpec` — starts an AlloyDB Omni container and verifies every
  changeset applies cleanly. Tagged `DockerRequired` — requires a running
  Docker daemon.
- `DockerPostgresSpec` — companion trait, exercised transitively.

To skip the Docker-dependent tests locally:

```bash
sbt "testOnly -- -l DockerRequired"
```

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull
request:

1. `sbt scalafmtCheckAll` — formatting.
2. `sbt compile` — WartRemover + tpolecat gates.
3. `sbt "scalafixAll --check"` — import ordering + unused imports.
4. `sbt coverage test coverageReport` — tests with scoverage.
5. Codecov upload (patch coverage gate 90%).

The CI workers have Docker available, so `MigrationRunnerSpec` runs in full
on every PR.

## Container image

The `Dockerfile` produces a Google Distroless Java 21 image that runs
`repcheck.db.migrations.MigrationApp`. It reads connection details from
`DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, and
`DATABASE_PASSWORD`, retries the JDBC connect to survive AlloyDB startup
races, then applies pending changesets and exits.

Cloud Run Job deployment is managed out of the infrastructure repo.

## Pre-push CI checks

```bash
source scripts/ci-functions.sh
CreatePR "title" "body"    # New PRs: runs checks, pushes, creates the PR
pushToPR                    # Existing PRs: runs checks, pushes
```

Both functions run `sbt compile`, `sbt test`, `sbt scalafmtCheckAll`, and
`sbt scalafixAll --check` and abort on the first failure.

## Conventions

See `CLAUDE.md` for the full Scala style, WartRemover, testing, and branch
hygiene rules shared across all RepCheck repositories.

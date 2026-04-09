# repcheck-db-migrations

RepCheck Liquibase migration runner.

This repository owns the authoritative PostgreSQL schema for the RepCheck
platform and produces three consumable artifacts:

1. **`repcheck-db-migrations-changesets`** — a resources-only JAR containing
   the Liquibase master changelog plus every `.sql` file on the classpath.
2. **`repcheck-db-migrations-runner`** — the Scala library with
   `MigrationRunner`, `ConnectionRetry`, the typed exceptions, and the
   reusable `DockerPostgresSpec` trait. Depends on the changesets
   JAR, so consumers only need this one coordinate.
3. **Cloud Run Job Docker image** — built from the `app` subproject
   (`MigrationApp`), published to GitHub Container Registry.

The target database is AlloyDB in staging and prod, Cloud SQL in dev, and
AlloyDB Omni (Docker) for local development and integration tests.

## Subproject layout

```
repcheck-db-migrations/
  changesets/     — resources-only JAR (db/changelog/**)
  runner/         — publishable library (MigrationRunner + DockerPostgresSpec)
  app/            — IOApp entry point + Docker image (not published to Maven)
```

## Artifact coordinates

Both JARs are published to GitHub Packages on merge to `main`:

```scala
resolvers += "GitHub Packages - db-migrations" at
  "https://maven.pkg.github.com/Eligio-Taveras/repcheck-db-migrations"

libraryDependencies ++= Seq(
  "com.repcheck" %% "repcheck-db-migrations-runner"      % "<version>",
  // transitively pulls repcheck-db-migrations-changesets
)
```

The `runner` POM declares a transitive dependency on `changesets`, so most
consumers do not need to add the changesets JAR directly.

## Consuming the runner in a downstream test suite

The `runner` artifact publishes the `DockerPostgresSpec` trait in
`src/main/scala` so downstream test suites can reuse it without paying a
production dependency on scalatest — scalatest is marked `Provided`, so
consumers add it themselves to their `Test` scope.

```scala
libraryDependencies ++= Seq(
  "com.repcheck" %% "repcheck-db-migrations-runner" % "<version>" % Test,
  "org.scalatest" %% "scalatest"                    % "3.2.18"    % Test
)
```

```scala
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import repcheck.db.migrations.{DockerPostgresSpec, DockerRequired}

class MyRepositorySpec extends AnyFlatSpec with Matchers with DockerPostgresSpec {
  "my repo" should "query the migrated schema" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      // database already has every RepCheck migration applied
    } finally conn.close()
  }
}
```

`DockerPostgresSpec.beforeAll` starts an AlloyDB Omni container, waits for
readiness, and runs `MigrationRunner.migrate` against the fresh database.
`afterAll` removes the container.

## Consuming just the changesets JAR

If a downstream project has its own Liquibase wiring, it can depend on the
changesets JAR alone and point Liquibase at the classpath resource:

```scala
libraryDependencies += "com.repcheck" % "repcheck-db-migrations-changesets" % "<version>"
```

```scala
import liquibase.command.CommandScope
import liquibase.command.core.UpdateCommandStep
// ...
new CommandScope("update")
  .addArgumentValue(UpdateCommandStep.CHANGELOG_FILE_ARG, "db/changelog/db.changelog-master.yaml")
  // ...
```

Note: the `changesets` artifact is a plain Java JAR (no `_3` Scala suffix).

## Pulling and running the Docker image

The `app` subproject produces a Google Distroless Java 21 image that runs
`repcheck.db.migrations.MigrationApp`. It is published on tagged releases to
GitHub Container Registry:

```bash
docker pull ghcr.io/eligio-taveras/repcheck-db-migrations-runner:<version>

docker run --rm \
  -e DATABASE_HOST=... \
  -e DATABASE_PORT=5432 \
  -e DATABASE_NAME=repcheck \
  -e DATABASE_USER=... \
  -e DATABASE_PASSWORD=... \
  ghcr.io/eligio-taveras/repcheck-db-migrations-runner:<version>
```

The runner retries the JDBC connect with exponential backoff until the
database is reachable, then applies all pending changesets and exits.
Cloud Run Job deployment is managed out of the infrastructure repo.

## Running migrations locally (from source)

```bash
export DATABASE_HOST=localhost
export DATABASE_PORT=5432
export DATABASE_NAME=repcheck
export DATABASE_USER=postgres
export DATABASE_PASSWORD=postgres
sbt "app/run"
```

## Tests

```bash
sbt runner/test
```

Runs four specs (15 tests total):

- `ChangelogValidationSpec` (2) — parses the changelog YAML and validates
  it against an in-memory H2 database. No Docker required.
- `ConnectionRetrySpec` (6) — exercises the retry logic against H2 and a
  bogus URL. No Docker required.
- `MigrationRunnerSpec` (7) — starts an AlloyDB Omni container via the
  `DockerPostgresSpec` trait and verifies every changeset applies
  cleanly, every expected table exists, seed data is present, and HNSW
  vector indexes are created. Tagged `DockerRequired`.

To skip the Docker-dependent tests locally:

```bash
sbt "runner/testOnly -- -l DockerRequired"
```

## CI

`.github/workflows/ci.yml` runs on every push and pull request:

1. `sbt scalafmtCheckAll` — formatting.
2. `sbt changesets/compile runner/compile app/compile` — WartRemover +
   tpolecat gates on all three subprojects.
3. `sbt "scalafixAll --check"` — import ordering + unused imports.
4. `sbt coverage runner/test runner/coverageReport` — runner tests with
   scoverage.
5. `sbt app/Docker/stage` — validates the Dockerfile build.
6. Codecov upload (patch coverage gate 90% against `runner`).

`.github/workflows/release.yml` runs on merge to `main`: it derives the next
semver tag from the merged PR's labels (`release:major`, `release:minor`,
`release:patch`, `release:skip`), tags the commit, publishes the `changesets`
and `runner` JARs to GitHub Packages, and pushes the Docker image for `app`
to GitHub Container Registry.

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

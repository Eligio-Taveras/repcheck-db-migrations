import sbt.*
import Versions.*

object Dependencies {

  // Cats Effect
  private val catsEffectCore = "org.typelevel" %% "cats-effect" % catsEffectVersion

  val catsEffect: Seq[ModuleID] = Seq(catsEffectCore)

  // Liquibase + PostgreSQL JDBC driver (runtime classpath for MigrationRunner)
  private val liquibaseCore = "org.liquibase" % "liquibase-core" % liquibaseVersion
  private val postgresqlDriver =
    "org.postgresql" % "postgresql" % postgresqlDriverVersion

  val liquibase: Seq[ModuleID] = Seq(liquibaseCore, postgresqlDriver)

  // H2 — used by ChangelogValidationSpec / ConnectionRetrySpec for no-Docker tests
  private val h2Database = "com.h2database" % "h2" % h2Version % Test

  val h2: Seq[ModuleID] = Seq(h2Database)

  // Doobie — MigrationRunner.migrateF uses Sync[F] from cats-effect.
  // We include doobie-core for type availability matching the legacy effective
  // classpath.
  private val doobieCore     = "org.tpolecat" %% "doobie-core" % doobieVersion
  private val doobieHikari   = "org.tpolecat" %% "doobie-hikari" % doobieVersion
  private val doobiePostgres = "org.tpolecat" %% "doobie-postgres" % doobieVersion

  val doobie: Seq[ModuleID] = Seq(doobieCore, doobieHikari, doobiePostgres)

  // Logging — Liquibase uses slf4j; logback is a Test-scope runtime binding so tests
  // don't spew NOP warnings.
  private val logbackClassic = "ch.qos.logback" % "logback-classic" % logbackVersion % Test

  val logging: Seq[ModuleID] = Seq(logbackClassic)

  // Test dependencies
  private val mockitoCore = "org.mockito" % "mockito-core" % "5.8.0" % Test

  val testDeps: Seq[ModuleID] = Seq(mockitoCore)

  // ── Testkit support ────────────────────────────────────────────────────────
  //
  // The runner subproject publishes a reusable `DockerPostgresSpec` trait under
  // `repcheck.db.migrations`. Because the trait lives in `src/main/scala`
  // (so it can be consumed by downstream test suites via the published JAR),
  // scalatest must be on the Compile classpath rather than the Test classpath.
  //
  // We mark it as `Provided` so consumers must add scalatest explicitly in their
  // own test scope, avoiding a transitive production dependency.
  private val scalatestProvided =
    "org.scalatest" %% "scalatest" % scalatestVersion % Provided

  val testkitProvided: Seq[ModuleID] = Seq(scalatestProvided)
}

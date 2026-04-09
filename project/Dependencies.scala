import sbt.*
import Versions.*

object Dependencies {

  // Cats Effect
  private val catsEffectCore = "org.typelevel" %% "cats-effect" % catsEffectVersion

  val catsEffect: Seq[ModuleID] = Seq(catsEffectCore)

  // Liquibase + PostgreSQL JDBC driver
  private val liquibaseCore = "org.liquibase" % "liquibase-core" % liquibaseVersion
  private val postgresqlDriver =
    "org.postgresql" % "postgresql" % postgresqlDriverVersion

  val liquibase: Seq[ModuleID] = Seq(liquibaseCore, postgresqlDriver)

  // H2 — used by ChangelogValidationSpec / ConnectionRetrySpec for no-Docker tests
  private val h2Database = "com.h2database" % "h2" % h2Version % Test

  val h2: Seq[ModuleID] = Seq(h2Database)

  // Doobie — MigrationRunner.migrateF uses Sync[F] from cats-effect, and downstream
  // projects that depend on db-migrations in test scope via the DockerPostgresSpec trait
  // will pick up doobie transitively if they need it. db-migrations itself only needs
  // doobie-core for type availability. We include the full trio to match the votr
  // dbMigrations subproject's effective classpath.
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
}

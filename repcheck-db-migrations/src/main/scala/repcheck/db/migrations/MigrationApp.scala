package repcheck.db.migrations

import scala.concurrent.duration._

import cats.effect.{ExitCode, IO, IOApp}

/**
 * Standalone entry point for applying migrations to a database.
 *
 * Reads connection details from environment variables:
 *   - DATABASE_HOST (required)
 *   - DATABASE_PORT (default: 5432)
 *   - DATABASE_NAME (default: repcheck)
 *   - DATABASE_USER (required)
 *   - DATABASE_PASSWORD (required)
 *
 * Retries the database connection with exponential backoff to handle container startup ordering (e.g., AlloyDB Omni
 * init restarts).
 *
 * Usage: sbt "dbMigrations/run"
 */
object MigrationApp extends IOApp {

  private val maxRetries: Int              = 10
  private val initialDelay: FiniteDuration = 2.seconds

  @SuppressWarnings(Array("org.wartremover.warts.Throw"))
  override def run(args: List[String]): IO[ExitCode] = {
    val host     = sys.env.getOrElse("DATABASE_HOST", throw MissingDatabaseHostEnvVar())
    val port     = sys.env.getOrElse("DATABASE_PORT", "5432")
    val name     = sys.env.getOrElse("DATABASE_NAME", "repcheck")
    val user     = sys.env.getOrElse("DATABASE_USER", throw MissingDatabaseUserEnvVar())
    val password = sys.env.getOrElse("DATABASE_PASSWORD", throw MissingDatabasePasswordEnvVar())
    val url      = s"jdbc:postgresql://$host:$port/$name"

    ConnectionRetry
      .connectWithRetry(url, user, password, maxRetries, initialDelay)
      .flatMap { connection =>
        IO.blocking {
          try {
            val pending = MigrationRunner.pendingCount(connection)
            println(s"Applying $pending pending migration(s) to $url ...")
            MigrationRunner.migrate(connection)
            println("Migrations completed successfully.")
          } finally connection.close()
        }
      }
      .as(ExitCode.Success)
  }

}

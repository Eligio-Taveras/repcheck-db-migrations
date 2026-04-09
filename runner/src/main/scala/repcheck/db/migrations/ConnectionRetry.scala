package repcheck.db.migrations

import java.sql.{Connection, DriverManager}

import scala.concurrent.duration._

import cats.effect.IO

/**
 * Provides connection-with-retry logic for database startup race conditions.
 *
 * Extracted from MigrationApp so it can be independently tested (MigrationApp itself is excluded from coverage as a
 * wiring-only IOApp entry point).
 */
object ConnectionRetry {

  /**
   * Attempt to connect to a database, retrying with exponential backoff on failure.
   *
   * @param url
   *   JDBC connection URL
   * @param user
   *   database user
   * @param password
   *   database password
   * @param retriesLeft
   *   number of retries remaining before giving up
   * @param delay
   *   current delay before next retry (doubles each attempt, capped at 30s)
   * @return
   *   an IO that produces a JDBC Connection
   */
  def connectWithRetry(
    url: String,
    user: String,
    password: String,
    retriesLeft: Int,
    delay: FiniteDuration,
  ): IO[Connection] =
    IO.blocking(DriverManager.getConnection(url, user, password)).handleErrorWith { error =>
      if (retriesLeft <= 0) {
        IO.raiseError(error)
      } else {
        IO.println(
          s"Database not ready, retrying in ${delay.toSeconds}s ($retriesLeft retries left): ${error.getMessage}"
        ) *>
          IO.sleep(delay) *>
          connectWithRetry(url, user, password, retriesLeft - 1, (delay * 2).min(30.seconds))
      }
    }

}

/**
 * Flat, unique exceptions for missing environment variables.
 *
 * RepCheck's exception-uniqueness rule requires that each project `Throwable` be thrown from at most one site. The
 * original `MissingEnvVar(name: String)` was thrown from three distinct call sites in `MigrationApp`, which violated
 * the rule. The retained `MissingEnvVar` case class (still used in tests and for downstream convenience) is no longer
 * thrown directly — each required env var has its own dedicated exception below.
 */
final case class MissingEnvVar(name: String) extends Exception(s"Required environment variable '$name' is not set")

final case class MissingDatabaseHostEnvVar()
    extends Exception("Required environment variable 'DATABASE_HOST' is not set")

final case class MissingDatabaseUserEnvVar()
    extends Exception("Required environment variable 'DATABASE_USER' is not set")

final case class MissingDatabasePasswordEnvVar()
    extends Exception("Required environment variable 'DATABASE_PASSWORD' is not set")

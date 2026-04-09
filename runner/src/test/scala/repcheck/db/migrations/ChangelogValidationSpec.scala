package repcheck.db.migrations

import java.sql.DriverManager

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

/**
 * Validates the Liquibase changelog structure without requiring Docker.
 *
 * Uses an in-memory H2 database to verify that:
 *   - The changelog YAML is parseable
 *   - All referenced SQL files exist on the classpath
 *   - Changeset IDs are valid and non-duplicate
 *
 * This does NOT execute the PostgreSQL-specific SQL (pgvector, TEXT[], etc.) — that validation requires the full
 * Testcontainers-based MigrationRunnerSpec with a real PostgreSQL instance.
 */
class ChangelogValidationSpec extends AnyFlatSpec with Matchers {

  private def withH2Connection[A](f: java.sql.Connection => A): A = {
    val conn = DriverManager.getConnection("jdbc:h2:mem:validation;DB_CLOSE_DELAY=-1", "sa", "")
    try
      f(conn)
    finally
      conn.close()
  }

  "Liquibase changelog" should "pass validation (parseable YAML, valid references, no duplicate IDs)" in {
    withH2Connection(conn => MigrationRunner.validate(conn))
  }

  it should "report pending changesets against an empty database" in {
    withH2Connection { conn =>
      val pending = MigrationRunner.pendingCount(conn)
      pending should be > 0
    }
  }

}

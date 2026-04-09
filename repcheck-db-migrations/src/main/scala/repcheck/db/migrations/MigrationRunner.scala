package repcheck.db.migrations

import java.sql.Connection
import java.util

import cats.effect.Sync

import liquibase.Scope
import liquibase.changelog.ChangeLogParameters
import liquibase.command.CommandScope
import liquibase.command.core.UpdateCommandStep
import liquibase.command.core.helpers.DbUrlConnectionArgumentsCommandStep
import liquibase.database.DatabaseFactory
import liquibase.database.jvm.JdbcConnection
import liquibase.parser.ChangeLogParserFactory
import liquibase.resource.ClassLoaderResourceAccessor

/**
 * Runs Liquibase migrations against a JDBC connection.
 *
 * Used in two contexts:
 *   1. Standalone migration tool: apply migrations to Cloud SQL / AlloyDB 2. Test setup: other projects depend on
 *      db-migrations and call MigrationRunner.migrate() to initialize a Testcontainers PostgreSQL database before
 *      running integration tests.
 *
 * Uses the CommandScope API (non-deprecated) rather than the legacy Liquibase class methods.
 */
object MigrationRunner {

  private val ChangelogPath = "db/changelog/db.changelog-master.yaml"

  private def withDatabase[A](connection: Connection)(f: liquibase.database.Database => A): A = {
    val database = DatabaseFactory
      .getInstance()
      .findCorrectDatabaseImplementation(new JdbcConnection(connection))
    val resourceAccessor = new ClassLoaderResourceAccessor()
    val scopeValues      = new util.HashMap[String, Object]()
    scopeValues.put(Scope.Attr.resourceAccessor.name(), resourceAccessor)
    Scope.child(
      scopeValues,
      new Scope.ScopedRunnerWithReturn[A] {
        override def run(): A = f(database)
      },
    )
  }

  /**
   * Apply all pending migrations to the given JDBC connection.
   *
   * @param connection
   *   a JDBC connection to the target database
   */
  def migrate(connection: Connection): Unit = {
    val _ = withDatabase(connection) { database =>
      new CommandScope("update")
        .addArgumentValue(UpdateCommandStep.CHANGELOG_FILE_ARG, ChangelogPath)
        .addArgumentValue(DbUrlConnectionArgumentsCommandStep.DATABASE_ARG, database)
        .execute()
    }
  }

  /**
   * Apply all pending migrations, wrapped in F[_] for use in Cats Effect apps.
   *
   * @param connection
   *   a JDBC connection to the target database
   */
  def migrateF[F[_]: Sync](connection: Connection): F[Unit] =
    Sync[F].blocking(migrate(connection))

  /**
   * Validate that all changesets are valid without applying them.
   *
   * @param connection
   *   a JDBC connection to the target database
   */
  def validate(connection: Connection): Unit = {
    val _ = withDatabase(connection) { database =>
      new CommandScope("validate")
        .addArgumentValue(UpdateCommandStep.CHANGELOG_FILE_ARG, ChangelogPath)
        .addArgumentValue(DbUrlConnectionArgumentsCommandStep.DATABASE_ARG, database)
        .execute()
    }
  }

  /**
   * Get the count of pending (unapplied) changesets.
   *
   * Uses the changelog parser to count total changesets and queries Liquibase's databasechangelog tracking table
   * directly to count applied changesets, avoiding deprecated ChangeLogHistoryServiceFactory.getInstance().
   *
   * @param connection
   *   a JDBC connection to the target database
   * @return
   *   number of changesets not yet applied
   */
  def pendingCount(connection: Connection): Int =
    withDatabase(connection) { database =>
      val resourceAccessor = new ClassLoaderResourceAccessor()
      val parser           = ChangeLogParserFactory.getInstance().getParser(ChangelogPath, resourceAccessor)
      val changeLog        = parser.parse(ChangelogPath, new ChangeLogParameters(database), resourceAccessor)
      val totalChangeSets  = changeLog.getChangeSets.size()
      totalChangeSets - countAppliedChangeSets(connection)
    }

  private def countAppliedChangeSets(connection: Connection): Int = {
    val stmt = connection.createStatement()
    try {
      // Check if the tracking table exists before querying it — avoids aborting
      // the PostgreSQL transaction with a query against a non-existent table.
      val existsRs = stmt.executeQuery(
        """SELECT 1 FROM information_schema.tables
          |WHERE table_name = 'databasechangelog'""".stripMargin
      )
      val tableExists = existsRs.next()
      existsRs.close()

      if (tableExists) {
        val rs = stmt.executeQuery("SELECT COUNT(*) FROM databasechangelog")
        try
          if (rs.next()) { rs.getInt(1) }
          else { 0 }
        finally
          rs.close()
      } else {
        0
      }
    } catch {
      case _: java.sql.SQLException => 0
    } finally stmt.close()
  }

}

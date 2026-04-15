package repcheck.db.migrations

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

/**
 * Verifies that all Liquibase migrations apply cleanly to a real pgvector PostgreSQL 16 database.
 *
 * Uses DockerPostgresSpec to manage the container lifecycle. Migrations are applied once in beforeAll; individual tests
 * verify the resulting schema state.
 *
 * Run with: sbt "dbMigrations/testOnly -- -n DockerRequired" Exclude: sbt "dbMigrations/testOnly -- -l DockerRequired"
 */
class MigrationRunnerSpec extends AnyFlatSpec with Matchers with DockerPostgresSpec {

  "MigrationRunner.migrate" should "apply all migrations to an empty database" taggedAs DockerRequired in {
    // Migrations already applied by DockerPostgresSpec.beforeAll — verify no exception was thrown
    // and the database is in a valid state by checking a basic query.
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs   = stmt.executeQuery("SELECT 1")
      val _    = rs.next() shouldBe true
      rs.close()
      stmt.close()
    } finally conn.close()
  }

  it should "be idempotent — running twice causes no errors" taggedAs DockerRequired in {
    val conn = getConnection
    try
      // First run happened in beforeAll. This is the second run — should be a no-op.
      MigrationRunner.migrate(conn)
    finally conn.close()
  }

  it should "report zero pending changesets after migration" taggedAs DockerRequired in {
    val conn = getConnection
    try
      MigrationRunner.pendingCount(conn) shouldBe 0
    finally conn.close()
  }

  it should "create all expected tables" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val expectedTables = Set(
        // Migration 001 — initial schema (29 tables)
        "us_states",
        "members",
        "member_terms",
        "member_party_history",
        "bills",
        "bill_cosponsors",
        "bill_subjects",
        "votes",
        "vote_positions",
        "vote_history",
        "vote_history_positions",
        "amendments",
        "amendment_findings",
        "bill_analyses",
        "finding_types",
        "bill_findings",
        "users",
        "user_preferences",
        "member_bill_stances",
        "scores",
        "score_topics",
        "score_congress",
        "score_congress_topics",
        "score_history",
        "score_history_congress",
        "score_history_congress_topics",
        "score_history_highlights",
        "processing_results",
        // Migration 002 — schema expansion (13 new tables)
        "bill_text_versions",
        "lis_members",
        "member_lis_mapping",
        "committees",
        "committee_members",
        "bill_committee_referrals",
        "member_history",
        "member_term_history",
        "bill_history",
        "bill_cosponsor_history",
        "bill_subject_history",
        "workflow_runs",
        "workflow_run_steps",
        "bill_concept_summaries",
        "bill_analysis_topics",
        "bill_fiscal_estimates",
        // Migration 003 — text sections & concept groups (3 new tables)
        "bill_text_sections",
        "bill_concept_groups",
        "bill_concept_group_sections",
        // Migration 004 — question bank (4 new tables)
        "qa_questions",
        "qa_question_topics",
        "qa_answer_options",
        "qa_user_responses",
      )

      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT table_name FROM information_schema.tables
          |WHERE table_schema = 'public'
          |AND table_type = 'BASE TABLE'
          |AND table_name NOT LIKE 'databasechangelog%'""".stripMargin
      )

      val actualTables = Iterator
        .continually(rs)
        .takeWhile(_.next())
        .map(_.getString("table_name"))
        .toSet

      rs.close()
      stmt.close()

      actualTables should contain allElementsOf expectedTables
    } finally conn.close()
  }

  it should "seed all US states and territories" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs   = stmt.executeQuery("SELECT COUNT(*) FROM us_states")
      rs.next()
      val _ = rs.getInt(1) shouldBe 56 // 50 states + DC + 5 territories
      rs.close()
      stmt.close()
    } finally conn.close()
  }

  it should "seed all finding types" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs   = stmt.executeQuery("SELECT COUNT(*) FROM finding_types")
      rs.next()
      val _ = rs.getInt(
        1
      ) shouldBe 12 // 4 analysis pass types + 4 discovery categories + 2 from migration 002 + 2 from migration 005 (civil_liberties, environmental)
      rs.close()
      stmt.close()
    } finally conn.close()
  }

  it should "create HNSW vector indexes" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        "SELECT indexname FROM pg_indexes WHERE indexdef LIKE '%hnsw%' ORDER BY indexname"
      )

      val indexes = Iterator
        .continually(rs)
        .takeWhile(_.next())
        .map(_.getString("indexname"))
        .toSet

      rs.close()
      stmt.close()

      indexes should contain allElementsOf Set(
        "idx_amendment_findings_embedding",
        "idx_bill_analyses_embedding",
        "idx_bill_findings_embedding",
        "idx_bill_subjects_embedding",
        "idx_btv_embedding",
        "idx_user_preferences_embedding",
      )
    } finally conn.close()
  }

}

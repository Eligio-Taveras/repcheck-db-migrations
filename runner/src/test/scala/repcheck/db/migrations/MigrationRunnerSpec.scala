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
        // Migration 026 — chunked raw bill text
        "raw_bill_text",
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
        // Migration 026 dropped idx_btv_embedding (and the underlying
        // bill_text_versions.embedding column) and moved the HNSW index
        // to raw_bill_text.embedding where chunked text embeddings live.
        "idx_raw_bill_text_embedding",
        "idx_user_preferences_embedding",
      )
    } finally conn.close()
  }

  it should "preserve uq_member_party_history UNIQUE (member_id, start_year, party_name)" taggedAs DockerRequired in {
    // Regression guard for migrations 019 + 020.
    //   019 restored the constraint dropped by migration 011's TEXT->BIGINT column rebuild.
    //   020 widened it from (member_id, start_year) to (member_id, start_year, party_name)
    //   so intra-year party switches are preserved — Congress members can legally switch
    //   parties multiple times per year, and the ingestion pipeline's ON CONFLICT clause
    //   must match so it doesn't silently drop the second affiliation.
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT conname, pg_get_constraintdef(oid) AS def
          |FROM pg_constraint
          |WHERE conrelid = 'member_party_history'::regclass
          |  AND contype = 'u'
          |  AND conname = 'uq_member_party_history'""".stripMargin
      )

      val found   = rs.next()
      val defText = if (found) rs.getString("def") else ""
      rs.close()
      stmt.close()

      val _ = found shouldBe true
      defText should (include("member_id") and include("start_year") and include("party_name"))
    } finally conn.close()
  }

  // ---------------------------------------------------------------------------
  // Migration 023 — dual-identity vote_positions (member_id XOR lis_member_id)
  // ---------------------------------------------------------------------------

  it should "make vote_positions.id a BIGSERIAL PRIMARY KEY" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT column_name, data_type, column_default, is_nullable
          |FROM information_schema.columns
          |WHERE table_name = 'vote_positions' AND column_name = 'id'""".stripMargin
      )

      val found      = rs.next()
      val dataType   = if (found) rs.getString("data_type") else ""
      val colDefault = if (found) rs.getString("column_default") else ""
      val isNullable = if (found) rs.getString("is_nullable") else ""
      rs.close()
      stmt.close()

      val _ = found shouldBe true
      val _ = dataType shouldBe "bigint"
      val _ = isNullable shouldBe "NO"
      colDefault should include("nextval")
    } finally conn.close()
  }

  it should "make vote_positions.member_id nullable" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT is_nullable FROM information_schema.columns
          |WHERE table_name = 'vote_positions' AND column_name = 'member_id'""".stripMargin
      )

      val found      = rs.next()
      val isNullable = if (found) rs.getString("is_nullable") else ""
      rs.close()
      stmt.close()

      val _ = found shouldBe true
      val _ = isNullable shouldBe "YES"
    } finally conn.close()
  }

  it should "add vote_positions.lis_member_id with FK to lis_members(id)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()

      // Column exists, BIGINT, nullable
      val colRs = stmt.executeQuery(
        """SELECT data_type, is_nullable FROM information_schema.columns
          |WHERE table_name = 'vote_positions' AND column_name = 'lis_member_id'""".stripMargin
      )
      val colFound   = colRs.next()
      val dataType   = if (colFound) colRs.getString("data_type") else ""
      val isNullable = if (colFound) colRs.getString("is_nullable") else ""
      colRs.close()

      // FK constraint to lis_members(id)
      val fkRs = stmt.executeQuery(
        """SELECT confrelid::regclass::text AS referenced_table,
          |       pg_get_constraintdef(oid) AS def
          |FROM pg_constraint
          |WHERE conrelid = 'vote_positions'::regclass
          |  AND contype = 'f'
          |  AND pg_get_constraintdef(oid) LIKE '%lis_member_id%'""".stripMargin
      )
      val fkFound  = fkRs.next()
      val refTable = if (fkFound) fkRs.getString("referenced_table") else ""
      val fkDef    = if (fkFound) fkRs.getString("def") else ""
      fkRs.close()
      stmt.close()

      val _ = colFound shouldBe true
      val _ = dataType shouldBe "bigint"
      val _ = isNullable shouldBe "YES"
      val _ = fkFound shouldBe true
      val _ = refTable shouldBe "lis_members"
      fkDef should (include("lis_member_id") and include("REFERENCES lis_members(id)"))
    } finally conn.close()
  }

  it should "enforce chk_vp_xor_identity — reject (NULL, NULL) and (Some, Some)" taggedAs DockerRequired in {
    // This verifies the XOR CHECK by exercising the DB directly. We seed a
    // minimal row-dependency graph (member, lis_member, vote) so we can attempt
    // inserts that should be rejected by the CHECK alone (not by FK or NOT NULL).
    //
    // Uses explicit SAVEPOINTs so a failed INSERT (which aborts the tx in
    // Postgres JDBC) can be rolled back to the savepoint and further inserts
    // can still see the seed rows.
    val conn = getConnection
    try {
      conn.setAutoCommit(false)
      val stmt = conn.createStatement()

      // Seed prerequisite rows — post-migration 012, placeholders only need the natural_key.
      val _ = stmt.executeUpdate(
        "INSERT INTO members (natural_key) VALUES ('XOR_TEST_MEMBER')"
      )
      val _ = stmt.executeUpdate(
        "INSERT INTO lis_members (natural_key) VALUES ('XOR_TEST_LIS')"
      )
      val _ = stmt.executeUpdate(
        """INSERT INTO votes (natural_key, congress, chamber, session_number, roll_number)
          |VALUES ('XOR_TEST_VOTE', 118, 'House'::chamber_type, 1, 1)""".stripMargin
      )

      def loadId(sql: String): Long = {
        val rs = stmt.executeQuery(sql)
        rs.next()
        val id = rs.getLong("id")
        rs.close()
        id
      }
      val memberId    = loadId("SELECT id FROM members WHERE natural_key = 'XOR_TEST_MEMBER'")
      val lisMemberId = loadId("SELECT id FROM lis_members WHERE natural_key = 'XOR_TEST_LIS'")
      val voteId      = loadId("SELECT id FROM votes WHERE natural_key = 'XOR_TEST_VOTE'")

      // (NULL, NULL) must be rejected — use savepoint so the seeds survive.
      val sp1 = conn.setSavepoint("before_null_null")
      val bothNullEx = intercept[java.sql.SQLException] {
        val ps = conn.prepareStatement(
          "INSERT INTO vote_positions (vote_id, member_id, lis_member_id, position) " +
            "VALUES (?, NULL, NULL, 'Yea'::vote_cast_type)"
        )
        ps.setLong(1, voteId)
        try {
          val _ = ps.executeUpdate()
          ()
        } finally ps.close()
      }
      val _ = bothNullEx.toString should include("chk_vp_xor_identity")
      conn.rollback(sp1)

      // (Some, Some) must be rejected — seeds still present due to savepoint rollback.
      val sp2 = conn.setSavepoint("before_some_some")
      val bothSetEx = intercept[java.sql.SQLException] {
        val ps = conn.prepareStatement(
          "INSERT INTO vote_positions (vote_id, member_id, lis_member_id, position) " +
            "VALUES (?, ?, ?, 'Yea'::vote_cast_type)"
        )
        ps.setLong(1, voteId)
        ps.setLong(2, memberId)
        ps.setLong(3, lisMemberId)
        try {
          val _ = ps.executeUpdate()
          ()
        } finally ps.close()
      }
      val _ = bothSetEx.toString should include("chk_vp_xor_identity")
      conn.rollback(sp2)

      stmt.close()
    } finally {
      conn.rollback()
      conn.setAutoCommit(true)
      conn.close()
    }
  }

  it should "enforce uq_vp_vote_member and uq_vp_vote_lis as partial UNIQUE indexes" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT indexname, indexdef FROM pg_indexes
          |WHERE tablename = 'vote_positions'
          |  AND indexname IN ('uq_vp_vote_member', 'uq_vp_vote_lis')
          |ORDER BY indexname""".stripMargin
      )

      val rows = Iterator
        .continually(rs)
        .takeWhile(_.next())
        .map(r => r.getString("indexname") -> r.getString("indexdef"))
        .toMap
      rs.close()
      stmt.close()

      val _ = rows.keySet shouldBe Set("uq_vp_vote_lis", "uq_vp_vote_member")

      val voteMemberDef = rows("uq_vp_vote_member")
      val _             = voteMemberDef should (include("UNIQUE") and include("vote_id") and include("member_id"))
      val _             = voteMemberDef should include("WHERE (member_id IS NOT NULL)")

      val voteLisDef = rows("uq_vp_vote_lis")
      val _          = voteLisDef should (include("UNIQUE") and include("vote_id") and include("lis_member_id"))
      voteLisDef should include("WHERE (lis_member_id IS NOT NULL)")
    } finally conn.close()
  }

  it should "drop the old uq_vote_positions composite UNIQUE constraint" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT conname FROM pg_constraint
          |WHERE conrelid = 'vote_positions'::regclass
          |  AND conname = 'uq_vote_positions'""".stripMargin
      )

      val found = rs.next()
      rs.close()
      stmt.close()

      val _ = found shouldBe false
    } finally conn.close()
  }

  it should "create vote_positions_resolved view unifying House and Senate arms" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      conn.setAutoCommit(false)
      val stmt = conn.createStatement()

      // View exists
      val viewRs = stmt.executeQuery(
        """SELECT table_name FROM information_schema.views
          |WHERE table_schema = 'public' AND table_name = 'vote_positions_resolved'""".stripMargin
      )
      val viewFound = viewRs.next()
      viewRs.close()
      val _ = viewFound shouldBe true

      // Seed data so both arms return rows:
      //   - One House row (member_id populated, lis_member_id NULL)
      //   - One Senate row mapped via member_lis_mapping
      //   - One Senate row unmapped (should be excluded)

      val _ = stmt.executeUpdate(
        """INSERT INTO members (natural_key)
          |VALUES ('VPR_TEST_HOUSE'),
          |       ('VPR_TEST_SEN_MAPPED')""".stripMargin
      )
      val _ = stmt.executeUpdate(
        """INSERT INTO lis_members (natural_key)
          |VALUES ('VPR_TEST_LIS_MAPPED'),
          |       ('VPR_TEST_LIS_UNMAPPED')""".stripMargin
      )
      val _ = stmt.executeUpdate(
        """INSERT INTO votes (natural_key, congress, chamber, session_number, roll_number)
          |VALUES ('VPR_TEST_VOTE', 118, 'House'::chamber_type, 1, 2)""".stripMargin
      )

      def loadId(sql: String): Long = {
        val rs = stmt.executeQuery(sql)
        rs.next()
        val id = rs.getLong("id")
        rs.close()
        id
      }
      val houseMemberId = loadId("SELECT id FROM members WHERE natural_key = 'VPR_TEST_HOUSE'")
      val senMappedId   = loadId("SELECT id FROM members WHERE natural_key = 'VPR_TEST_SEN_MAPPED'")
      val lisMappedId   = loadId("SELECT id FROM lis_members WHERE natural_key = 'VPR_TEST_LIS_MAPPED'")
      val lisUnmappedId = loadId("SELECT id FROM lis_members WHERE natural_key = 'VPR_TEST_LIS_UNMAPPED'")
      val voteId        = loadId("SELECT id FROM votes WHERE natural_key = 'VPR_TEST_VOTE'")

      // Map one of the senators so the Senate arm can resolve it.
      val mapPs = conn.prepareStatement(
        "INSERT INTO member_lis_mapping (member_id, lis_member_id) VALUES (?, ?)"
      )
      mapPs.setLong(1, senMappedId)
      mapPs.setLong(2, lisMappedId)
      val _ = mapPs.executeUpdate()
      mapPs.close()

      // Insert vote_positions rows exercising both arms + unmapped senator.
      val vpHouse = conn.prepareStatement(
        "INSERT INTO vote_positions (vote_id, member_id, lis_member_id, position) " +
          "VALUES (?, ?, NULL, 'Yea'::vote_cast_type)"
      )
      vpHouse.setLong(1, voteId)
      vpHouse.setLong(2, houseMemberId)
      val _ = vpHouse.executeUpdate()
      vpHouse.close()

      val vpSenMapped = conn.prepareStatement(
        "INSERT INTO vote_positions (vote_id, member_id, lis_member_id, position) " +
          "VALUES (?, NULL, ?, 'Nay'::vote_cast_type)"
      )
      vpSenMapped.setLong(1, voteId)
      vpSenMapped.setLong(2, lisMappedId)
      val _ = vpSenMapped.executeUpdate()
      vpSenMapped.close()

      val vpSenUnmapped = conn.prepareStatement(
        "INSERT INTO vote_positions (vote_id, member_id, lis_member_id, position) " +
          "VALUES (?, NULL, ?, 'Nay'::vote_cast_type)"
      )
      vpSenUnmapped.setLong(1, voteId)
      vpSenUnmapped.setLong(2, lisUnmappedId)
      val _ = vpSenUnmapped.executeUpdate()
      vpSenUnmapped.close()

      // View should return 2 rows: House + mapped Senate. Unmapped is excluded.
      val vpsRs = stmt.executeQuery(
        s"""SELECT member_id, lis_member_id FROM vote_positions_resolved
            |WHERE vote_id = $voteId
            |ORDER BY member_id""".stripMargin
      )
      val resolvedRows = Iterator
        .continually(vpsRs)
        .takeWhile(_.next())
        .map { r =>
          val mId    = r.getLong("member_id")
          val mIdOpt = if (r.wasNull()) None else Some(mId)
          val lIdRaw = r.getLong("lis_member_id")
          val lIdOpt = if (r.wasNull()) None else Some(lIdRaw)
          (mIdOpt, lIdOpt)
        }
        .toList
      vpsRs.close()
      stmt.close()

      val _ = resolvedRows.size shouldBe 2
      // Both rows must carry a member_id (House arm passes through; Senate arm resolved via mapping).
      val _ = resolvedRows.map(_._1) should contain theSameElementsAs List(Some(houseMemberId), Some(senMappedId))
      // Senate arm preserves lis_member_id; House arm is NULL.
      resolvedRows.map(_._2) should contain theSameElementsAs List(None, Some(lisMappedId))
    } finally {
      conn.rollback()
      conn.setAutoCommit(true)
      conn.close()
    }
  }

  // =========================================================================
  // Migration 024 — enum value additions
  // =========================================================================

  /**
   * Pull every `value` column from a ResultSet into an immutable List. Wart-compliant (no mutable collection) via
   * Iterator.continually + takeWhile.
   */
  private def readAllValues(rs: java.sql.ResultSet): List[String] =
    Iterator.continually(rs.next()).takeWhile(identity).map(_ => rs.getString("value")).toList

  it should "add 'Candidate' to vote_cast_type enum (migration 024)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT unnest(enum_range(NULL::vote_cast_type))::text AS value""".stripMargin
      )
      val values = readAllValues(rs)
      rs.close()
      stmt.close()
      values should contain("Candidate")
    } finally conn.close()
  }

  it should "add 'Election' to vote_type_enum (migration 024)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT unnest(enum_range(NULL::vote_type_enum))::text AS value""".stripMargin
      )
      val values = readAllValues(rs)
      rs.close()
      stmt.close()
      values should contain("Election")
    } finally conn.close()
  }

  // =========================================================================
  // Migration 025 — vote_cast_candidate_name column + CHECK + VIEW update
  // =========================================================================

  it should "add vote_cast_candidate_name TEXT column on vote_positions (migration 025)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT data_type, is_nullable FROM information_schema.columns
          |WHERE table_name = 'vote_positions' AND column_name = 'vote_cast_candidate_name'""".stripMargin
      )
      val found  = rs.next()
      val dt     = if (found) rs.getString("data_type") else ""
      val nullOk = if (found) rs.getString("is_nullable") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      val _ = dt shouldBe "text"
      nullOk shouldBe "YES"
    } finally conn.close()
  }

  it should "mirror vote_cast_candidate_name on vote_history_positions (migration 025)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT data_type FROM information_schema.columns
          |WHERE table_name = 'vote_history_positions' AND column_name = 'vote_cast_candidate_name'""".stripMargin
      )
      val found = rs.next()
      val dt    = if (found) rs.getString("data_type") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      dt shouldBe "text"
    } finally conn.close()
  }

  it should "enforce chk_vp_candidate_name — position='Candidate' requires non-null name" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      conn.setAutoCommit(false)
      val stmt = conn.createStatement()

      // Seed members + a bill-less vote so we can INSERT positions.
      val memRs = stmt.executeQuery(
        """INSERT INTO members (natural_key) VALUES ('VCN_TEST_M1') RETURNING id""".stripMargin
      )
      memRs.next()
      val memberId = memRs.getLong(1)
      memRs.close()

      val voteRs = stmt.executeQuery(
        """INSERT INTO votes (natural_key, congress, chamber, session_number, roll_number)
          |VALUES ('VCN_TEST_VOTE', 119, 'House'::chamber_type, 1, 9999)
          |RETURNING id""".stripMargin
      )
      voteRs.next()
      val voteId = voteRs.getLong(1)
      voteRs.close()

      // Case 1: position='Yea' with a candidate_name -> CHECK must reject.
      stmt.execute("SAVEPOINT sp1")
      val rejectYea = scala.util.Try {
        val _ = stmt.executeUpdate(
          s"""INSERT INTO vote_positions (vote_id, member_id, position, vote_cast_candidate_name)
             |VALUES ($voteId, $memberId, 'Yea', 'Jeffries')""".stripMargin
        )
      }
      stmt.execute("ROLLBACK TO SAVEPOINT sp1")
      val _ = rejectYea.isFailure shouldBe true

      // Case 2: position='Candidate' with NULL candidate_name -> CHECK must reject.
      stmt.execute("SAVEPOINT sp2")
      val rejectNullName = scala.util.Try {
        val _ = stmt.executeUpdate(
          s"""INSERT INTO vote_positions (vote_id, member_id, position)
             |VALUES ($voteId, $memberId, 'Candidate')""".stripMargin
        )
      }
      stmt.execute("ROLLBACK TO SAVEPOINT sp2")
      val _ = rejectNullName.isFailure shouldBe true

      // Case 3: position='Candidate' + name -> allowed.
      val okCandidate = stmt.executeUpdate(
        s"""INSERT INTO vote_positions (vote_id, member_id, position, vote_cast_candidate_name)
           |VALUES ($voteId, $memberId, 'Candidate', 'Jeffries')""".stripMargin
      )
      val _ = okCandidate shouldBe 1

      stmt.close()
    } finally {
      conn.rollback()
      conn.setAutoCommit(true)
      conn.close()
    }
  }

  it should "expose vote_cast_candidate_name through vote_positions_resolved VIEW (migration 025)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT column_name FROM information_schema.columns
          |WHERE table_schema = 'public'
          |  AND table_name = 'vote_positions_resolved'
          |  AND column_name = 'vote_cast_candidate_name'""".stripMargin
      )
      val found = rs.next()
      rs.close()
      stmt.close()
      found shouldBe true
    } finally conn.close()
  }

  it should "drop bill_text_versions.content and .embedding (migration 026)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT column_name FROM information_schema.columns
          |WHERE table_schema = 'public'
          |  AND table_name = 'bill_text_versions'
          |  AND column_name IN ('content', 'embedding')""".stripMargin
      )
      val remaining = Iterator
        .continually(rs)
        .takeWhile(_.next())
        .map(_.getString("column_name"))
        .toSet
      rs.close()
      stmt.close()
      remaining shouldBe Set.empty
    } finally conn.close()
  }

  it should "expose raw_bill_text with the expected columns (migration 026)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT column_name, is_nullable, data_type
          |FROM information_schema.columns
          |WHERE table_schema = 'public'
          |  AND table_name = 'raw_bill_text'""".stripMargin
      )
      val columns = Iterator
        .continually(rs)
        .takeWhile(_.next())
        .map { r =>
          val name     = r.getString("column_name")
          val nullable = r.getString("is_nullable") == "YES"
          val typ      = r.getString("data_type")
          (name, nullable, typ)
        }
        .toList
      rs.close()
      stmt.close()

      val byName = columns.map { case (n, nu, t) => n -> (nu, t) }.toMap

      val _ =
        byName.keySet should contain allOf ("id", "bill_id", "version_id", "chunk_index", "content", "embedding", "created_at")
      val _ = byName("id")._1 shouldBe false          // NOT NULL
      val _ = byName("bill_id")._1 shouldBe false     // NOT NULL
      val _ = byName("version_id")._1 shouldBe true   // nullable per the design
      val _ = byName("chunk_index")._1 shouldBe false // NOT NULL
      val _ = byName("content")._1 shouldBe false     // NOT NULL
      val _ = byName("embedding")._1 shouldBe true    // nullable (allows inserting row before embed call completes)
      byName("embedding")._2 shouldBe "USER-DEFINED" // pgvector type
    } finally conn.close()
  }

  it should "enforce (version_id, chunk_index) uniqueness on raw_bill_text only when version_id is not null (migration 026)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT indexname, indexdef
          |FROM pg_indexes
          |WHERE schemaname = 'public'
          |  AND tablename = 'raw_bill_text'
          |  AND indexname = 'uq_raw_bill_text_version_chunk'""".stripMargin
      )
      val found = rs.next()
      val defn  = if (found) rs.getString("indexdef") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      val _ = defn should include("UNIQUE")
      defn should include("WHERE (version_id IS NOT NULL)")
    } finally conn.close()
  }

  it should "drop the legacy uq_votes_natural_key constraint on (congress, chamber, roll_number) (migration 027)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT conname
          |FROM pg_constraint
          |WHERE conrelid = 'public.votes'::regclass
          |  AND conname = 'uq_votes_natural_key'""".stripMargin
      )
      val present = rs.next()
      rs.close()
      stmt.close()
      // Migration 027 dropped this legacy constraint. uq_votes_natural_key_pk on (natural_key)
      // remains and is the correct identity (sessions distinguished via the string format).
      present shouldBe false
    } finally conn.close()
  }

  it should "retain the natural_key string constraint after migration 027" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT conname
          |FROM pg_constraint
          |WHERE conrelid = 'public.votes'::regclass
          |  AND conname = 'uq_votes_natural_key_pk'""".stripMargin
      )
      val present = rs.next()
      rs.close()
      stmt.close()
      present shouldBe true
    } finally conn.close()
  }

  it should "add the session-aware composite uq_votes_congress_chamber_session_roll constraint (migration 027)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT array_to_string(
          |         array_agg(a.attname ORDER BY array_position(c.conkey, a.attnum)),
          |         ','
          |       ) AS columns
          |FROM pg_constraint c
          |JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
          |WHERE c.conrelid = 'public.votes'::regclass
          |  AND c.conname = 'uq_votes_congress_chamber_session_roll'
          |GROUP BY c.conname""".stripMargin
      )
      val found = rs.next()
      val cols  = if (found) rs.getString("columns") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      cols shouldBe "congress,chamber,session_number,roll_number"
    } finally conn.close()
  }

  it should "make votes.session_number NOT NULL after migration 027" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT is_nullable
          |FROM information_schema.columns
          |WHERE table_schema = 'public'
          |  AND table_name = 'votes'
          |  AND column_name = 'session_number'""".stripMargin
      )
      val found    = rs.next()
      val nullable = if (found) rs.getString("is_nullable") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      nullable shouldBe "NO"
    } finally conn.close()
  }

  it should "shrink raw_bill_text.embedding to vector(1024) (migration 028)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      // format_type renders pgvector typmod as "vector(N)" — N is the dimension
      val rs = stmt.executeQuery(
        """SELECT format_type(a.atttypid, a.atttypmod) AS rendered_type
          |FROM pg_attribute a
          |WHERE a.attrelid = 'public.raw_bill_text'::regclass
          |  AND a.attname = 'embedding'
          |  AND NOT a.attisdropped""".stripMargin
      )
      val found    = rs.next()
      val rendered = if (found) rs.getString("rendered_type") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      rendered shouldBe "vector(1024)"
    } finally conn.close()
  }

  it should "rebuild the raw_bill_text.embedding HNSW index on the new column (migration 028)" taggedAs DockerRequired in {
    val conn = getConnection
    try {
      val stmt = conn.createStatement()
      val rs = stmt.executeQuery(
        """SELECT indexdef
          |FROM pg_indexes
          |WHERE schemaname = 'public'
          |  AND tablename = 'raw_bill_text'
          |  AND indexname = 'idx_raw_bill_text_embedding'""".stripMargin
      )
      val found = rs.next()
      val defn  = if (found) rs.getString("indexdef") else ""
      rs.close()
      stmt.close()
      val _ = found shouldBe true
      val _ = defn should include("USING hnsw")
      defn should include("vector_cosine_ops")
    } finally conn.close()
  }

}

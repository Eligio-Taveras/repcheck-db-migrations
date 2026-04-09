package repcheck.db.migrations

import java.sql.{Connection, DriverManager}
import java.util.UUID

import scala.annotation.tailrec
import scala.sys.process._
import scala.util.Try

import cats.effect.unsafe.implicits.global
import cats.effect.{IO, Resource}

import org.scalatest.{BeforeAndAfterAll, Suite, Tag}

/**
 * Immutable AlloyDB Omni container info returned by DockerPostgres.resource.
 */
final case class PostgresContainerInfo(jdbcUrl: String, user: String, password: String) {

  def getConnection: Connection =
    DriverManager.getConnection(jdbcUrl, user, password)

}

/**
 * Cats Effect Resource that manages an AlloyDB Omni Docker container lifecycle.
 *
 * Uses the Docker CLI directly rather than Testcontainers to avoid the API version incompatibility between docker-java
 * (v1.32) and Docker 29+ (minimum v1.40).
 *
 * AlloyDB Omni is Google's containerized AlloyDB engine — wire-compatible with PostgreSQL 16, with pgvector and
 * uuid-ossp extensions bundled. Using Omni for tests provides production parity with the AlloyDB instances used in
 * staging and prod.
 *
 * Each resource allocation gets a unique container name and random host port. Migrations are applied automatically
 * after the container is ready.
 *
 * Can be used directly:
 * {{{
 *   DockerPostgres.resource.use { info =>
 *     IO { /* use info.getConnection */ }
 *   }
 * }}}
 *
 * Or via the DockerPostgresSpec trait for ScalaTest suites.
 */
object DockerPostgres {

  private val dbName: String        = "repcheck_test"
  private val dbUser: String        = "test"
  private val dbPassword: String    = "test"
  private val image: String         = "google/alloydbomni:16.8.0"
  private val maxReadyAttempts: Int = 30
  private val readyDelayMs: Long    = 1000L

  // Internal handle that pairs the container name (for cleanup) with the public info
  final private case class ContainerHandle(name: String, info: PostgresContainerInfo)

  /**
   * Resource that acquires a Docker pgvector container with migrations applied, and removes it on release. Each
   * allocation gets a unique container name and random port.
   */
  val resource: Resource[IO, PostgresContainerInfo] =
    Resource.make(acquire)(release).map(_.info)

  private def acquire: IO[ContainerHandle] = IO.blocking {
    val containerName = s"repcheck-test-${UUID.randomUUID().toString.take(8)}"
    val port          = startContainer(containerName)
    waitForReady(containerName)
    applyMigrations(port)
    ContainerHandle(
      name = containerName,
      info = PostgresContainerInfo(
        jdbcUrl = s"jdbc:postgresql://localhost:$port/$dbName?sslmode=disable",
        user = dbUser,
        password = dbPassword,
      ),
    )
  }

  private def release(handle: ContainerHandle): IO[Unit] = IO.blocking {
    val _ = Seq("docker", "rm", "-f", handle.name).!
    ()
  }

  private def startContainer(containerName: String): Int = {
    val exitCode = Seq(
      "docker",
      "run",
      "-d",
      "--name",
      containerName,
      "-e",
      s"POSTGRES_DB=$dbName",
      "-e",
      s"POSTGRES_USER=$dbUser",
      "-e",
      s"POSTGRES_PASSWORD=$dbPassword",
      "-p",
      "0:5432",
      image,
    ).!

    if (exitCode != 0) {
      sys.error("Failed to start Docker container. Is Docker running?")
    }

    val portOutput = Seq("docker", "port", containerName, "5432").!!.trim
    // Output format: "0.0.0.0:12345" or "[::]:12345"
    portOutput.split(':').last.toInt
  }

  private def waitForReady(containerName: String): Unit = {
    @tailrec
    def poll(remaining: Int): Boolean =
      if (remaining <= 0) { false }
      else {
        val ready = Try {
          Seq("docker", "exec", containerName, "pg_isready", "-U", dbUser, "-d", dbName).!!
        }.isSuccess

        if (ready) { true }
        else {
          Thread.sleep(readyDelayMs)
          poll(remaining - 1)
        }
      }

    if (!poll(maxReadyAttempts)) {
      val _ = Seq("docker", "rm", "-f", containerName).!
      sys.error(s"PostgreSQL container did not become ready after $maxReadyAttempts attempts")
    }
  }

  private val maxConnectAttempts: Int = 10
  private val connectDelayMs: Long    = 1000L

  private def applyMigrations(port: Int): Unit = {
    val conn = connectWithRetry(port, maxConnectAttempts)
    try
      MigrationRunner.migrate(conn)
    finally conn.close()
  }

  // pg_isready reports success before the server is fully ready for authenticated
  // JDBC connections (especially in CI). Retry the JDBC connect to handle this gap.
  @tailrec
  private def connectWithRetry(port: Int, remaining: Int): Connection = {
    val result = Try {
      DriverManager.getConnection(
        s"jdbc:postgresql://localhost:$port/$dbName?sslmode=disable",
        dbUser,
        dbPassword,
      )
    }
    result match {
      case scala.util.Success(conn) => conn
      case scala.util.Failure(_) if remaining > 1 =>
        Thread.sleep(connectDelayMs)
        connectWithRetry(port, remaining - 1)
      case scala.util.Failure(ex) =>
        sys.error(s"Failed to connect to PostgreSQL after $maxConnectAttempts attempts: ${ex.getMessage}")
    }
  }

}

/**
 * Mix-in trait for ScalaTest suites that need an AlloyDB Omni database with pgvector.
 *
 * Uses Cats Effect Resource.allocated to manage the container lifecycle across the suite. The container starts in
 * beforeAll and is removed in afterAll. No mutable state — lazy val handles single-evaluation semantics.
 *
 * Other SBT projects can use this trait by depending on db-migrations in test scope:
 * {{{
 *   .dependsOn(dbMigrations % "test->test")
 * }}}
 *
 * Then extend it in their specs:
 * {{{
 *   class MyRepoSpec extends AnyFlatSpec with DockerPostgresSpec {
 *     it should "query the database" in {
 *       val conn = getConnection
 *       try { ... } finally conn.close()
 *     }
 *   }
 * }}}
 */
trait DockerPostgresSpec extends BeforeAndAfterAll { self: Suite =>

  // Resource.allocated returns (A, IO[Unit]) — the value and its finalizer.
  // lazy val ensures single evaluation with no mutable state.
  private lazy val (containerInfo, releaseContainer) =
    DockerPostgres.resource.allocated.unsafeRunSync()

  protected def getConnection: Connection = containerInfo.getConnection

  protected def jdbcUrl: String = containerInfo.jdbcUrl

  override def beforeAll(): Unit = {
    super.beforeAll()
    // Force lazy val evaluation — starts the container and applies migrations
    val _ = containerInfo
  }

  override def afterAll(): Unit =
    try
      releaseContainer.unsafeRunSync()
    finally super.afterAll()

}

/**
 * Tag for tests that require Docker. Allows selective execution:
 * {{{
 *   sbt "testOnly -- -n DockerRequired"     // only Docker tests
 *   sbt "testOnly -- -l DockerRequired"     // exclude Docker tests
 * }}}
 */
object DockerRequired extends Tag("DockerRequired")

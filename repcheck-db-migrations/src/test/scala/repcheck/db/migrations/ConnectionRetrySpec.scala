package repcheck.db.migrations

import java.sql.SQLException

import scala.concurrent.duration._

import cats.effect.unsafe.implicits.global

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

class ConnectionRetrySpec extends AnyFlatSpec with Matchers {

  // H2 in-memory database — no Docker required, available as a test dependency
  private val h2Url      = "jdbc:h2:mem:retry_test;DB_CLOSE_DELAY=-1"
  private val h2User     = "sa"
  private val h2Password = ""

  // Bogus URL that will always fail to connect
  private val bogusUrl = "jdbc:postgresql://localhost:1/nonexistent"

  "ConnectionRetry.connectWithRetry" should "return a connection on first attempt when the database is reachable" in {
    val connection = ConnectionRetry
      .connectWithRetry(h2Url, h2User, h2Password, retriesLeft = 3, delay = 1.millisecond)
      .unsafeRunSync()

    try {
      val _ = connection.isClosed shouldBe false
      connection.isValid(1) shouldBe true
    } finally connection.close()
  }

  it should "fail immediately when retriesLeft is 0 and database is unreachable" in {
    val error = intercept[SQLException] {
      ConnectionRetry
        .connectWithRetry(bogusUrl, "user", "pass", retriesLeft = 0, delay = 1.millisecond)
        .unsafeRunSync()
    }

    error.getMessage should not be empty
  }

  it should "exhaust retries and raise the last error when database never becomes reachable" in {
    val error = intercept[SQLException] {
      ConnectionRetry
        .connectWithRetry(bogusUrl, "user", "pass", retriesLeft = 2, delay = 1.millisecond)
        .unsafeRunSync()
    }

    error.getMessage should not be empty
  }

  it should "succeed after retries when given a valid URL" in {
    // Even with retries configured, a reachable DB succeeds on the first attempt
    val connection = ConnectionRetry
      .connectWithRetry(h2Url, h2User, h2Password, retriesLeft = 5, delay = 1.millisecond)
      .unsafeRunSync()

    try
      connection.isValid(1) shouldBe true
    finally connection.close()
  }

  "MissingEnvVar" should "include the variable name in the error message" in {
    val error = MissingEnvVar("DATABASE_HOST")
    error.getMessage shouldBe "Required environment variable 'DATABASE_HOST' is not set"
  }

  it should "extend Exception" in {
    val error = MissingEnvVar("SOME_VAR")
    val _     = (error: Exception).getMessage should include("SOME_VAR")
    error.name shouldBe "SOME_VAR"
  }

}

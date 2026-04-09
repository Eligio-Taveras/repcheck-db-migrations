import org.typelevel.scalacoptions.ScalacOption
import sbt.Keys.libraryDependencies
import sbt.Def
import Dependencies.*
import com.repcheck.sbt.ExceptionUniquenessPlugin.autoImport.exceptionUniquenessRootPackages

val isScala212: Def.Initialize[Boolean] = Def.setting {
  VersionNumber(scalaVersion.value).matchesSemVer(SemanticSelector("2.12.x"))
}

ThisBuild / dynverSonatypeSnapshots := true

lazy val commonSettings = Seq(
  organization := "com.repcheck",
  scalaVersion := "3.7.3",
  publishTo := Some(
    "GitHub Packages" at s"https://maven.pkg.github.com/Eligio-Taveras/repcheck-db-migrations"
  ),
  publishMavenStyle := true,
  credentials ++= {
    val envCreds = for {
      user  <- sys.env.get("GITHUB_ACTOR")
      token <- sys.env.get("GITHUB_TOKEN")
    } yield Credentials("GitHub Package Registry", "maven.pkg.github.com", user, token)

    val fileCreds = {
      val f = Path.userHome / ".sbt" / ".github-packages-credentials"
      if (f.exists) Some(Credentials(f)) else None
    }

    envCreds.orElse(fileCreds).toSeq
  },
  libraryDependencies ++= Seq(
    "org.scalatest" %% "scalatest" % "3.2.18" % Test
  ),
  semanticdbEnabled := true,
  tpolecatScalacOptions ++= ScalaCConfig.scalaCOptions,
  tpolecatScalacOptions ++= {
    if (isScala212.value) ScalaCConfig.scalaCOption2_12
    else Set.empty[ScalacOption]
  },

  // WartRemover — enforces FP discipline at compile time
  wartremoverErrors ++= Seq(
    Wart.AsInstanceOf,          // No unsafe casts
    Wart.EitherProjectionPartial, // No .get on Either projections
    Wart.IsInstanceOf,          // No runtime type checks — use pattern matching
    Wart.MutableDataStructures, // No mutable collections
    Wart.Null,                  // No null — use Option
    Wart.OptionPartial,         // No Option.get — use fold/map/getOrElse
    Wart.Return,                // No return statements
    Wart.StringPlusAny,         // No string + any — use interpolation
    Wart.IterableOps,           // No .head/.tail on collections — use headOption
    Wart.TryPartial,            // No Try.get — use fold/recover
    Wart.Var                    // No mutable vars
  ),
  wartremoverWarnings ++= Seq(
    Wart.Throw                  // Warn on bare throw — prefer F.raiseError
  )
)

lazy val dockerSettings = Seq(
  dockerBaseImage := "gcr.io/distroless/java21-debian12",
  dockerExposedPorts := Seq.empty,
  dockerUpdateLatest := true,
  Docker / daemonUser := "appuser",
)

lazy val root = (project in file("."))
  .aggregate(repcheckdbmigrations)
  .settings(
    commonSettings,
    name := "repcheck-db-migrations-root",
    publish / skip := true
  )

lazy val repcheckdbmigrations = (project in file("repcheck-db-migrations"))
  .enablePlugins(com.repcheck.sbt.ExceptionUniquenessPlugin, JavaAppPackaging, DockerPlugin)
  .settings(
    commonSettings,
    dockerSettings,
    name := "repcheck-db-migrations",
    libraryDependencies ++= liquibase ++ h2 ++ catsEffect ++ doobie ++ logging ++ testDeps,
    Compile / mainClass := Some("repcheck.db.migrations.MigrationApp"),
    Docker / packageName := "repcheck/db-migrations",
    exceptionUniquenessRootPackages := Seq("repcheck.db.migrations"),
    coverageEnabled := true,
    // MigrationApp is a thin wiring entry point — all logic lives in MigrationRunner
    // and ConnectionRetry. It is excluded from coverage because there is no testable
    // logic beyond environment-variable reading and Cats Effect wiring.
    coverageExcludedFiles := ".*MigrationApp.*"
  )

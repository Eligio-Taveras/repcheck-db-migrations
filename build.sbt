import org.typelevel.scalacoptions.ScalacOption
import sbt.Keys.libraryDependencies
import sbt.Def
import Dependencies.*
import com.repcheck.sbt.ExceptionUniquenessPlugin.autoImport.exceptionUniquenessRootPackages
import com.typesafe.sbt.packager.docker.DockerPermissionStrategy

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

lazy val scalatestTest = Seq(
  libraryDependencies += "org.scalatest" %% "scalatest" % Versions.scalatestVersion % Test
)

lazy val dockerSettings = Seq(
  dockerBaseImage := "gcr.io/distroless/java21-debian12",
  dockerExposedPorts := Seq.empty,
  dockerUpdateLatest := true,
  // Distroless has no shell (/bin/sh), chmod, or useradd — disable all RUN commands.
  // The distroless java21-debian12 image ships with a "nonroot" user (uid 65532).
  dockerPermissionStrategy := DockerPermissionStrategy.None,
  Docker / daemonUserUid := None,
  Docker / daemonUser := "nonroot",
)

lazy val root = (project in file("."))
  .aggregate(changesets, runner, app)
  .settings(
    commonSettings,
    name := "repcheck-db-migrations-root",
    publish / skip := true
  )

// ── changesets ────────────────────────────────────────────────────────────────
// Resources-only JAR containing the Liquibase master changelog + SQL files.
// No Scala code, no transitive dependencies. Consumers that want to bring up
// Postgres in a test and apply the schema can add this JAR to their classpath
// and point Liquibase at `classpath:db/changelog/db.changelog-master.yaml`.
lazy val changesets = (project in file("changesets"))
  .settings(
    commonSettings,
    name := "repcheck-db-migrations-changesets",
    // Resources-only: explicitly disable Scala autocompile of empty source tree.
    crossPaths := true,
    autoScalaLibrary := false,
    // No library deps — this is a pure resource JAR.
    libraryDependencies := Seq.empty,
    // Not a real Scala project so no need for WartRemover / tpolecat / scalafmt
    wartremoverErrors := Seq.empty,
    wartremoverWarnings := Seq.empty,
    tpolecatScalacOptions := Set.empty,
    // No tests in this subproject.
    Test / test := {},
    coverageEnabled := false
  )

// ── runner ────────────────────────────────────────────────────────────────────
// The publishable Scala library: MigrationRunner, ConnectionRetry, typed
// exceptions, and the reusable `DockerPostgresSpec` trait.
// Depends on `changesets` so the published POM transitively pulls the
// changelog JAR onto consumers' classpaths.
lazy val runner = (project in file("runner"))
  .enablePlugins(com.repcheck.sbt.ExceptionUniquenessPlugin)
  .dependsOn(changesets)
  .settings(
    commonSettings,
    scalatestTest,
    name := "repcheck-db-migrations-runner",
    libraryDependencies ++=
      liquibase ++ h2 ++ catsEffect ++ doobie ++ logging ++ testDeps ++ testkitProvided,
    exceptionUniquenessRootPackages := Seq("repcheck.db.migrations"),
    // NOTE: coverageEnabled is intentionally NOT set here. Turning it on in
    // default settings bakes scoverage bytecode instrumentation (with absolute
    // GHA runner paths) into the published JAR, which crashes consumers on
    // classload with FileNotFoundException for scoverage.measurements.<uuid>.
    // Run coverage explicitly for local/CI measurement instead:
    //   sbt coverage test coverageReport coverageOff
    // DockerPostgresSpec testkit lives in src/main/scala so it can be published
    // for downstream reuse. It is exercised transitively by MigrationRunnerSpec
    // and is not the locus of any custom business logic, so exclude it from
    // the coverage numerator. The coverage gate applies to the actual runner
    // classes (MigrationRunner, ConnectionRetry, exceptions).
    coverageExcludedFiles := ".*DockerPostgresSpec.*"
  )

// ── app ───────────────────────────────────────────────────────────────────────
// The IOApp Cloud Run Job entry point. Produces a Docker image via
// sbt-native-packager. NOT published to Maven — consumers pull the Docker
// image from the container registry instead.
lazy val app = (project in file("app"))
  .enablePlugins(JavaAppPackaging, DockerPlugin, com.repcheck.sbt.ExceptionUniquenessPlugin)
  .dependsOn(runner)
  .settings(
    commonSettings,
    dockerSettings,
    name := "repcheck-db-migrations-app",
    Compile / mainClass := Some("repcheck.db.migrations.MigrationApp"),
    Docker / packageName := "repcheck-db-migrations-runner",
    exceptionUniquenessRootPackages := Seq("repcheck.db.migrations"),
    publish / skip := true,
    // MigrationApp is a thin wiring entry point — all logic lives in
    // MigrationRunner and ConnectionRetry. It is excluded from coverage
    // because there is no testable logic beyond environment-variable reading
    // and Cats Effect wiring.
    coverageExcludedFiles := ".*MigrationApp.*",
    coverageEnabled := false
  )

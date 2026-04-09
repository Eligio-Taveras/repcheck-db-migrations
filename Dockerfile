# Multi-stage build for repcheck-db-migrations
#
# Produces a Cloud Run Job image that runs Liquibase migrations against a target
# PostgreSQL-compatible database (AlloyDB in staging/prod, Cloud SQL in dev,
# AlloyDB Omni locally).
#
# Usage:
#   docker build -t repcheck/db-migrations:local .
#   docker run --rm --network host \
#     -e DATABASE_HOST=localhost \
#     -e DATABASE_USER=postgres \
#     -e DATABASE_PASSWORD=postgres \
#     repcheck/db-migrations:local
#
# Stage 1: Build a staged runtime layout with sbt-native-packager.
FROM sbtscala/scala-sbt:eclipse-temurin-21.0.2_13_1.9.9_3.4.1 AS build
WORKDIR /app
COPY . .
RUN sbt "repcheckdbmigrations/stage"

# Stage 2: Runtime on Google Distroless Java 21
FROM gcr.io/distroless/java21-debian12
WORKDIR /app

# Copy only the staged libs — no launcher script, we invoke the JVM directly.
COPY --from=build /app/repcheck-db-migrations/target/universal/stage/lib /app/lib

# Cloud Run Jobs expect a foreground process. We bypass the bin/ launcher script
# (which uses bash) because Distroless has no shell. Instead we launch java
# directly with the full classpath glob.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-cp", "/app/lib/*", "repcheck.db.migrations.MigrationApp"]

#!/bin/bash
# Mirrors ansible/roles/postgresql-primary init (local run).
# Users: replicator (streaming), app1 (app DB), monitoring (exporter).
# Passwords come from the root .env via compose environment.
set -e
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD '${PG_REPLICATION_PASSWORD:-changeme}';
CREATE ROLE monitoring WITH LOGIN PASSWORD '${PG_MONITORING_PASSWORD:-changeme}';
GRANT CONNECT ON DATABASE postgres TO monitoring;
ALTER ROLE monitoring WITH CREATEROLE;
ALTER ROLE monitoring WITH SUPERUSER;
GRANT pg_monitor TO monitoring;
SELECT pg_create_physical_replication_slot('replica_slot_local');
SQL

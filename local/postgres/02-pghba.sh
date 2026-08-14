#!/bin/bash
# Appends network auth to pg_hba.conf (docker entrypoint regenerates the
# file, so this runs as an init script while the server is up, then reloads
# it). Mirrors the ansible role's pg_hba template for the lab.
set -e
cat >> "$PGDATA/pg_hba.conf" <<'EOF'
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256
host    replication     replicator      0.0.0.0/0               scram-sha-256
host    replication     replicator      ::/0                    scram-sha-256
EOF
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_reload_conf();" >/dev/null
echo "pg_hba.conf extended + reloaded"
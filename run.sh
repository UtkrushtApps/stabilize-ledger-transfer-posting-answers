#!/usr/bin/env bash
set -euo pipefail

cd /root/task

echo "Starting PostgreSQL assessment environment..."
docker compose up -d

echo "Waiting for PostgreSQL to become ready..."
for i in $(seq 1 60); do
  if docker compose exec -T postgres pg_isready -U assessor -d ledgerlab >/dev/null 2>&1; then
    echo "PostgreSQL is accepting connections."
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "PostgreSQL did not become ready in time." >&2
    docker compose ps >&2
    docker compose logs postgres >&2
    exit 1
  fi
  sleep 2
done

echo "Validating initialized database objects..."
docker compose exec -T postgres psql -U assessor -d ledgerlab -v ON_ERROR_STOP=1 -c "SELECT count(*) AS tenants FROM tenants;" >/dev/null
docker compose exec -T postgres psql -U assessor -d ledgerlab -v ON_ERROR_STOP=1 -c "SELECT count(*) AS ledger_entries FROM ledger_entries;" >/dev/null
docker compose exec -T postgres psql -U assessor -d ledgerlab -v ON_ERROR_STOP=1 -c "SELECT proname FROM pg_proc WHERE proname = 'process_transfer';" >/dev/null

echo "Database deployment complete."
docker compose ps


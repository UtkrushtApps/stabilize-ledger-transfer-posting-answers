-- Inspect the current transfer posting workflow.
SELECT pg_get_functiondef('process_transfer(bigint)'::regprocedure);

-- Confirm the retry/concurrency guardrails on transfer ledger legs.
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'ledger_entries'
  AND indexname IN ('ledger_entries_one_debit_per_transfer_idx', 'ledger_entries_one_credit_per_transfer_idx')
ORDER BY indexname;

-- Reset the deterministic conflict scenario before each investigation run.
SELECT reset_deadlock_demo();

-- Session A: run this statement in one transaction or client session.
-- SELECT process_transfer(900001);

-- Session B: run this statement at nearly the same time in another transaction or client session.
-- The fixed function locks account balance rows in account_id order, so this should
-- wait/serialize behind Session A instead of deadlocking.
-- SELECT process_transfer(900002);

-- Control transfer that does not touch the same account pair.
SELECT process_transfer(900003);

-- Current state of the demo transfer requests.
SELECT transfer_id, from_account_id, to_account_id, amount, status, posted_at
FROM transfer_requests
WHERE transfer_id IN (900001, 900002, 900003)
ORDER BY transfer_id;

-- Balance view for the accounts used by the demo scenario.
SELECT a.account_id, a.tenant_id, a.external_account_ref, b.available_balance, b.updated_at
FROM accounts a
JOIN account_balances b ON b.account_id = a.account_id
WHERE a.account_id IN (1,2,3,4)
ORDER BY a.account_id;

-- Ledger-entry consistency check for the demo transfers.
SELECT transfer_id,
       count(*) AS entry_count,
       count(*) FILTER (WHERE direction = 'debit') AS debit_entries,
       count(*) FILTER (WHERE direction = 'credit') AS credit_entries,
       sum(CASE WHEN direction = 'credit' THEN amount ELSE -amount END) AS net_amount
FROM ledger_entries
WHERE transfer_id IN (900001, 900002, 900003)
GROUP BY transfer_id
ORDER BY transfer_id;

-- Run while a conflict test is active to observe waiting sessions and row-level contention.
SELECT a.pid,
       a.state,
       a.wait_event_type,
       a.wait_event,
       age(clock_timestamp(), a.query_start) AS query_age,
       left(a.query, 120) AS query_text
FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.pid <> pg_backend_pid()
ORDER BY a.query_start NULLS LAST;

-- Lock summary for the balance and transfer tables during a concurrent run.
SELECT l.locktype,
       l.relation::regclass AS relation_name,
       l.mode,
       l.granted,
       count(*) AS lock_count
FROM pg_locks l
WHERE l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND (l.relation IN ('account_balances'::regclass, 'transfer_requests'::regclass, 'ledger_entries'::regclass) OR l.relation IS NULL)
GROUP BY l.locktype, l.relation, l.mode, l.granted
ORDER BY l.granted, relation_name, l.mode;

-- Recent execution statistics for the posting workflow, if available after test runs.
SELECT calls,
       round(total_exec_time::numeric, 2) AS total_exec_ms,
       round(mean_exec_time::numeric, 2) AS mean_exec_ms,
       rows,
       left(query, 140) AS query_text
FROM pg_stat_statements
WHERE query ILIKE '%process_transfer%'
ORDER BY total_exec_time DESC
LIMIT 10;


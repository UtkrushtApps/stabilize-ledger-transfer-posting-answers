# Solution Steps

1. Identify the deadlock source in process_transfer: it locks the transfer row, then updates the debit account balance first and the credit account balance second. Opposite-direction transfers for the same two accounts therefore acquire account_balances row locks in opposite orders.

2. Keep the transfer row SELECT ... FOR UPDATE because it serializes retries for the same transfer_id and preserves idempotent behavior for already-posted transfers.

3. Before applying any balance delta, select the two account_balances rows touched by the transfer with FOR UPDATE ordered by account_id. This establishes a single global lock order for all transfers, independent of transfer direction.

4. After the deterministic pre-lock succeeds, update both account balance rows in one statement using a CASE expression: subtract the amount from from_account_id and add it to to_account_id. Check that exactly two rows were updated.

5. Use one v_posted_at timestamp for the balance updates, both ledger entries, and the transfer_requests posted_at value so the posted transfer is internally consistent.

6. Insert the debit and credit ledger entries in the same transaction after the balance update, and verify that exactly two ledger rows were inserted.

7. Add partial unique indexes on ledger_entries for one debit leg and one credit leg per non-null transfer_id. These indexes prevent duplicate transfer ledger legs during retry/concurrency mistakes while still allowing historical non-transfer rows with transfer_id IS NULL.

8. Leave the status='posted' early return in place. Concurrent calls for the same transfer serialize on the transfer row; the second caller observes posted status and returns without changing balances or inserting duplicate ledger entries.

9. Keep reset_deadlock_demo able to delete demo ledger/audit rows and reset demo balances so the provided workload can be run repeatedly.

10. Validate by resetting the demo, running process_transfer(900001) and process_transfer(900002) concurrently, and checking that both complete, account 1/2 balances reflect -125/+80 and +125/-80 respectively, and each transfer has exactly one debit and one credit ledger entry.


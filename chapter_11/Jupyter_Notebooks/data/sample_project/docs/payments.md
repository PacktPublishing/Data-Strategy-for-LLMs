# Payments

The payments service posts transactions to the ledger through the gateway.
Batch settlement runs at 02:00 UTC. Retries use exponential backoff with a
cap of 5 attempts. Reconciliation reports land in the finance bucket at 06:00.

Payment requests must carry an idempotency key. Duplicate keys within 24 hours
return the original response instead of creating a second charge.

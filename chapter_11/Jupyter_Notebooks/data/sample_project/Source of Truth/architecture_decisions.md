# Architecture decision records (authoritative, read-only)

## ADR-014 (March 2026): Gateway-issued JWTs replace the legacy auth-service

All service-to-service authentication goes through the API gateway using
OAuth 2.0 client-credentials with 15-minute JWTs. The legacy auth-service
and its session-cookie flow are retired. Reason: the February replay
incident and the security review that followed.

## ADR-009 (November 2025): One ledger, one writer

Only the payments service writes to the ledger. Every other service reads.

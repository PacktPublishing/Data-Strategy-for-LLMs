# Authentication (current)

Every service authenticates through the API gateway using OAuth 2.0
client-credentials. The gateway issues a JWT signed with the platform key,
and services validate the token locally. Tokens expire after 15 minutes.

Do not call the old auth-service directly. It was retired in March 2026
(see Source of Truth/architecture_decisions.md, ADR-014).

# Design review notes, March 2, 2026

Attendees: platform team, security, two service owners.

We reviewed the incident from February where session cookies were replayed
against the legacy auth-service. Security recommended moving every service
to gateway-issued JWTs. Decision recorded as ADR-014. The legacy auth-service
enters read-only mode immediately and is retired at the end of March.

# Authentication design

Services authenticate against the auth-service using session cookies.
The auth-service keeps a session table in Redis with a 24-hour TTL.
On login, the client receives a session cookie, and every downstream
service calls auth-service /validate on each request.

This design is simple and battle-tested. All new services should follow it.

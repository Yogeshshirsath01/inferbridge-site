---
title: Authentication
description: Bearer token auth, key prefixes, and 401 responses.
---


Every request outside of `POST /v1/users` is authenticated via a bearer
token:

```http
Authorization: Bearer ib_<32 base62 chars>
```

The key is minted by `POST /v1/users` and returned exactly once —
InferBridge stores only a SHA-256 hash. If you lose it, register a new
user. Keys issued before the 2026-04-23 rename are prefixed `agni_` and
remain valid indefinitely.

A missing, malformed, or revoked key returns 401:

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer

{"error":{"message":"invalid or missing API key","type":"authentication_error"}}
```

---


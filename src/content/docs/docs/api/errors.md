---
title: Errors & rate limits
description: Error envelope shape, error type enumeration, and rate-limit behaviour.
---

## Error envelope

Every error response follows the OpenAI shape:

```json
{
  "error": {
    "message": "…human-readable explanation…",
    "type":    "…see table below…",
    "code":    "…optional, see the validation case…"
  }
}
```

`type` is drawn from this enumeration:

| `type` | HTTP status | Meaning |
|---|---|---|
| `invalid_request_error` | 400 / 422 | Malformed request, unknown field, out-of-range value, invalid cursor, bad TTL, unknown mode / provider |
| `authentication_error` | 401 | Missing or invalid InferBridge API key |
| `permission_error` | 403 | Caller authenticated but lacks permission for the action (reserved; not used in MVP) |
| `not_found_error` | 404 | Resource does not exist or is owned by another user |
| `conflict_error` | 409 | Unique-constraint violation (duplicate email, duplicate commercial-provider key) |
| `residency_error` | 422 | Residency filter left the candidate list empty |
| `rate_limit_error` | 429 | Upstream rate-limit exhaustion after fallback. `Retry-After` header populated. |
| `provider_error` | 502 | Upstream 5xx / timeout after fallback exhaustion |
| `service_unavailable_error` | 503 | Mixed upstream failures or dependency failure |
| `api_error` | 500 | Unhandled server error (stack trace logged, **not** returned) |

The `code` field is populated for validation errors
(`code: "validation_error"`) to let clients distinguish schema failures
from semantic 422s without string-matching `message`.

Every error response — and every successful one — includes an
`X-Request-ID` response header you can correlate with `/v1/logs` rows
and with the server's JSON log stream.

## Rate limits

**None in MVP.** InferBridge currently enforces no per-user rate limits
of its own. Upstream provider rate limits still apply and will surface
as 429 `rate_limit_error` responses if every candidate is exhausted —
see the [chat completions error table](/docs/api/chat-completions/#chat-completion-errors).

Please be respectful with free-tier usage — we monitor aggregate
traffic and may reach out to heavy users. Paid tiers (post-MVP) will
add explicit per-user limits.

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

InferBridge enforces two sliding-window limits per user, both measured
over a rolling 60-second window:

| Limit | Free tier | Header on 429 |
|---|---:|---|
| Requests per minute (RPM) | **60** | `X-RateLimit-Limit-RPM: 60` |
| Tokens per minute (TPM)   | **100,000** | `X-RateLimit-Limit-TPM: 100000` |

The TPM check uses a pre-flight estimate of `len(content) // 4` summed
across every message in the request — a coarse heuristic that
under-counts dense content (code, non-Latin script). Output tokens
don't count toward TPM because they aren't known until the upstream
finishes generating.

When either limit is exhausted the gateway responds with **429
Too Many Requests** and the following envelope:

```json
{
  "error": {
    "message": "rate limit exceeded — try again in 28 seconds",
    "type": "rate_limit_error",
    "limit_type": "rpm"
  }
}
```

`limit_type` is `"rpm"` or `"tpm"` so callers can branch on which
budget tripped. Headers on the 429:

* `Retry-After: <seconds>` — when the oldest entry in the offending
  window expires. Always rounded up so a retry at exactly that delay
  cannot bounce again.
* `X-RateLimit-Limit-RPM`, `X-RateLimit-Limit-TPM` — the configured
  budget for context.

This per-user limiter is distinct from the upstream-provider 429 the
gateway surfaces when *every* candidate model returns 429 (see the
[chat completions error table](/docs/api/chat-completions/#chat-completion-errors));
both shapes use `type: rate_limit_error`, but only the per-user case
includes `limit_type`.

> **Heads-up — paid tiers.** Free-tier limits apply to every account
> today. When paid plans land, limits will be looked up per user.

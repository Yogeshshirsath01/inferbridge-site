---
title: Chat completions
description: OpenAI-compatible POST /v1/chat/completions — headers, streaming, errors.
---

The main gateway endpoint. Request shape is OpenAI-compatible; the
response carries the usual OpenAI fields plus an `inferbridge` block.

```http
POST /v1/chat/completions
Authorization: Bearer ib_...
Content-Type: application/json

{
  "model": "ib/balanced",
  "messages": [
    {"role": "user", "content": "In one sentence, what is InferBridge?"}
  ]
}
```

### Core request fields

| Field | Type | Notes |
|---|---|---|
| `model` | string | An InferBridge mode (`ib/cheap`, `ib/balanced`, `ib/premium`). To pin a specific provider/model, keep a mode here and add the `X-InferBridge-Override-Model` header. Legacy `agni/*` names are accepted until 2026-07-22. |
| `messages` | array | At least one message; `role ∈ {system, user, assistant, tool}` |
| `temperature` | float | `0.0 ≤ t ≤ 2.0` |
| `max_tokens` | int | ≥ 1 |
| `top_p` | float | `0.0 ≤ t ≤ 1.0` |
| `presence_penalty` | float | `-2.0 ≤ p ≤ 2.0` |
| `frequency_penalty` | float | `-2.0 ≤ p ≤ 2.0` |
| `seed` | int | Best-effort — only OpenAI honours it today |
| `stop` | string or list of strings | — |
| `n` | int | 1 ≤ n ≤ 10 |
| `stream` | bool | Enable SSE streaming (see below) |
| `user` | string | Arbitrary end-user label, forwarded upstream where supported |

Unknown top-level fields are rejected 422. Unknown per-message fields
(e.g. `name`, `tool_call_id`, `tool_calls`) pass through to the provider
unchanged.

### InferBridge-specific headers

| Header | Purpose |
|---|---|
| `X-InferBridge-Cache: true` | Opt-in cache lookup + store |
| `X-InferBridge-Cache-TTL: <seconds>` | Override cache TTL; clamped to `[60, 86400]`. Default 3600. |
| `X-InferBridge-Override-Model: provider:model` | Bypass the tier; dispatch directly to `provider` + `model` |
| `X-InferBridge-Residency: india` | Restrict routing to India-residency providers |
| `X-InferBridge-Timeout: <seconds>` | Per-request upstream timeout; clamped to `[1, 300]` |
| `X-Request-ID: <token>` | Client-supplied request ID. Must match `[A-Za-z0-9_-]{1,128}`; malformed values are silently replaced with a fresh UUID. Echoed back in the response header and persisted on the log row. |

Every `X-InferBridge-*` header above has a legacy `X-Agni-*` alias
that's read as a fallback until 2026-07-22. If both are sent, the
`X-InferBridge-*` value wins.

### Example

```shell
curl -X POST https://inferbridge.dev/v1/chat/completions \
  -H 'Authorization: Bearer ib_...' \
  -H 'Content-Type: application/json' \
  -H 'X-InferBridge-Cache: true' \
  -H 'X-Request-ID: demo-001' \
  -d '{
    "model": "ib/balanced",
    "messages": [{"role":"user","content":"In one sentence, what is InferBridge?"}],
    "temperature": 0.2
  }'
```

**200 OK**

```json
{
  "id": "chatcmpl-9abc...",
  "object": "chat.completion",
  "created": 1745218392,
  "model": "gpt-4o-mini",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "InferBridge is …"},
      "finish_reason": "stop"
    }
  ],
  "usage": {"prompt_tokens": 24, "completion_tokens": 17, "total_tokens": 41},
  "inferbridge": {
    "provider": "openai",
    "model": "gpt-4o-mini",
    "mode": "ib/balanced",
    "cache_hit": false,
    "latency_ms": 734,
    "cost_usd": "0.000142",
    "residency_actual": "global",
    "request_id": "demo-001"
  }
}
```

### The `inferbridge` response block

Every successful response — including cache hits and streamed final
chunks — carries this object:

| Field | Type | Meaning |
|---|---|---|
| `provider` | string | Provider that actually served the response (`"cache"` on a cache hit) |
| `model` | string | Model that served it. On cache hit, the original `provider:model` string. |
| `mode` | string | The mode from the request (`ib/balanced`, or `"override"` for `X-InferBridge-Override-Model`) |
| `cache_hit` | bool | `true` only on cache hits |
| `latency_ms` | int | Wall-clock ms from request entry to response assembly |
| `cost_usd` | string | USD, as a fixed-point string with six decimal places. `"0.000000"` when the upstream didn't report token counts (e.g. OpenAI streaming without `stream_options.include_usage=true`) or when the provider's pricing is unknown (`self_hosted`). Same shape as `/v1/stats` and `/v1/logs` for byte-exact aggregation. |
| `residency_actual` | string | The residency bucket that served the request — `global`, `india`, or `cache` |
| `request_id` | string | Same value echoed in the `X-Request-ID` response header |

> **Breaking change in v0.2.0.** This block used to be keyed `"agni"`.
> No alias is shipped — update your parsers.

### Streaming

Set `"stream": true` in the body. InferBridge returns `text/event-stream`
with OpenAI-shaped deltas. The **final chunk before `data: [DONE]`**
carries the `inferbridge` metadata block on the `choices[0].delta`
object, so a single parser can extract it without special-casing.

```shell
curl -N -X POST https://inferbridge.dev/v1/chat/completions \
  -H 'Authorization: Bearer ib_...' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "ib/balanced",
    "stream": true,
    "messages": [{"role":"user","content":"Give me three colours."}]
  }'
```

Fallback behavior during streaming: if the primary candidate errors
**before the first token**, InferBridge tries the next candidate
transparently. After the first token has already been sent to the
client, errors propagate and the stream ends.

### Chat completion errors

| Status | `type` | When |
|---|---|---|
| 401 | `authentication_error` | Missing / bad InferBridge key |
| 422 | `invalid_request_error` | Body validation (unknown field, bad TTL, bad override format, unknown mode, unknown override provider) |
| 422 | `residency_error` | `X-InferBridge-Residency: india` set but no India-residency keys registered for the tier |
| 429 | `rate_limit_error` | Every candidate returned 429 (upstream-exhausted). `Retry-After` header is populated with `min(upstream retry-afters)`. |
| 500 | `api_error` | Unhandled server error |
| 502 | `provider_error` | Upstream 5xx / timeout after fallback exhaustion |
| 503 | `service_unavailable_error` | Mixed upstream failures during fallback exhaustion |

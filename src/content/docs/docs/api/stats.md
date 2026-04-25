---
title: Stats
description: Per-user aggregates — totals, by mode, by provider, by residency.
---

Aggregates scoped to the authenticated user over a bounded time range.

```http
GET /v1/stats?since=2026-04-14T00:00:00Z&until=2026-04-21T00:00:00Z
Authorization: Bearer ib_...
```

- Both `since` and `until` are ISO 8601 datetimes with an explicit
  timezone offset. Naive datetimes are rejected 422.
- Defaults: `until = now`, `since = until - 7 days` if unspecified.
- Maximum span: 90 days (422 if exceeded).
- `since < until` is enforced.

**200 OK**

```json
{
  "range": {
    "since": "2026-04-14T06:33:12.046069Z",
    "until": "2026-04-21T06:33:12.046069Z"
  },
  "totals": {
    "requests": 0,
    "cost_usd": "0.000000",
    "input_tokens": 0,
    "output_tokens": 0,
    "cache_hits": 0,
    "cache_hit_rate": 0.0,
    "avg_latency_ms": 0
  },
  "by_mode": {},
  "by_provider": {},
  "by_residency": {},
  "by_status": {},
  "pricing": {"last_updated": "2026-04-18"}
}
```

Notes worth knowing:

- `totals.cost_usd` is a **fixed-point string** with six decimal places —
  integer-ish clients can parse as Decimal, float-averse clients keep
  exactness. Same applies to `cost_usd` in `/v1/logs`.
- `avg_latency_ms` **excludes cache hits** (sub-millisecond by
  definition). Cache activity is visible in `cache_hits` and
  `cache_hit_rate`.
- `pricing.last_updated` is the date the cost table was last refreshed.
  Audit freshness before trusting the cost totals for billing.
- Historical rows predating v0.2.0 carry `agni/*` mode strings in the
  `by_mode` breakdown; InferBridge does not rewrite existing data, so
  `by_mode` may contain both `ib/balanced` and `agni/balanced` keys
  during the compatibility window.

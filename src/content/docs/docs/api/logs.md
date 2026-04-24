---
title: Logs
description: Reverse-chronological request logs with opaque cursor pagination.
---


Reverse-chronological `request_logs` rows with opaque cursor pagination.

```http
GET /v1/logs?since=2026-04-20T00:00:00Z&limit=50
Authorization: Bearer ib_...
```

- `since` — optional ISO 8601 with tz.
- `limit` — default 100, max 1000 (422 if exceeded).
- `cursor` — opaque string from the previous page's `next_cursor`. When
  absent, start from the newest row.

**200 OK**

```json
{
  "data": [
    {
      "id": 142,
      "mode": "ib/balanced",
      "provider": "openai",
      "model": "gpt-4o-mini",
      "input_tokens": 24,
      "output_tokens": 17,
      "latency_ms": 734,
      "cost_usd": "0.000142",
      "cache_hit": false,
      "status": "success",
      "error": null,
      "residency_requested": null,
      "residency_actual": "global",
      "created_at": "2026-04-21T06:35:00.123456Z"
    }
  ],
  "next_cursor": "eyJ0IjoiMjAyNi0wNC0yMVQwNjozNTowMC4xMjM0NTZaIiwiaSI6MTQyfQ"
}
```

### Paginating through every row

Walk until `next_cursor` is `null`:

```shell
# Page 1
curl "https://inferbridge.dev/v1/logs?limit=100" \
  -H 'Authorization: Bearer ib_...'
# → {"data":[... 100 rows ...],"next_cursor":"eyJ0I..."}

# Page 2 — use the cursor from page 1
curl "https://inferbridge.dev/v1/logs?limit=100&cursor=eyJ0I..." \
  -H 'Authorization: Bearer ib_...'
# → {"data":[... 100 rows ...],"next_cursor":"eyJ0J..."}

# Keep walking until next_cursor is null.
```

The cursor is a base64url-encoded JSON blob; don't parse it — treat it
as opaque so we can change the contents later without breaking you. A
malformed cursor returns 422 `invalid_request_error`.

### Edge case — last page exact-limit match

When the final page returns exactly `limit` rows, InferBridge still
emits a `next_cursor`. The next fetch will return
`{"data":[], "next_cursor":null}`. A single-query implementation can't
cheaply distinguish "exactly `limit` and no more" from "`limit` and
maybe more", so clients walk until empty.

---


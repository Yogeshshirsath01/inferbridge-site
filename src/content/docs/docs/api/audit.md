---
title: Audit export
description: Signed DPDP / GDPR compliance export — JSON or PDF, SHA-256 verifiable.
---

Signed compliance export of `request_logs` metadata over a bounded
window — built for DPDP / GDPR data-inventory obligations. Same data
visible via `/v1/logs`, but packaged with a SHA-256 signature so the
artefact stays verifiable after it leaves InferBridge's servers.

```http
GET /v1/audit/export?start_date=2026-01-01T00:00:00Z&end_date=2026-04-01T00:00:00Z
Authorization: Bearer ib_...
```

| Param | Required | Notes |
|---|---|---|
| `start_date` | yes | ISO 8601 datetime with timezone (e.g. `2026-04-01T00:00:00+00:00`) |
| `end_date` | yes | ISO 8601 datetime with timezone (e.g. `2026-04-01T00:00:00+00:00`); window ≤ 90 days |
| `format` | no | `json` (default) or `pdf` |
| `residency` | no | `india`, `global`, or `eu` — filters on `residency_actual` |

Both date params must include a timezone offset; naive datetimes return
422. Windows longer than 90 days return 422 — chain successive calls if
you need a longer history.

### Response shape (`format=json`)

```json
{
  "report_version": "1.0",
  "generated_at": "2026-04-25T11:32:08.144210+00:00",
  "user_id": "8294669a-6d77-43d3-a204-d4de7c94b7ef",
  "date_range": {
    "start": "2026-01-01T00:00:00+00:00",
    "end":   "2026-04-01T00:00:00+00:00"
  },
  "filters": {"residency": null},
  "summary": {
    "total_requests": 1283,
    "total_input_tokens": 412934,
    "total_output_tokens": 198430,
    "total_cost_usd": "12.483921",
    "cache_hits": 217,
    "by_provider": {"openai": 942, "anthropic": 230, "sarvam": 111},
    "by_residency": {"global": 1172, "india": 111},
    "by_status": {"success": 1262, "error": 21}
  },
  "records": [
    {
      "id": 142,
      "user_id": "8294669a-6d77-43d3-a204-d4de7c94b7ef",
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
      "request_id": "9f7c1a3e-4f3b-4e0e-8b62-7a5e96a4a2f0",
      "created_at": "2026-04-21T06:35:00.123456+00:00"
    }
  ],
  "signature": {
    "algorithm": "sha256",
    "value": "7f3c…b91"
  }
}
```

The signature value also surfaces in the `X-InferBridge-Audit-Signature`
response header.

### Verifying the signature

```python
import hashlib, json, requests
report = requests.get(
    "https://api.inferbridge.dev/v1/audit/export",
    params={"start_date": "2026-01-01T00:00:00+00:00",
            "end_date":   "2026-04-01T00:00:00+00:00"},
    headers={"Authorization": "Bearer ib_..."},
).json()

body = {k: v for k, v in report.items() if k != "signature"}
canonical = json.dumps(body, sort_keys=True, separators=(",", ":"))
expected = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
assert expected == report["signature"]["value"]
```

The canonicalisation rules: drop the `signature` key, JSON-serialize
with `sort_keys=True` and `separators=(",", ":")` (no whitespace),
SHA-256 the bytes, compare hex digests.

### PDF export

```shell
curl "https://api.inferbridge.dev/v1/audit/export?start_date=...&end_date=...&format=pdf" \
  -H 'Authorization: Bearer ib_...' \
  -o audit.pdf
```

Returns `application/pdf` (`Content-Disposition: attachment`). The PDF
embeds the same metadata + signature as the JSON form, formatted for
human review. The same `X-InferBridge-Audit-Signature` header is set on
the PDF response.

### What's NOT in the export

By design, audit records contain only metadata. Prompts, completions,
tool calls, and message bodies are **never** exported because they are
not stored — see [Security](#authentication) and the project's logging
policy. If you need conversation content for compliance review, that
must come from your own application logs, not from InferBridge.

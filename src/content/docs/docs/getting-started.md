---
title: Getting started
description: Thirty seconds from curl to first InferBridge response — register, BYOK, point your existing OpenAI SDK at the gateway.
---

InferBridge speaks the OpenAI Chat Completions protocol, so after a
two-step registration you can keep using your existing SDK code. This
walkthrough assumes you already have an OpenAI (or Anthropic, Together,
or Sarvam) API key.

## 1. Create an InferBridge user

The key is shown exactly once — save it somewhere before you close the
terminal.

```shell
curl -X POST https://api.inferbridge.dev/v1/users \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com"}'
# → {"user_id":"...","email":"...","api_key":"ib_...","shown_once":true}
```

## 2. Register a provider key

BYOK: InferBridge encrypts your provider key at rest and forwards
requests on your behalf. No markup, no proxying of your bill.

```shell
curl -X POST https://api.inferbridge.dev/v1/keys \
  -H 'Authorization: Bearer ib_...' \
  -H 'Content-Type: application/json' \
  -d '{"provider":"openai","api_key":"sk-..."}'
```

Supported `provider` values: `openai`, `anthropic`, `together`, `sarvam`,
`self_hosted`. Self-hosted keys need a `base_url` and a
`declared_region`. See [Users & provider keys](/docs/api/keys/) for the
full schema.

## 3. Point your existing OpenAI SDK at InferBridge

Python, before:

```python
from openai import OpenAI
client = OpenAI(api_key="sk-...")
```

Python, after:

```python
from openai import OpenAI

client = OpenAI(
    api_key="ib_...",
    base_url="https://api.inferbridge.dev/v1",
)

resp = client.chat.completions.create(
    model="ib/balanced",
    messages=[{"role": "user", "content": "Hello"}],
)
```

That's it. Streaming works unchanged (`stream=True`). InferBridge picks
the cheapest healthy provider for your tier, falls back if one errors,
caches repeated prompts on request (header: `X-InferBridge-Cache: true`),
and logs every call with tokens, cost, and latency.

Full Python / Node / cURL walkthrough with every response field
explained: [Migrating from OpenAI](/docs/migration/).

## Next steps

- **Route by tier** — pick `ib/cheap`, `ib/balanced`, or `ib/premium` in
  the `model` field. Or override per-request with
  `X-InferBridge-Override-Model: provider:model`.
- **Watch your spend** — `GET /v1/stats` for aggregates,
  `GET /v1/logs` for per-request rows. Both scoped to your user.
- **Go India-only** — send `X-InferBridge-Residency: india` to filter
  routing to Sarvam + self-hosted India endpoints.

Full API reference: [`/docs/api/authentication/`](/docs/api/authentication/).

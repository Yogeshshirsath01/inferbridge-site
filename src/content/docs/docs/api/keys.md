---
title: Users & provider keys
description: Register a user, register BYOK provider keys, list, and delete.
---

## Register a user

Create an InferBridge account and mint an API key.

```http
POST /v1/users
Content-Type: application/json

{"email": "you@example.com"}
```

```shell
curl -X POST https://api.inferbridge.dev/v1/users \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com"}'
```

**201 Created**

```json
{
  "user_id": "8294669a-6d77-43d3-a204-d4de7c94b7ef",
  "email": "you@example.com",
  "api_key": "ib_Ji3uubDajZx7N1XFcooqAVjKGkVFlC1D",
  "shown_once": true
}
```

`shown_once: true` is a reminder — the key is not retrievable later.

**Errors**

| Status | `type` | When |
|---|---|---|
| 409 | `conflict_error` | `email` is already registered |
| 422 | `invalid_request_error` | `email` is not a valid address |

## Register a provider key

Store a BYOK key for one of the supported providers. All provider keys
are Fernet-encrypted at rest; InferBridge decrypts them only in-memory
at request time.

```http
POST /v1/keys
Authorization: Bearer ib_...
Content-Type: application/json

{
  "provider": "openai",
  "api_key": "sk-..."
}
```

### Required fields per provider

| Provider | Required fields | Notes |
|---|---|---|
| `openai` | `provider`, `api_key` | — |
| `anthropic` | `provider`, `api_key` | — |
| `together` | `provider`, `api_key` | — |
| `groq` | `provider`, `api_key` | Fastest inference; free developer tier is rate-limited |
| `deepseek` | `provider`, `api_key` | Cheapest reasoning model — `deepseek-chat` and `deepseek-reasoner` (R1) |
| `cohere` | `provider`, `api_key` | Best for RAG workloads — `command-r-plus`, `command-r`, `command-light` |
| `mistral` | `provider`, `api_key` | EU data residency (`X-InferBridge-Residency: eu`) |
| `sarvam` | `provider`, `api_key` | Residency auto-set to `india` |
| `krutrim` | `provider`, `api_key` | OLA-backed second India provider — `Krutrim-spectre-v2`, `DeepSeek-R1` |
| `self_hosted` | `provider`, `api_key`, `base_url`, `declared_region` | See below |

### Optional fields

- `label` (string, ≤ 128 chars) — human-readable hint, especially useful
  for multiple self-hosted entries (`"mumbai-llama-70b"`,
  `"sgp-mistral-7b"`).

### Self-hosted endpoints

`self_hosted` registers an OpenAI-compatible endpoint you operate
yourself (vLLM, TGI, Ollama, llama.cpp, LM Studio, etc.):

```shell
curl -X POST https://api.inferbridge.dev/v1/keys \
  -H 'Authorization: Bearer ib_...' \
  -H 'Content-Type: application/json' \
  -d '{
    "provider": "self_hosted",
    "api_key": "sk-local-or-any-placeholder",
    "base_url": "https://llm.internal.mycompany.com/v1",
    "declared_region": "india",
    "label": "mumbai-llama-70b"
  }'
```

`base_url` must use HTTPS unless the host is `localhost` / `*.localhost`
or a private / loopback / link-local IP. Self-hosted keys are **never**
auto-routed — they're only reachable via
`X-InferBridge-Override-Model: self_hosted:<your-model-id>` on chat
completions.

### Response — 201 Created

```json
{
  "id": "5e4b02f9-2efb-4b69-8d6b-0a8e4e3e6ab2",
  "provider": "openai",
  "residency": "global",
  "declared_region": null,
  "base_url": null,
  "label": null,
  "created_at": "2026-04-21T06:33:12.046069Z"
}
```

**Errors**

| Status | `type` | When |
|---|---|---|
| 401 | `authentication_error` | Missing / bad InferBridge key |
| 409 | `conflict_error` | Duplicate commercial-provider key for this user |
| 422 | `invalid_request_error` | Unknown provider, missing `base_url`/`declared_region` on `self_hosted`, `base_url` set on non-`self_hosted`, or HTTP `base_url` on a public host |

Duplicate `self_hosted` entries are **allowed** — the unique index is
partial — so a user can register `mumbai-llama-70b`,
`bangalore-mistral-7b`, and `sgp-mixtral-8x7b` side-by-side.

## List provider keys

```shell
curl https://api.inferbridge.dev/v1/keys \
  -H 'Authorization: Bearer ib_...'
```

**200 OK**

```json
[
  {
    "id": "5e4b02f9-2efb-4b69-8d6b-0a8e4e3e6ab2",
    "provider": "openai",
    "residency": "global",
    "declared_region": null,
    "base_url": null,
    "label": null,
    "created_at": "2026-04-21T06:33:12.046069Z"
  }
]
```

Secrets are never returned.

## Delete a provider key

```shell
curl -X DELETE https://api.inferbridge.dev/v1/keys/5e4b02f9-2efb-4b69-8d6b-0a8e4e3e6ab2 \
  -H 'Authorization: Bearer ib_...'
```

**204 No Content** — empty body.
**404 Not Found** if the key doesn't exist or is owned by a different user.

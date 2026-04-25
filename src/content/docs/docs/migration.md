---
title: Migrating from OpenAI
description: Two-line migration from the OpenAI SDK to InferBridge — Python, Node, and cURL.
---

InferBridge speaks the OpenAI Chat Completions protocol, so moving an
existing app is almost always two lines: swap `api_key` and `base_url`.
The model string changes too — to an InferBridge mode like
`ib/balanced` — but your prompts, message arrays, temperature, tools
payloads, and parsing code stay exactly the same.

> **Renamed 2026-04-23.** InferBridge launched as **Agni AI** in v0.1.0.
> If you integrated before the rename, legacy surface keeps working
> until 2026-07-22: `agni_` API keys, `agni/*` mode names, and
> `X-Agni-*` headers are all still accepted. See the
> [changelog](changelog.md) for the removal calendar.

One-time setup first:

```shell
# 1) Mint an InferBridge API key.
curl -X POST https://api.inferbridge.dev/v1/users \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com"}'
# → copy api_key from response (shown exactly once)

# 2) Register your OpenAI key so InferBridge can forward traffic on your behalf.
curl -X POST https://api.inferbridge.dev/v1/keys \
  -H 'Authorization: Bearer ib_...' \
  -H 'Content-Type: application/json' \
  -d '{"provider":"openai","api_key":"sk-..."}'
```

Now the code changes. Two lines in every language.

---

## Python

Before:

```python
from openai import OpenAI

client = OpenAI(api_key="sk-...")

resp = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "Hello"}],
)
```

After:

```python
from openai import OpenAI

client = OpenAI(
    api_key="ib_...",                                            # ← line 1
    base_url="https://api.inferbridge.dev/v1",      # ← line 2
)

resp = client.chat.completions.create(
    model="ib/balanced",
    messages=[{"role": "user", "content": "Hello"}],
)
```

Streaming works unchanged (`stream=True`). The response carries an
extra `resp.inferbridge` block with provider, model, latency, and
cost — ignore it, or log it for observability.

> **Renamed response block.** The OpenAI SDK stores unknown response
> fields on a `.model_extra` dict, so `resp.model_extra["inferbridge"]`
> works from v0.2.0 on. Integrations built against v0.1.0 looking for
> `resp.model_extra["agni"]` will see `KeyError`; rename the lookup.

---

## Node.js (TypeScript or JS)

Before:

```ts
import OpenAI from "openai";

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const resp = await client.chat.completions.create({
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "Hello" }],
});
```

After:

```ts
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: process.env.INFERBRIDGE_API_KEY,                       // ← line 1
  baseURL: "https://api.inferbridge.dev/v1",        // ← line 2
});

const resp = await client.chat.completions.create({
  model: "ib/balanced",
  messages: [{ role: "user", content: "Hello" }],
});
```

---

## Using a specific model (override)

To pin a specific provider+model while keeping InferBridge's gateway,
use `model: "ib/balanced"` in the request body and add an
`X-InferBridge-Override-Model` header to force the exact provider/model
you want:

```python
resp = client.chat.completions.create(
    model="ib/balanced",
    messages=[{"role": "user", "content": "Hello"}],
    extra_headers={
        "X-InferBridge-Override-Model": "openai:gpt-4o-mini",
    },
)
```

This is also how you dispatch to a `self_hosted` endpoint.

---

## Caveats — what's not supported yet

- **Tool use / function calling.** Tool calls in the request pass
  through to providers that support them, but we haven't hardened the
  streaming-tool-use path. If you rely on `tool_calls` delivered over
  SSE, stay on the vendor SDK for now.
- **Vision inputs.** Image parts in messages aren't routed correctly
  across all providers today.
- **Embeddings.** No `/v1/embeddings` endpoint yet. Use the provider
  SDK directly.
- **Structured outputs / response format.** `response_format` passes
  through but has not been validated across providers.

Everything else — `temperature`, `max_tokens`, `top_p`, `stop`,
streaming, `seed`, `user`, `presence_penalty`, `frequency_penalty` —
works the same way as OpenAI.

---

## FAQ

**Do my prompts need changes?**
No. InferBridge is a transport layer. Whatever you were sending to
OpenAI goes through unchanged.

**Does `stream: true` still work?**
Yes. InferBridge returns SSE in the same wire format. The final chunk
before `data: [DONE]` carries the `inferbridge` metadata block on the
`choices[0].delta` object — ignore it if you don't need it.

**What about cost? Is there a markup?**
No. You pay your providers directly using your own BYOK keys.
InferBridge MVP is free. Costs in the `inferbridge.cost_usd` response
field are informational.

**How do I switch back to OpenAI?**
Revert the two lines. Nothing persistent changes on your provider side.

**What happens when OpenAI has an outage?**
For tier requests, InferBridge falls back to the next candidate
(default for `ib/balanced` is OpenAI → Sarvam → Anthropic). Override
requests get the vendor's error propagated verbatim.

**I integrated under the old name (Agni). Do I have to change anything?**
Not immediately. Until **2026-07-22** the gateway accepts `agni_` API
keys, `agni/*` model names, and `X-Agni-*` headers. The one exception
is the response metadata block, which is now keyed `"inferbridge"`
instead of `"agni"` with no alias — if your code reads
`resp.agni.something`, rename the lookup to `resp.inferbridge.something`.

**Is this production-ready?**
MVP. Tiered routing, non-streaming chat, streaming chat, fallback,
caching, observability, and logs are production-tested and are
suitable for real workloads. The streaming tool-use path is the one
area not yet hardened — avoid routing production function-calling
traffic through InferBridge until a future release covers it.

**Where do I report a bug?**
Email **hello@inferbridge.dev** with your `X-Request-ID` — every response
carries one, and it pivots directly to our log stream.

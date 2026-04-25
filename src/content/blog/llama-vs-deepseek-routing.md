---
title: "Llama 3.3 70B vs DeepSeek-R1: routing decisions for cost and reasoning"
description: "When to route to Llama 3.3 70B (Together/Groq) vs DeepSeek-R1 for cost-sensitive and reasoning-heavy workloads. Concrete routing examples using InferBridge tiers."
publishedAt: 2026-04-25
draft: false
tags: ["routing", "models", "cost", "deepseek", "llama"]
---

The cheap-tier slot in most LLM gateways gets one model. InferBridge's
`ib/cheap` tier holds six, and the order matters. The two most
useful endpoints to understand in that list are Llama 3.3 70B
Instruct (served by Groq and Together) and the DeepSeek family
(`deepseek-chat` for general use, `deepseek-reasoner` for
chain-of-thought). They cover different workloads, and routing the
wrong one is the most common cost mistake we see.

## What each model is good at

**Llama 3.3 70B Instruct** is Meta's latest open-weights chat model
in the 70B class. It's strong on summarisation, classification,
extraction, RAG-style question answering, and short-form chat. The
Groq deployment serves it at hundreds of tokens per second — fast
enough that streaming feels like local inference. Together serves
the same weights at a slightly slower rate but without the free-tier
rate cap. Either way, the model is the same; the routing choice is
about throughput and cost.

**DeepSeek-R1** (`deepseek-reasoner`) is a different beast. It's a
reasoning model — the streaming response includes a
`reasoning_content` field that exposes the chain-of-thought before
the final answer arrives. For mathematical problems, multi-step code
generation, and any task where the model benefits from "thinking
out loud," R1 outperforms general-purpose chat models of comparable
size. The trade-off is latency and tokens: the reasoning trace is
billed at the same per-token rate as the visible answer, and the
trace can easily be longer than the answer itself.

For everything that isn't reasoning-heavy, `deepseek-chat`
(DeepSeek-V3) is the cheaper alternative — no reasoning trace, much
shorter responses, similar quality on chat-style tasks.

## The cost numbers

Per-million-token rates from each provider's published pricing,
as encoded in the gateway's cost table:

| Model | Input | Output |
|---|---:|---:|
| `groq` / Llama 3.3 70B | $0.00 (free tier, rate-limited) | $0.00 |
| `together` / Llama 3.3 70B Instruct Turbo | $0.88 / M | $0.88 / M |
| `deepseek` / `deepseek-chat` | $0.27 / M | $1.10 / M |
| `deepseek` / `deepseek-reasoner` (R1) | $0.55 / M | $2.19 / M |

A 1k-input / 500-output request costs:

- Groq Llama 3.3 70B: **free** (subject to per-minute limits)
- Together Llama 3.3 70B: ~$0.0013
- `deepseek-chat`: ~$0.0008
- `deepseek-reasoner` (R1): ~$0.0017 *plus* the reasoning tokens,
  which often double the output count — realistic billed total is
  closer to $0.003–$0.004 per request

R1 isn't expensive in absolute terms, but on a high-volume workload
it's roughly 4× the cost of Groq Llama and 2–3× the cost of
DeepSeek-chat. The latency is also higher — first token is fast,
but the model writes a full reasoning paragraph before the answer
begins, so total response time is noticeably longer than non-
reasoning models.

## How to route

For most workloads, send everything to `ib/cheap` and let the
fallback chain do its job. The configured tier order is:

```
ib/cheap:
  groq      / llama-3.3-70b-versatile
  deepseek  / deepseek-chat
  together  / meta-llama/Llama-3.3-70B-Instruct-Turbo
  sarvam    / sarvam-m
  krutrim   / Krutrim-spectre-v2
  openai    / gpt-4o-mini
```

Groq serves the request when it has free-tier capacity. When Groq
returns 429 with a `retry-after` header, the gateway moves to
`deepseek-chat` immediately rather than waiting. If your DeepSeek
key is rate-limited or down, Together picks up Llama 3.3 70B at
the published per-token rate. The end client sees one consistent
response shape regardless of which provider served it — the
`inferbridge.provider` field in the response metadata tells you
which one did.

```bash
curl https://api.inferbridge.dev/v1/chat/completions \
  -H "Authorization: Bearer ib_..." \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ib/cheap",
    "messages": [
      {"role": "user", "content": "Summarise this in two bullets: ..."}
    ]
  }'
```

For reasoning workloads — math, multi-step code, anything where
you want the chain-of-thought back — bypass the tier entirely and
pin the request to R1 with the override header:

```bash
curl https://api.inferbridge.dev/v1/chat/completions \
  -H "Authorization: Bearer ib_..." \
  -H "Content-Type: application/json" \
  -H "X-InferBridge-Override-Model: deepseek:deepseek-reasoner" \
  -d '{
    "model": "ib/cheap",
    "messages": [
      {"role": "user", "content": "Prove that the sum of two odd integers is even."}
    ]
  }'
```

The `model` field still has to be set (the OpenAI schema requires
it), but `X-InferBridge-Override-Model` takes precedence. The tier
becomes a fallback for the override — if DeepSeek is unreachable
the gateway falls back through the tier list, but for non-
reasoning models the trace won't be there.

## A simple decision rule

If the task can be solved by a fast chat model — extraction,
summarisation, classification, RAG, drafting — send it to
`ib/cheap` and don't think about it further. If the task involves
multi-step reasoning that you want to inspect, override to
`deepseek:deepseek-reasoner`. Don't route reasoning workloads
through `ib/cheap` and hope Llama figures it out, and don't route
classification through R1 and pay 4× to read a reasoning trace
nobody will look at.

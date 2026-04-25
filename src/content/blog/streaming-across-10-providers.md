---
title: "Streaming LLM responses across 10 providers with one API"
description: "How InferBridge handles SSE streaming, fallback before first token, and provider-specific quirks across OpenAI, Anthropic, Groq, Mistral, DeepSeek, Cohere, Together, Sarvam, Krutrim, and self-hosted models."
publishedAt: 2026-04-25
draft: false
tags: ["engineering", "streaming", "providers"]
---

Streaming is the difference between a chat UI that feels alive and one
that feels broken. A model that produces 800 tokens at 60 tokens/second
takes ~13 seconds to finish; the same model streamed delivers the
first word in ~250ms. For interactive products the time-to-first-token
is the latency that matters — full-response latency is mostly a cost
metric.

InferBridge speaks Server-Sent Events on `/v1/chat/completions` whenever
the request includes `"stream": true`, and the wire format mirrors
OpenAI's exactly: a series of `data: {chunk}` lines, each chunk holding
a partial `choices[0].delta`, terminated by a literal `data: [DONE]`
line. The OpenAI Python SDK consumes this without modification, which
means swapping `base_url` and the API key is the only client-side
change.

## The fallback-before-first-token rule

A non-streaming request that fails on provider A can be retried on
provider B — the client never saw a partial response, so a clean
restart is invisible. Streaming breaks that property. Once the client
has received `data: {"choices":[{"delta":{"content":"The capital"}}]}`,
falling back to a different provider would force the client to either
discard those tokens (visible flicker, lost context) or splice in
content from a different model mid-sentence (incoherent output).

InferBridge handles this with a hard rule: **fallback is only attempted
if the error happens before the first chunk arrives.** Connection
refused, 5xx on the initial response, timeout before any bytes — those
all retry the next provider in the tier list. Errors after the first
chunk propagate directly to the client as a normal SSE error event.
This is enforced inside the streaming generator: the first `yield`
flips a flag, and once it's set the fallback path is no longer
reachable for that request.

The implication for callers: if you need stronger guarantees against
mid-stream failure, set a tighter `X-InferBridge-Timeout` so degraded
providers fail fast, before the first token ships.

## Provider quirks the gateway smooths over

The point of a unified API is that the client sees one shape. Behind
the gateway, each provider has its own surface, and a few are sharp
enough to be worth naming.

**Anthropic** doesn't accept `system` messages inside the `messages`
array. The Anthropic adapter pulls every `role: "system"` entry out,
joins them with `\n\n`, and sends the result as a top-level `system`
parameter. It also normalises `stop_reason` to OpenAI's
`finish_reason` field — `max_tokens` becomes `length`, anything else
(`end_turn`, `stop_sequence`, etc.) becomes `stop`. The streaming
generator emits the same finish reason in the terminal chunk that
non-streaming emits in `choices[0]`.

**DeepSeek-R1** (`deepseek-reasoner`) emits an extra `reasoning_content`
field alongside `content` on every delta. This is the model's
chain-of-thought, and it's billed at the same per-token rate as the
visible answer. The DeepSeek adapter passes `reasoning_content`
through unchanged so clients that care about the trace can render it,
and clients that don't can ignore it. The token count returned in the
final `usage` block includes reasoning tokens, which is why R1
responses cost more than they look.

**Groq** rate-limits aggressively on the free tier — single-digit
requests per minute on some models. When Groq returns HTTP 429, the
response includes a `retry-after` header, and InferBridge surfaces
that to the fallback layer. If the request was made under
`ib/cheap`, the gateway moves to the next provider (DeepSeek →
Together → Sarvam → Krutrim → OpenAI) instead of waiting. Same code
path handles 429s from every other provider, but Groq is the one most
likely to trigger it during prototyping.

## A minimal client

Drop-in OpenAI SDK usage looks like this:

```python
from openai import OpenAI

client = OpenAI(
    api_key="ib_...",
    base_url="https://api.inferbridge.dev/v1",
)

stream = client.chat.completions.create(
    model="ib/cheap",
    messages=[{"role": "user", "content": "Explain SSE in one paragraph."}],
    stream=True,
)

for chunk in stream:
    delta = chunk.choices[0].delta
    if delta.content:
        print(delta.content, end="", flush=True)
```

That's the entire integration. The `model` field accepts a tier name
(`ib/cheap`, `ib/balanced`, `ib/premium`) or — via the
`X-InferBridge-Override-Model` header — an explicit
`provider:model` string for cases where you need a specific backend.

The terminal chunk arrives with `delta = {}` and `finish_reason` set,
followed by the `data: [DONE]` line. If you're parsing SSE manually
rather than using the SDK, that's the loop exit condition.

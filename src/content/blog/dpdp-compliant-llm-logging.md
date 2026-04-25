---
title: "DPDP-compliant LLM request logging: what to store and what to never store"
description: "India's DPDP Act and what it means for teams using LLMs in production. How InferBridge logs metadata without storing prompts or completions, and how the audit export endpoint generates a signed compliance artifact."
publishedAt: 2026-04-25
draft: false
tags: ["compliance", "dpdp", "india", "privacy"]
---

The Digital Personal Data Protection Act (DPDP, India 2023) applies the
moment a user types a prompt that mentions a name, an address, or any
identifier tied to a real person. That includes most production
chatbots, support tools, and internal copilots. The Act doesn't care
that the data went to a third-party model; it cares that you, the
operator, processed it. Storing those prompts in your application logs
turns every log archive into a regulated dataset.

InferBridge's logging design takes the simplest path through that
problem: we never see the content as logged data, and neither does
your database.

## What DPDP actually requires

Three obligations matter for an LLM operator:

1. **Data minimisation** — collect and retain only what's necessary for
   the stated purpose. Operational metrics (latency, cost, error
   rates) are necessary. The text of the prompt is, in almost every
   case, not.
2. **Purpose limitation** — data collected for one purpose cannot be
   reused for another without re-consent. If you log prompts to debug
   a routing bug, you cannot then mine them to train a model.
3. **Audit trail** — a Data Principal can request a record of the
   processing that involved their data. You need a way to produce that
   record on demand, scoped to a date range and verifiably untampered.

The cheapest way to satisfy all three is to never store the
sensitive part in the first place.

## The content-not-logged invariant

Every InferBridge request produces one row in the `request_logs`
table. The columns are deliberate:

```
request_id            uuid (propagated as X-Request-ID end-to-end)
created_at            timestamp with time zone
user_id               uuid (the InferBridge account, not the end user)
mode                  text  (ib/cheap | ib/balanced | ib/premium | override)
provider              text  (openai | anthropic | deepseek | ...)
model                 text  (resolved model name)
status                text  (success | error | rate_limited)
input_tokens          int
output_tokens         int
cost_usd              numeric (6dp string on the wire)
latency_ms            int
cache_hit             boolean
residency_requested   text   (india | global | eu | null)
residency_actual      text   (where the request was actually served)
error                 text   (provider error code, no payload)
```

There is no `prompt` column. There is no `completion` column. The
adapter that calls each provider is the only code that holds the
request body in memory, and that body is dropped as soon as the
upstream call returns. Token counts come from the provider's `usage`
field; they're a number, not the underlying text.

This is a hard property of the schema, not a configurable one. There
is no "log content for debugging" flag in production. If a request
fails, what gets logged is the provider error code and the HTTP
status — enough to triage routing or auth issues, never enough to
reconstruct what the user asked.

The trade-off is real: you cannot replay a prompt from logs to
reproduce a bug. You can replay the *shape* of the request (model,
mode, residency), and for most production triage that turns out to
be sufficient. The PII liability you avoid is worth more than the
debugging convenience you give up.

## The audit export endpoint

When a Data Principal — or an internal compliance team, or a
regulator — asks for the processing record, you need a signed
artifact, not a CSV exported from a query tool. `GET /v1/audit/export`
produces that artifact:

```bash
curl "https://inferbridge.dev/v1/audit/export?start_date=2026-04-01T00:00:00+00:00&end_date=2026-04-15T00:00:00+00:00" \
  -H "Authorization: Bearer ib_..." \
  -o audit.json
```

The response is a JSON document with four sections: a date range, a
filter description, the per-request rows (the same metadata fields
listed above, never content), and a SHA-256 signature computed over
the canonical body. The signature uses sorted keys and no whitespace,
so any later mutation — reordering, pretty-printing, dropping a
row — invalidates it. The signature itself is excluded from the
canonical input, so verifiers can recompute it deterministically.

For a printable artifact, append `&format=pdf`. The PDF embeds the
same signature in a header block alongside the row table; both
formats also surface the signature in the
`X-InferBridge-Audit-Signature` response header so it can be archived
separately from the body.

A typical compliance flow:

1. Operator receives a Data Principal request referencing a date.
2. Operator calls `/v1/audit/export` with that day's window and,
   optionally, `&residency=india` to scope to in-country processing.
3. Operator hands the file (and the header signature) to the
   requester. The Data Principal — or their auditor — recomputes the
   SHA-256 over the canonical body and compares.

Maximum window is 90 days per call; longer ranges are intentionally
rejected so that auditable artifacts stay reviewable in a sitting.
For multi-quarter exports, chain successive calls — each one is
independently signed.

## What this doesn't do

The audit export tells you *that* a request happened, not what was
in it. If your application separately needs to retain the prompt
text for legitimate business reasons — say, customer support
transcripts the user explicitly consented to retain — that storage
is your responsibility, scoped to your application, with its own
DPDP posture. The gateway logs are deliberately a thin layer;
content retention belongs in the product, not the routing
infrastructure.

The signed metadata stream is enough to answer "did we process
data on this date, with this model, in this region?" — which is
the question DPDP enforcement actually asks.

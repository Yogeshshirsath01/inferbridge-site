---
title: InferBridge Docs
description: One OpenAI-compatible API for OpenAI, Anthropic, Together, Sarvam, and self-hosted models. Drop-in gateway with routing, caching, and observability.
hero:
  tagline: One API for every LLM — global, open-source, and Indian.
  actions:
    - text: Get started
      link: /docs/getting-started/
      icon: right-arrow
      variant: primary
    - text: Migrate from OpenAI
      link: /docs/migration/
      icon: external
      variant: minimal
---

InferBridge is a drop-in, OpenAI-compatible gateway. Point your existing
OpenAI SDK at `https://api.inferbridge.dev/v1`, keep your prompts and
streaming code unchanged, and get tier-based routing, per-request
caching, residency filtering, and per-call observability across OpenAI,
Anthropic, Together, Sarvam, and your own self-hosted endpoints.

## What's here

- **[Getting started](/docs/getting-started/)** — thirty seconds from `curl` to first response.
- **[Migrating from OpenAI](/docs/migration/)** — the two-line patch for Python and Node.
- **[API reference](/docs/api/authentication/)** — every endpoint, every header, every response field.
- **[Changelog](/docs/changelog/)** — releases, breaking changes, and deprecation windows.

---

*InferBridge was released as Agni AI in v0.1.0; the rename shipped in
v0.2.0 on 2026-04-23. Legacy `agni_*` keys, `agni/*` modes, and
`X-Agni-*` headers remain accepted until 2026-07-22. See the
[changelog](/docs/changelog/) for the full compatibility matrix.*

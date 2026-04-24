---
title: Changelog
description: All user-visible changes to InferBridge, by release.
---


All user-visible changes to InferBridge (formerly Agni AI) land here.
Dates are UTC.

## v0.2.0 — 2026-04-23

Product rename: **Agni AI → InferBridge**. The rename is positioning
only; behaviour is unchanged. This release ships the new names
everywhere and backwards-compatible aliases for the old ones. One
surface — the attached response metadata block — is a **breaking
change**; see below.

### Breaking change

- The non-standard response metadata block is now keyed **`inferbridge`**
  (was `agni`). If your code reads `response.json()["agni"]`, rename
  that lookup to `response.json()["inferbridge"]`. The block's contents
  are unchanged:
  ```json
  "inferbridge": {
    "provider": "openai",
    "model":    "gpt-4o-mini",
    "mode":     "ib/balanced",
    "cache_hit": false,
    "latency_ms": 734,
    "cost_usd": "0.000142",
    "residency_actual": "global",
    "request_id": "..."
  }
  ```
  No alias is shipped for this field — an alias would inflate every
  response payload permanently, and the fix for callers is a one-line
  string change.

### Backwards-compatible renames (deprecated, removal 2026-07-22)

All of these keep working until **2026-07-22**. Structured warnings are
logged (logger `inferbridge.aliases`) whenever the legacy form is used,
so you can grep your ops stream to find remaining callers before the
removal date.

- **API-key prefix.** Newly-issued keys are prefixed **`ib_`**; keys
  issued before the rename (prefixed `agni_`) authenticate indefinitely,
  since they remain valid until the user rotates them.
- **Tier names.** The canonical modes are **`ib/cheap`**,
  **`ib/balanced`**, **`ib/premium`**. Incoming `agni/*` mode strings
  are normalized to their `ib/*` equivalent at the chat endpoint.
- **Request headers** (legacy → canonical):
  - `X-Agni-Residency` → `X-InferBridge-Residency`
  - `X-Agni-Override-Model` → `X-InferBridge-Override-Model`
  - `X-Agni-Cache` → `X-InferBridge-Cache`
  - `X-Agni-Cache-TTL` → `X-InferBridge-Cache-TTL`
  - `X-Agni-Timeout` → `X-InferBridge-Timeout`

  If both the new and legacy header are sent, the new header wins.

- **Environment variable.** `AGNI_ENCRYPTION_KEY` → `INFERBRIDGE_ENCRYPTION_KEY`.
  Both names are read at startup; the new name wins if both are set, the
  old name logs a deprecation warning and is used as a fallback.

- **Python package.** The distribution is now named **`inferbridge`**
  (was `agni`) in `pyproject.toml`. The in-repo module path stays `app/`.

### Unchanged on purpose

- **Database schema.** No column or table renames. The `users.agni_key_hash`
  column retains its Agni-era name — a column rename would require a
  schema migration against a production DB, and the column name is
  private to the server. The column stores SHA-256 hashes of whatever
  key prefix the user registered with (`ib_` or legacy `agni_`); neither
  the prefix nor the rename changes the hash format.
- **Git repository and Railway URL.** Unchanged. A custom
  `inferbridge.*` domain will be added in a follow-up; the Railway
  hostname stays as a stable secondary for existing integrations.

### Removal calendar (2026-07-22)

On that date a follow-up PR removes, in a single commit:

- The `app/core/aliases.py` shim module.
- The `x_agni_*` `Header(...)` parameters on `POST /v1/chat/completions`.
- The `AGNI_ENCRYPTION_KEY` field and reconciliation validator on `Settings`.
- The legacy `agni_` branch in `has_valid_key_prefix` (pre-rename keys
  remain valid — only the prefix check goes; the hash comparison is
  unchanged).

Expect the 2026-07-22 change to bump us to v0.3.0.

---

## v0.1.0 — 2026-04-21

First public release under the **Agni AI** brand. MVP feature set:

### Gateway

- `POST /v1/chat/completions` — OpenAI-compatible non-streaming and
  SSE-streaming. Body passes through; response carries an extra `agni`
  block with provider, model, mode, `cache_hit`, latency, cost,
  `residency_actual`, and `request_id`. (Renamed to `inferbridge` in
  v0.2.0.)
- Tier-based routing (`agni/cheap`, `agni/balanced`, `agni/premium`)
  across the candidate providers the caller has registered keys for.
  (Renamed to `ib/*` in v0.2.0.)
- Per-request `X-Agni-Override-Model: provider:model` to pin a specific
  upstream — including `self_hosted` endpoints, which are override-only.
- Residency filtering via `X-Agni-Residency: india`. Returns 422
  `residency_error` if no registered key matches.
- Fallback across candidates on transient errors (5xx, timeouts, 429).
  Budget: max 2 provider attempts per request. Streaming fallback stops
  after the first token.
- Opt-in exact-match cache via `X-Agni-Cache: true`. TTL default 3600 s,
  configurable via `X-Agni-Cache-TTL` (clamped `[60, 86400]`).
  Redis outages never block requests.
- Per-request upstream timeout via `X-Agni-Timeout: <seconds>` (clamped
  `[1, 300]`). Belt-and-suspenders: `asyncio.wait_for` backs up the
  `httpx` client timeout.

### Providers

- OpenAI (`gpt-4o`, `gpt-4o-mini`, …)
- Anthropic (`claude-opus-4-7`, `claude-haiku-4-5`) — OpenAI-shaped I/O
  with system-prompt extraction, `max_tokens` default, and
  `usage.input_tokens` / `usage.output_tokens` normalization.
- Together (`meta-llama/Llama-3.3-70B-Instruct-Turbo`, …)
- Sarvam (`sarvam-m`) — India-residency, free-per-token.
- Self-hosted — any OpenAI-compatible endpoint (vLLM, TGI, Ollama,
  llama.cpp, LM Studio, …). `base_url` required; HTTPS enforced unless
  the host is loopback or a private IP.

### User + key management

- `POST /v1/users` — register; returns `agni_<32 chars>` API key exactly
  once. Stored as SHA-256 hash. (Prefix changed to `ib_` in v0.2.0;
  keys issued under v0.1 remain valid.)
- `POST /v1/keys`, `GET /v1/keys`, `DELETE /v1/keys/{id}` — BYOK
  provider-key CRUD. Fernet-encrypted at rest. Partial unique index
  prevents duplicate commercial-provider keys per user while allowing
  multiple `self_hosted` entries.

### Observability

- `GET /v1/stats?since=&until=` — totals, `cache_hit_rate`,
  `avg_latency_ms` (excl. cache hits), and group-by counts (`by_mode`,
  `by_provider`, `by_residency`, `by_status`). Max 90-day window.
- `GET /v1/logs?since=&limit=&cursor=` — reverse-chronological row
  stream with opaque cursor pagination; limit default 100, max 1000.
- `X-Request-ID` threads through the response header, structured logs
  (JSON in production via structlog), and the `request_logs` row.
- Prompts and completions are **never** logged. Pinning test
  (`test_prompts_and_completions_never_reach_log_output`) prevents
  regressions.

### Ops

- Docker image (multi-stage, uv-built, ~250 MB, non-root).
- `scripts/start.sh` runs `alembic upgrade head` before `uvicorn`.
- Railway deploy: [railway.toml](../railway.toml) + env-var reference at
  [docs/deploy/railway-env.md](deploy/railway-env.md).
- Rollback runbook: [docs/deploy/rollback.md](deploy/rollback.md).

### Known limitations

- No streaming tool use (function calling) yet.
- No vision inputs.
- No `/v1/embeddings` endpoint — call the provider directly.
- No semantic cache (exact-match only).
- No gateway-level rate limits in MVP — upstream 429s still surface via
  `rate_limit_error`.

[GitHub release — placeholder](https://github.com/Yogeshshirsath01/agniai/releases)

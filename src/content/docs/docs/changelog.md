---
title: Changelog
description: All user-visible changes to InferBridge, by release.
---

All user-visible changes to InferBridge (formerly Agni AI) land here.
Dates are UTC.

## v0.3.5 — 2026-05-03

Hotfix for external uptime probes. No API behaviour change for normal
clients.

- `/health` and `/live` now accept `HEAD` in addition to `GET`. Most
  uptime services (UptimeRobot, StatusCake, Pingdom) default to HEAD
  because it's a lighter probe; the previous `@app.get`-only routes
  returned 405 with `Allow: GET`, which UptimeRobot read as "down."
- Starlette serves HEAD by running the GET handler and stripping the
  body, so the DB + Redis checks still execute and the status code
  remains accurate. GET callers see no change.

## v0.3.4 — 2026-05-03

Documentation-only release. No API changes, no behaviour changes.

- **Caching docs.** Added a dedicated "Caching" subsection under
  `POST /v1/chat/completions` in `docs/api.md`, with a separate
  "Streaming cache (Day 26, v0.3.3)" sub-block covering the
  read/write semantics, the asynchronous post-`[DONE]` cache write,
  and the known consequence that the replayed `inferbridge` meta
  chunk reflects the original request's latency / cost / request_id.
- **Audit retention note.** Added a callout in the `/v1/audit/export`
  section noting that free-tier accounts retain `request_logs` rows
  for 30 days. Export before the window closes — rows that have aged
  out cannot appear in any signed report.
- **Migration FAQ.** Added a "What are the rate limits?" entry to
  `docs/migration-from-openai.md` covering the free-tier 60 rpm /
  100k tpm limits, the `Retry-After` header, and the `limit_type`
  branch.

## v0.3.3 — 2026-05-03

Adds **streaming cache** support to `POST /v1/chat/completions`. The
existing exact-match cache (Day 6) only covered non-streaming
responses; identical streaming requests now also opt in via
`X-InferBridge-Cache: true` and replay from Redis on the second call.
No breaking changes; no deprecations.

### Behaviour

- Streaming requests with `X-InferBridge-Cache: true` accumulate each
  raw SSE chunk during the live response (yield-first, append-second
  so caching never delays first-byte) and write the chunk list to
  Redis after the `[DONE]` sentinel ships. The write is fire-and-forget
  via `asyncio.create_task` — the live request never waits.
- Subsequent identical streaming requests replay the cached chunks
  immediately as SSE, then emit `data: [DONE]\n\n`. Provider is not
  called; no fallback chain is opened; no upstream cost is charged.
- Streaming and non-streaming caches are keyed separately. The cache
  key now hashes `(provider, model, messages, params, stream)` —
  same digest function, one extra input. A streaming request can
  never deserialize a non-streaming entry as a chunk list and vice
  versa, even when every other input matches.

### Logging

Streaming cache hits log a row with:

| Field | Value |
|---|---|
| `status` | `cache_hit` |
| `provider` | `cache` |
| `model` | `<orig_provider>:<orig_model>` (parsed from cached meta) |
| `input_tokens` / `output_tokens` | `0` |
| `cost_usd` | `0.000000` |
| `cache_hit` | `true` |

Distinct from the non-streaming cache hit shape (which logs `None`
tokens) — the Day 26 spec asks for explicit zero counts on streaming.

### Implementation

- New module-level functions in `app.core.cache`:
  - `write_stream_cache(redis_client, key, chunks, ttl_seconds)` —
    JSON-array-of-strings storage, fail-soft on Redis errors.
  - `read_stream_cache(redis_client, key)` — returns `list[str] | None`,
    fail-soft on Redis errors and on entries that aren't a flat list
    of strings.
- `cache.cache_key(...)` now requires a `stream: bool` keyword arg.
  Internal callers pass `False` for non-streaming and `True` for
  streaming. External library users are extremely rare for this
  helper, but any in-tree forks need to update their call sites.
- `app/api/chat.py` `_sse_body` accumulates chunk JSON in memory
  (yield-then-append order) and schedules the write after `[DONE]`.
  Failures from the fire-and-forget write surface via a `done_callback`
  to the gateway log — they never escalate to the client.

### Known consequence

The cached chunk list includes the gateway's own meta chunk (the
final pre-`[DONE]` chunk carrying the `inferbridge` block). On
replay, that meta chunk's `latency_ms`, `cost_usd`, `request_id`
reflect the **original** request, not the cache-hit replay. The
log row is correct (`status=cache_hit`, `cost=0`); the wire-level
meta is not. Clients that need fresh meta should ignore the
`inferbridge` block on responses they recognize as cached (e.g.
unrealistically low latency for the mode).

---

## v0.3.2 — 2026-05-02

Internal cleanup release — no API changes, no behaviour changes.

- Migrated every `HTTP_422_UNPROCESSABLE_ENTITY` reference to the new
  `HTTP_422_UNPROCESSABLE_CONTENT` name across the API modules.
  Starlette deprecated the old constant; the value (`422`) is
  unchanged so wire behaviour is identical.
- `alembic.ini`: added `path_separator = os` so Alembic stops
  emitting a deprecation warning on every test boot.
- `pyproject.toml`: scoped `filterwarnings` entry under
  `[tool.pytest.ini_options]` to silence FastAPI's own internal use
  of the deprecated 422 constant. The filter targets `fastapi.*`
  only — DeprecationWarnings from our own code still surface.
- Net result: pytest run goes from 92 warnings to **0**.

## v0.3.1 — 2026-04-25

Adds **per-user rate limiting** on the chat completions endpoint. No
breaking changes; no deprecations.

### Per-user RPM and TPM limits

- Free-tier defaults: **60 requests / minute** and **100,000 tokens /
  minute**, both measured over a sliding 60-second window keyed by
  `user_id`. The same limits apply to every account today; tier-aware
  limits will land alongside paid plans.
- When either budget trips, `POST /v1/chat/completions` returns
  **429 Too Many Requests** with the standard error envelope plus a
  new `limit_type` field (`"rpm"` or `"tpm"`) so callers can branch
  on which budget tripped:

  ```json
  {
    "error": {
      "message": "rate limit exceeded — try again in 28 seconds",
      "type": "rate_limit_error",
      "limit_type": "rpm"
    }
  }
  ```

- New response headers on the 429: `Retry-After: <seconds>`,
  `X-RateLimit-Limit-RPM: 60`, `X-RateLimit-Limit-TPM: 100000`.
  `Retry-After` is always rounded up so a client retrying at exactly
  that delay can't bounce back into another 429.

### Distinct from upstream 429

The existing all-providers-rate-limited 429 (when every fallback
candidate returns 429 from the upstream) keeps its current shape and
does NOT include `limit_type`. The new per-user 429 fires earlier in
the request — before any provider call — so a rate-limited caller
never burns provider quota.

### Implementation

- New module `app.core.rate_limiter` — sliding-window limiter backed
  by Redis sorted sets. No Lua scripts, no third-party rate-limit
  library; stays consistent with the rest of the codebase.
- New module `app.core.token_estimator` — pre-flight `len(content)
  // 4` heuristic for the TPM check. Coarse on purpose; the real
  per-tokenizer count is unavailable before dispatch.
- **Redis-down policy: degrade open.** If Redis is unreachable, the
  limiter logs a warning and admits the request — same posture as
  `app.core.cache`. Rate-limit precision is not worth a global outage
  during a Redis hiccup.

### Configuration

Three new optional `Settings` fields (all environment-overridable):

| Env var | Default | Notes |
|---|---:|---|
| `RATE_LIMIT_ENABLED` | `true` | Global kill-switch. Set to `false` in dev/staging when iterating. |
| `RATE_LIMIT_RPM` | `60` | Requests / minute per user. |
| `RATE_LIMIT_TPM` | `100000` | Estimated input tokens / minute per user. |

Documented in [api.md § Rate limits](api.md#rate-limits).

---

## v0.3.0 — 2026-04-25

Adds the **DPDP audit export** endpoint — a signed compliance report of
request metadata over a bounded window. No breaking changes; no
deprecations.

### New endpoint — `GET /v1/audit/export`

- Returns a self-contained, SHA-256-signed report of `request_logs`
  metadata for the authenticated user across a given window. Designed
  for India's DPDP Act / GDPR data-inventory obligations: the artefact
  is portable, reproducible, and verifiable after it leaves the
  gateway.
- Required query params: `start_date`, `end_date` (ISO 8601 with tz).
- Optional: `format` = `json` (default) or `pdf`; `residency` =
  `india` / `global` / `eu` (filters on `residency_actual`).
- Window cap is **90 days**, identical to `/v1/stats`. Longer histories
  are supported by chaining successive calls.
- The signature value is also exposed via the
  `X-InferBridge-Audit-Signature` response header so PDF consumers can
  cross-check against a JSON copy without re-parsing the binary.

### Signature canonicalisation

The signature is the SHA-256 hex digest of:

1. The report dict with the `signature` key removed.
2. Serialized via `json.dumps(..., sort_keys=True, separators=(",", ":"))`
   — no whitespace, keys sorted, UTF-8 bytes.

A 4-line Python verifier ships in [api.md → Audit
export](api.md#audit-export). The canonicalisation is intentionally
boring (stdlib `json` + `hashlib`) so auditors can replicate it without
installing the InferBridge SDK.

### What's NOT exported

By design, the audit body contains only metadata: provider, model,
tokens, latency, cost, residency, status, error class. Prompts,
completions, tool calls, and message bodies are **never** included
because they are never stored (see CLAUDE.md § Security Rules). If
your compliance review needs conversation content, source it from
your own application logs.

### Dependencies

- New runtime dep: **`reportlab>=4.0`** (PDF rendering, pure Python,
  no system binaries). Adds ~7 MB to the container image. Wheels for
  Linux x86_64 + arm64 + macOS are published on PyPI; no extra build
  steps are needed in CI or on Railway.

---

## v0.2.5 — 2026-04-25

Adds **Krutrim** as the tenth supported provider — the second
India-residency option after Sarvam. No breaking changes; no
deprecations.

### Provider — Krutrim

- New BYOK provider value: **`krutrim`**. Register a Krutrim API key
  at `cloud.olakrutrim.com`, then `POST /v1/keys` with
  `{"provider": "krutrim", "api_key": "..."}`. Residency is `india`
  (same bucket as Sarvam).
- Krutrim exposes an OpenAI-compatible Chat Completions endpoint at
  `https://cloud.olakrutrim.com/v1`; the adapter is a direct
  pass-through with no request or response translation.
- Suggested models: `Krutrim-spectre-v2` (Krutrim's own model) and
  `DeepSeek-R1` (Krutrim-hosted, priced separately from
  `provider="deepseek"`'s `deepseek-reasoner`). Use either directly
  via `X-InferBridge-Override-Model: krutrim:<model>`.
- Pricing surfaced through `inferbridge.cost_usd` uses the published
  per-million-token rates: `Krutrim-spectre-v2` `$0.40 / $1.20` and
  `DeepSeek-R1` `$0.50 / $1.50` for input/output respectively.

### Routing changes — second-line India fallback

The static routing table slots Krutrim **after** Sarvam in both
`ib/cheap` and `ib/balanced`. With both keys registered, Sarvam still
serves first; if Sarvam is unavailable (5xx/timeout/429), the router
falls back to Krutrim before drifting back to global providers. The
premium tier remains reserved for Anthropic / OpenAI / Mistral.

| Mode | Order |
|---|---|
| `ib/cheap` | `groq` → `deepseek` → `together` → `sarvam` → `krutrim` → `openai` |
| `ib/balanced` | `openai` → `groq` → `cohere` → `sarvam` → `krutrim` → `anthropic` |
| `ib/premium` | `anthropic` → `openai` → `mistral` *(unchanged)* |

### Multi-provider residency — `X-InferBridge-Residency: india`

`X-InferBridge-Residency: india` now resolves to **both** Sarvam and
Krutrim (in tier order) as candidates. The residency filter has
always been a string-equality match over the candidate list, so two
providers sharing the `india` bucket coexist without code changes —
the filter just keeps every key whose residency equals the requested
value. If you don't have a Krutrim key registered, the router skips
the Krutrim slot exactly as before.

### Streaming + fallback

Krutrim returns standard OpenAI-shaped SSE deltas; existing streaming
clients work unchanged. Fallback budget (max 2 candidates per request,
streaming fallback before first token only) is unchanged.

---

## v0.2.4 — 2026-04-25

Adds **Cohere** as the ninth supported provider. No breaking changes;
no deprecations.

### Provider — Cohere

- New BYOK provider value: **`cohere`**. Register a Cohere API key at
  `dashboard.cohere.com`, then `POST /v1/keys` with
  `{"provider": "cohere", "api_key": "..."}`. Residency is `global`.
- The adapter targets Cohere's **v2** chat endpoint at
  `https://api.cohere.com/v2/chat`. The path is `/chat`, *not*
  `/chat/completions` — that's the only Cohere-specific deviation from
  the rest of the OpenAI-shaped adapter family.
- Suggested models: `command-r-plus` (flagship), `command-r`
  (balanced), `command-light` (cheapest). Use any directly via
  `X-InferBridge-Override-Model: cohere:<model>`.
- Pricing surfaced through `inferbridge.cost_usd` uses the published
  per-million-token rates: `command-r-plus` `$2.50 / $10.00`,
  `command-r` `$0.15 / $0.60`, `command-light` `$0.075 / $0.30` for
  input/output respectively.

### Routing changes

The static routing table slots Cohere into the **balanced** tier
between Groq and Sarvam. Cheap and premium are unchanged — Cohere is
not price-competitive with Groq/Together/Sarvam at the cheap tier and
the premium tier remains reserved for Anthropic / OpenAI / Mistral
flagships.

| Mode | Order |
|---|---|
| `ib/cheap` | `groq` → `deepseek` → `together` → `sarvam` → `openai` *(unchanged)* |
| `ib/balanced` | `openai` → `groq` → `cohere` → `sarvam` → `anthropic` |
| `ib/premium` | `anthropic` → `openai` → `mistral` *(unchanged)* |

If you don't have a Cohere key registered, the router skips the Cohere
slot and proceeds down the same list — no change in behaviour for
existing integrations until you register a Cohere key.

### Streaming + fallback

Cohere v2 returns standard OpenAI-shaped SSE deltas; existing
streaming clients work unchanged. Fallback budget (max 2 candidates
per request, streaming fallback before first token only) is unchanged.

---

## v0.2.3 — 2026-04-25

Adds **DeepSeek** as an eighth supported provider, including the R1
reasoning model. No breaking changes; no deprecations.

### Provider — DeepSeek

- New BYOK provider value: **`deepseek`**. Register a DeepSeek API
  key at `platform.deepseek.com`, then `POST /v1/keys` with
  `{"provider": "deepseek", "api_key": "..."}`. Residency is `global`.
- DeepSeek exposes an OpenAI-compatible Chat Completions endpoint at
  `https://api.deepseek.com/v1`; the adapter is a direct pass-through
  with no request or response translation.
- Suggested models: `deepseek-chat` (general purpose) and
  `deepseek-reasoner` (R1 reasoning). Use either directly via
  `X-InferBridge-Override-Model: deepseek:<model>`.
- Pricing surfaced through `inferbridge.cost_usd` uses the published
  per-million-token rates: `deepseek-chat` `$0.27 / $1.10` and
  `deepseek-reasoner` `$0.55 / $2.19` for input/output respectively.

### Reasoning model passthrough — `reasoning_content`

`deepseek-reasoner` (R1) returns an extra `reasoning_content` field on
each `message` (and on streaming `delta` chunks) carrying the model's
chain-of-thought alongside the usual `content`. The InferBridge gateway
**preserves the field verbatim** — it is not stripped, renamed, or
translated. Clients that opt into `deepseek-reasoner` receive the
reasoning output exactly as DeepSeek emits it.

### Routing changes

The static routing table slots DeepSeek into the **cheap** tier at the
second position (after Groq, before Together). Balanced and premium
are unchanged.

| Mode | Order |
|---|---|
| `ib/cheap` | `groq` → `deepseek` → `together` → `sarvam` → `openai` |
| `ib/balanced` | `openai` → `groq` → `sarvam` → `anthropic` *(unchanged)* |
| `ib/premium` | `anthropic` → `openai` → `mistral` *(unchanged)* |

If you don't have a DeepSeek key registered, the router skips the
DeepSeek slot and proceeds down the same list — no change in behaviour
for existing integrations until you register a DeepSeek key.

### Streaming + fallback

DeepSeek returns standard OpenAI-shaped SSE deltas (with the optional
`reasoning_content` field on R1 streams); existing streaming clients
work unchanged. Fallback budget (max 2 candidates per request,
streaming fallback before first token only) is unchanged.

---

## v0.2.2 — 2026-04-25

Adds **Mistral** as a seventh supported provider, and introduces a new
`eu` residency bucket. No breaking changes; no deprecations.

### Provider — Mistral

- New BYOK provider value: **`mistral`**. Register a Mistral API key at
  `console.mistral.ai`, then `POST /v1/keys` with
  `{"provider": "mistral", "api_key": "..."}`. Residency is `eu` —
  the first non-`global`/non-`india` bucket the gateway exposes.
- Mistral exposes an OpenAI-compatible Chat Completions endpoint at
  `https://api.mistral.ai/v1`; the adapter is a direct pass-through
  with no request or response translation.
- Suggested models: `mistral-large-latest`, `mistral-small-latest`,
  `open-mistral-nemo`. Use a model directly via
  `X-InferBridge-Override-Model: mistral:<model>`.
- Pricing surfaced through `inferbridge.cost_usd` uses the published
  per-million-token rates (small `$1.00 / $3.00`, large `$2.00 / $6.00`,
  nemo `$0.30 / $0.30` for input/output respectively).

### Routing changes

The static routing table slots Mistral into the **premium** tier only,
behind the existing Anthropic + OpenAI flagships. The cheap and
balanced tiers are unchanged.

| Mode | Order |
|---|---|
| `ib/cheap` | `groq` → `together` → `sarvam` → `openai` *(unchanged)* |
| `ib/balanced` | `openai` → `groq` → `sarvam` → `anthropic` *(unchanged)* |
| `ib/premium` | `anthropic` → `openai` → `mistral` |

If you don't have a Mistral key registered, the router skips the
Mistral slot and proceeds down the same list — no change in behaviour
for existing integrations until you register a Mistral key.

### Residency — new `eu` bucket

`X-InferBridge-Residency: eu` is now accepted at the chat endpoint
and filters routing to providers in the EU residency bucket. Today
that's only Mistral. The header continues to support `india` for
Sarvam/self-hosted-india keys; nothing about the global default
changes. The `residency_actual` field on the response metadata block
and on `request_logs` rows can now also be `eu`.

### Streaming + fallback

Mistral returns standard OpenAI-shaped SSE deltas; existing streaming
clients work unchanged. Fallback budget (max 2 candidates per request,
streaming fallback before first token only) is unchanged.

---

## v0.2.1 — 2026-04-25

Adds **Groq** as a sixth supported provider. No breaking changes; no
deprecations.

### Provider — Groq

- New BYOK provider value: **`groq`**. Register a Groq API key at
  `console.groq.com`, then `POST /v1/keys` with
  `{"provider": "groq", "api_key": "gsk_..."}`. Residency is `global`.
- Groq exposes an OpenAI-compatible Chat Completions endpoint at
  `https://api.groq.com/openai/v1`; the adapter is a direct
  pass-through with no request or response translation.
- Suggested models: `llama-3.3-70b-versatile`, `mixtral-8x7b-32768`,
  `gemma2-9b-it`. Use the model directly via
  `X-InferBridge-Override-Model: groq:<model>`.
- **Free tier is rate-limited** (per-minute and per-day token caps; see
  `console.groq.com` for current limits). Costs surfaced through
  `inferbridge.cost_usd` are reported as `"0.000000"` while the free
  tier is in use; the pricing table will switch to per-million rates
  once the paid tier ships and operators register paid keys.

### Routing changes

The static routing table now slots Groq into the cheap and balanced
tiers, in front of the slower commercial alternatives. Premium is
unchanged — it remains reserved for Anthropic + OpenAI flagships.

| Mode | Order |
|---|---|
| `ib/cheap` | `groq` → `together` → `sarvam` → `openai` |
| `ib/balanced` | `openai` → `groq` → `sarvam` → `anthropic` |
| `ib/premium` | `anthropic` → `openai` *(unchanged)* |

If you don't have a Groq key registered, the router skips the Groq slot
and proceeds down the same list — no change in behaviour for existing
integrations until you register a Groq key.

### Streaming + fallback

Groq returns standard OpenAI-shaped SSE deltas; existing streaming
clients work unchanged. Fallback budget (max 2 candidates per request,
streaming fallback before first token only) is unchanged.

---

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

### Known limitations

- No streaming tool use (function calling) yet.
- No vision inputs.
- No `/v1/embeddings` endpoint — call the provider directly.
- No semantic cache (exact-match only).
- No gateway-level rate limits in MVP — upstream 429s still surface via
  `rate_limit_error`.

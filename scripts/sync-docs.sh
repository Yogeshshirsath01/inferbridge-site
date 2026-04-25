#!/usr/bin/env bash
# Sync source docs from the backend InferBridge repo into this site's
# Starlight content collection.
#
# The canonical source of truth for user-facing docs is the backend repo
# (~/Desktop/agni/docs). This script pulls them into
# src/content/docs/docs/ so Starlight can render them at /docs/*.
#
# Run this after editing any of the following in the backend repo:
#   - docs/api.md
#   - docs/migration-from-openai.md
#   - docs/changelog.md
#   - README.md (quickstart block)
#
# Usage:
#   ./scripts/sync-docs.sh                   # assumes backend at ~/Desktop/agni
#   ./scripts/sync-docs.sh path/to/backend   # or pass the path explicitly
#
# Design notes:
#   - migration-from-openai.md and changelog.md map 1:1 onto single
#     Starlight pages; we prepend frontmatter and copy verbatim.
#   - api.md is split into 6 Starlight pages by H2 section boundaries.
#     The keys-page combines the 4 user+key CRUD endpoints into one page.
#   - The README quickstart block is extracted into /docs/getting-started.
#
# If you rename or add H2 headers in api.md, update the section markers
# below.

set -euo pipefail

BACKEND="${1:-$HOME/Desktop/agni}"
SITE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS_OUT="$SITE_ROOT/src/content/docs/docs"

if [[ ! -d "$BACKEND/docs" ]]; then
  echo "error: backend repo docs/ not found at $BACKEND/docs" >&2
  echo "usage: $0 [path-to-backend-repo]" >&2
  exit 1
fi

mkdir -p "$DOCS_OUT/api"

write_with_frontmatter() {
  # $1 outfile, $2 title, $3 description, stdin = body.
  # Body is normalized: leading blank lines stripped (avoids a yawning
  # gap between frontmatter and first paragraph) and a single trailing
  # newline guaranteed.
  local out="$1" title="$2" desc="$3"
  {
    printf -- '---\n'
    printf -- 'title: %s\n' "$title"
    printf -- 'description: %s\n' "$desc"
    printf -- '---\n\n'
    awk '
      seen==0 && NF==0 { next }
      { seen=1; lines[++n] = $0 }
      END {
        # Trim trailing blank lines so we end on exactly one newline.
        while (n > 0 && lines[n] == "") n--
        for (i = 1; i <= n; i++) print lines[i]
      }
    '
  } > "$out"
}

# Extract the body of api.md between two H2 section markers (exclusive of
# the closing marker). The `end` argument may be literal "EOF" to consume
# the rest of the file.
extract_api_section() {
  local start="$1" end="$2"
  local api="$BACKEND/docs/api.md"
  if [[ "$end" == "EOF" ]]; then
    awk -v start="## $start" '
      $0 == start { capture=1 }
      capture { print }
    ' "$api"
  else
    awk -v start="## $start" -v end="## $end" '
      $0 == start { capture=1 }
      $0 == end && capture { exit }
      capture { print }
    ' "$api"
  fi
}

# Strip the first H2 line, any immediately-following blank lines, and any
# trailing horizontal-rule separator (`---`) plus surrounding blank lines.
# api.md uses `---` between H2 sections; without this trim, every split
# section ends with a stray HR that renders as a thin gray bar at the
# bottom of the Starlight page.
strip_leading_h2() {
  awk '
    NR==1 && /^## / { next }
    seen==0 && NF==0 { next }
    { seen=1; lines[++n] = $0 }
    END {
      # Trim trailing blanks, then a trailing HR, then trailing blanks again.
      while (n > 0 && lines[n] == "") n--
      if (n > 0 && lines[n] == "---") n--
      while (n > 0 && lines[n] == "") n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  '
}

# ---------- migration ----------
cat "$BACKEND/docs/migration-from-openai.md" \
  | tail -n +2 \
  | write_with_frontmatter \
    "$DOCS_OUT/migration.md" \
    "Migrating from OpenAI" \
    "Two-line migration from the OpenAI SDK to InferBridge — Python, Node, and cURL."

# ---------- changelog ----------
cat "$BACKEND/docs/changelog.md" \
  | tail -n +2 \
  | write_with_frontmatter \
    "$DOCS_OUT/changelog.md" \
    "Changelog" \
    "All user-visible changes to InferBridge, by release."

# ---------- api: authentication ----------
extract_api_section "Authentication" "Register a user" | strip_leading_h2 \
  | write_with_frontmatter \
    "$DOCS_OUT/api/authentication.md" \
    "Authentication" \
    "Bearer token auth, key prefixes, and 401 responses."

# ---------- api: users + provider keys (combined page) ----------
{
  printf -- '## Register a user\n\n'
  extract_api_section "Register a user" "Register a provider key" | strip_leading_h2
  printf -- '\n## Register a provider key\n\n'
  extract_api_section "Register a provider key" "List provider keys" | strip_leading_h2
  printf -- '\n## List provider keys\n\n'
  extract_api_section "List provider keys" "Delete a provider key" | strip_leading_h2
  printf -- '\n## Delete a provider key\n\n'
  extract_api_section "Delete a provider key" "Chat completions" | strip_leading_h2
} | write_with_frontmatter \
  "$DOCS_OUT/api/keys.md" \
  "Users & provider keys" \
  "Register a user, register BYOK provider keys, list, and delete."

# ---------- api: chat completions ----------
extract_api_section "Chat completions" "Stats" | strip_leading_h2 \
  | write_with_frontmatter \
    "$DOCS_OUT/api/chat-completions.md" \
    "Chat completions" \
    "OpenAI-compatible POST /v1/chat/completions — headers, streaming, errors."

# ---------- api: stats ----------
extract_api_section "Stats" "Logs" | strip_leading_h2 \
  | write_with_frontmatter \
    "$DOCS_OUT/api/stats.md" \
    "Stats" \
    "Per-user aggregates — totals, by mode, by provider, by residency."

# ---------- api: logs ----------
extract_api_section "Logs" "Error envelope" | strip_leading_h2 \
  | write_with_frontmatter \
    "$DOCS_OUT/api/logs.md" \
    "Logs" \
    "Reverse-chronological request logs with opaque cursor pagination."

# ---------- api: errors + rate limits (combined) ----------
{
  printf -- '## Error envelope\n\n'
  extract_api_section "Error envelope" "Rate limits" | strip_leading_h2
  printf -- '\n## Rate limits\n\n'
  extract_api_section "Rate limits" "EOF" | strip_leading_h2
} | write_with_frontmatter \
  "$DOCS_OUT/api/errors.md" \
  "Errors & rate limits" \
  "Error envelope shape, error type enumeration, and rate-limit behaviour."

echo "synced from $BACKEND into $DOCS_OUT"

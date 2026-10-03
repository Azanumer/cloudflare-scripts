#!/usr/bin/env bash
#
# purge-cache.sh — Purge Cloudflare cache for specific URLs (or everything).
#
# Needs:  Cloudflare API token with "Cache Purge" permission + the Zone ID.
# Usage:  CF_TOKEN=xxx CF_ZONE=yyy ./purge-cache.sh url1 [url2 ...]
#         ./purge-cache.sh --all        # purge the whole zone cache
#
set -euo pipefail

: "${CF_TOKEN:?Set CF_TOKEN to your Cloudflare API token}"
: "${CF_ZONE:?Set CF_ZONE to the zone ID}"

API="https://api.cloudflare.com/client/v4/zones/${CF_ZONE}/purge_cache"

if [[ "${1:-}" == "--all" ]]; then
  payload='{"purge_everything":true}'
  echo "Purging ALL cache for zone ${CF_ZONE} ..."
else
  # Build {"files":[...]} from the URL arguments.
  files=$(printf '"%s",' "$@" | sed 's/,$//')
  payload="{\"files\":[${files}]}"
  echo "Purging $# URL(s) ..."
fi

curl -sS -X POST "$API" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$payload" | grep -o '"success":[a-z]*'

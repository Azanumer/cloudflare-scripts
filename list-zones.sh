#!/usr/bin/env bash
#
# list-zones.sh — List Cloudflare zones (name + ID) for the token's account.
#
# Usage:  CF_TOKEN=xxx ./list-zones.sh
#
set -euo pipefail

: "${CF_TOKEN:?Set CF_TOKEN to your Cloudflare API token}"

curl -sS "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
| grep -o '"name":"[^"]*","id":"[^"]*"' \
| sed 's/"name":"//; s/","id":"/  ->  /; s/"$//'

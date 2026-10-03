#!/usr/bin/env bash
#
# dns-add-txt.sh — Add a TXT record to a Cloudflare zone (e.g. SPF, DKIM, verification).
#
# Usage:  CF_TOKEN=xxx CF_ZONE=yyy ./dns-add-txt.sh <name> "<content>" [ttl]
# Example: CF_TOKEN=xxx CF_ZONE=yyy ./dns-add-txt.sh @ "v=spf1 include:_spf.google.com ~all"
#
set -euo pipefail

: "${CF_TOKEN:?Set CF_TOKEN to your Cloudflare API token}"
: "${CF_ZONE:?Set CF_ZONE to the zone ID}"

name="${1:?Record name, e.g. @ or _dmarc}"
content="${2:?TXT content in quotes}"
ttl="${3:-3600}"

curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE}/dns_records" \
  -H "Authorization: Bearer ${CF_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$(printf '{"type":"TXT","name":"%s","content":"%s","ttl":%s}' \
             "$name" "$content" "$ttl")" | grep -o '"success":[a-z]*'

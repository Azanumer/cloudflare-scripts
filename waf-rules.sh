#!/usr/bin/env bash
#
# waf-rules.sh — Deploy Cloudflare WAF custom rules from a JSON file.
#
# Complements the Cloudflare dashboard: keep your firewall rules in version
# control and push them with one command.
#
# Needs:  Cloudflare API token with "Zone WAF Edit" permission + the Zone ID.
#         python3 (for JSON validation/transform).
# Usage:
#   CF_TOKEN=... CF_ZONE=... ./waf-rules.sh list
#   CF_TOKEN=... CF_ZONE=... ./waf-rules.sh apply --file rules.json [--dry-run] [--yes]
#   CF_TOKEN=... CF_ZONE=... ./waf-rules.sh clear [--yes]
#
# rules.json is a JSON array; each rule needs name, action and expression:
#   [
#     {"name": "challenge-known-bots", "action": "managed_challenge",
#      "expression": "(cf.client.bot)"},
#     {"name": "block-two-countries", "action": "block",
#      "expression": "(ip.geoip.country in {\"CN\" \"RU\"})",
#      "description": "No traffic expected from these regions"}
#   ]
# Valid actions: block, challenge, js_challenge, managed_challenge, log, skip.
# See rules.example.json for a starter set (bots + bad-country block + wp-login hardening).
#
set -euo pipefail

: "${CF_TOKEN:?Set CF_TOKEN to your Cloudflare API token}"
: "${CF_ZONE:?Set CF_ZONE to the zone ID}"

API="https://api.cloudflare.com/client/v4/zones/${CF_ZONE}"
ENTRYPOINT="${API}/rulesets/phases/http_request_firewall_custom/entrypoint"

auth() {
  curl -sS -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" "$@"
}

# Print the current ruleset id + rule summary; returns 1 when no ruleset exists.
show_current() {
  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  local code
  code=$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" "$ENTRYPOINT")

  if [[ "$code" == "404" ]]; then
    echo "No WAF custom ruleset on this zone yet."
    return 1
  fi
  if [[ "$code" != "200" ]]; then
    echo "API error (HTTP $code):" >&2
    cat "$tmp" >&2
    return 2
  fi

  local id
  id=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",{}).get("id",""))' < "$tmp")
  echo "Ruleset: $id"
  python3 - "$tmp" <<'EOF'
import json, sys
rules = json.load(open(sys.argv[1])).get("result", {}).get("rules", [])
if not rules:
    print("  (no rules)")
for r in rules:
    print(f'  [{"ON" if r.get("enabled", True) else "off"}] {r.get("action","?"):16} {r.get("description") or r.get("expression","")}')
EOF
  printf '%s' "$id"
  return 0
}

# Validate rules.json and print the normalized rules array to stdout.
normalize_rules() {
  local file="$1"
  python3 - "$file" <<'EOF'
import json, sys
try:
    rules = json.load(open(sys.argv[1]))
except Exception as e:
    sys.exit(f"Invalid JSON in rules file: {e}")
if not isinstance(rules, list):
    sys.exit("Rules file must be a JSON array of rule objects.")
valid_actions = {"block", "challenge", "js_challenge", "managed_challenge", "log", "skip"}
out = []
for i, r in enumerate(rules):
    if not isinstance(r, dict):
        sys.exit(f"Rule #{i} is not an object.")
    for key in ("name", "action", "expression"):
        if key not in r or not r[key]:
            sys.exit(f'Rule #{i} is missing required key "{key}".')
    if r["action"] not in valid_actions:
        sys.exit(f'Rule #{i} has invalid action "{r["action"]}" (valid: {sorted(valid_actions)}).')
    out.append({
        "action": r["action"],
        "expression": r["expression"],
        "description": r.get("description", r["name"]),
        "enabled": bool(r.get("enabled", True)),
    })
print(json.dumps(out))
EOF
}

confirm() {
  # $1 = prompt; skipped when --yes was given.
  if [[ "${YES:-0}" == "1" ]]; then return 0; fi
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

cmd_list() {
  show_current > /dev/null || true
}

cmd_apply() {
  local file="" dry=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --yes) YES=1; shift ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  [[ -n "$file" ]] || { echo "apply needs --file rules.json" >&2; exit 1; }
  [[ -f "$file" ]] || { echo "File not found: $file" >&2; exit 1; }

  local rules payload
  rules=$(normalize_rules "$file")
  payload=$(python3 -c 'import json,sys; print(json.dumps({"rules": json.loads(sys.argv[1])}))' "$rules")
  echo "Rules to deploy:"
  python3 -c '
import json, sys
for r in json.loads(sys.argv[1])["rules"]:
    print(f"  [{r['action']:16}] {r['description']}")' "$payload"

  if [[ "$dry" == "1" ]]; then
    echo "--- dry-run: payload that would be PUT ---"
    echo "$payload" | python3 -m json.tool
    return 0
  fi

  confirm "Replace ALL WAF custom rules on zone ${CF_ZONE} with the above?" || { echo "Aborted."; exit 1; }

  local id
  if id=$(show_current > /dev/null 2>&1); then
    # Ruleset exists: full replace via PUT.
    auth -X PUT "${API}/rulesets/${id}" --data "$payload" \
      | python3 -c 'import json,sys; print("success:", json.load(sys.stdin).get("success"))'
  else
    # No ruleset yet: create it with the rules inline.
    local create_payload
    create_payload=$(python3 -c '
import json, sys
rules = json.loads(sys.argv[1])["rules"]
print(json.dumps({
  "name": "waf-rules.sh custom ruleset",
  "description": "Managed by waf-rules.sh — edit rules.json and re-apply",
  "kind": "zone",
  "phase": "http_request_firewall_custom",
  "rules": rules,
}))' "$payload")
    auth -X POST "${API}/rulesets" --data "$create_payload" \
      | python3 -c 'import json,sys; print("success:", json.load(sys.stdin).get("success"))'
  fi
  echo "Done. Verify with: $0 list"
}

cmd_clear() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) YES=1; shift ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  local id
  id=$(show_current > /dev/null 2>&1) || { echo "Nothing to clear."; exit 0; }
  confirm "Delete ALL WAF custom rules on zone ${CF_ZONE}?" || { echo "Aborted."; exit 1; }
  auth -X PUT "${API}/rulesets/${id}" --data '{"rules":[]}' \
    | python3 -c 'import json,sys; print("success:", json.load(sys.stdin).get("success"))'
  echo "All custom rules removed."
}

case "${1:-}" in
  list)  cmd_list ;;
  apply) shift; cmd_apply "$@" ;;
  clear) shift; cmd_clear "$@" ;;
  *) echo "Usage: $0 {list|apply --file rules.json [--dry-run] [--yes]|clear [--yes]}" >&2; exit 1 ;;
esac

# Cloudflare Scripts

Small Bash helpers for the Cloudflare v4 API — no dashboard needed.

## Scripts

| Script | What it does |
|---|---|
| `purge-cache.sh` | Purge cache for specific URLs, or `--all` for the whole zone |
| `dns-add-txt.sh` | Add a TXT record (SPF, DKIM, domain verification) |
| `list-zones.sh` | List zone names + IDs for your token |

## Setup

Create an API token at **Cloudflare → My Profile → API Tokens** with the needed permissions
(Cache Purge for purging, Zone DNS Edit for DNS), then export it per command — never hard-code it:

```bash
CF_TOKEN=your_token CF_ZONE=your_zone_id ./purge-cache.sh https://example.com/page/
CF_TOKEN=your_token CF_ZONE=your_zone_id ./purge-cache.sh --all
CF_TOKEN=your_token CF_ZONE=your_zone_id ./dns-add-txt.sh @ "v=spf1 include:_spf.google.com ~all"
CF_TOKEN=your_token ./list-zones.sh
```

MIT licensed.

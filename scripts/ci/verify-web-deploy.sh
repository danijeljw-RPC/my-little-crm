#!/usr/bin/env bash
# Check a deployed browser demo over HTTP (#61).
#
#   scripts/ci/verify-web-deploy.sh https://my-little-crm.pages.dev [more URLs...]
#
# For each site: sqlite3.wasm and main.dart.wasm must come back as
# application/wasm with the WebAssembly magic bytes (not the HTML fallback),
# and the page must send the cross-origin isolation headers. A freshly
# published production alias can lag a few seconds, so each check retries.
#
# Used by scripts/web-demo.sh deploy and .github/workflows/web-demo-deploy.yml.
set -euo pipefail

(( $# )) || { echo "usage: verify-web-deploy.sh <site-url> [...]"; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check_wasm() { # site path
  local url=$1/$2 type magic
  type=$(curl -fsSL -o "$tmp/body" -w '%{content_type}' "$url") || { echo "  $2: request failed"; return 1; }
  magic=$(od -An -tx1 -N4 "$tmp/body" | tr -d ' \n')
  if [[ $type != application/wasm* || $magic != 0061736d ]]; then
    echo "  $2: Content-Type '$type', first bytes $magic (want application/wasm, 0061736d)"
    return 1
  fi
}

check_headers() { # site
  curl -fsSI "$1/" > "$tmp/headers" || { echo "  /: request failed"; return 1; }
  grep -qi '^cross-origin-opener-policy: *same-origin' "$tmp/headers" \
    && grep -qi '^cross-origin-embedder-policy: *require-corp' "$tmp/headers" \
    || { echo "  /: missing COOP/COEP headers"; return 1; }
}

check_site() {
  check_wasm "$1" sqlite3.wasm && check_wasm "$1" main.dart.wasm && check_headers "$1"
}

status=0
for site in "$@"; do
  site=${site%/}
  ok=0
  for attempt in 1 2 3 4 5 6; do
    if check_site "$site"; then ok=1; break; fi
    (( attempt < 6 )) && { echo "  retrying $site in 10s ($attempt/6)"; sleep 10; }
  done
  if (( ok )); then
    echo "✓ $site serves sqlite3.wasm and main.dart.wasm as WebAssembly, with COOP/COEP"
  else
    echo "::error::$site is not serving the demo correctly"
    status=1
  fi
done
exit $status

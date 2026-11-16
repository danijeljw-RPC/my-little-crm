#!/usr/bin/env zsh
# Build and/or serve the browser demo (#30): Flutter WebAssembly, DEMO_MODE,
# in-memory SQLite seeded with sample records. Nothing is persisted.
#
#   scripts/web-demo.sh setup          fetch web/sqlite3.wasm (needed once)
#   scripts/web-demo.sh build          setup + release Wasm build -> build/web
#   scripts/web-demo.sh serve [port]   serve build/web (default port 8080)
#   scripts/web-demo.sh [port]         build, then serve
#   scripts/web-demo.sh package        build + zip -> dist/mylittlecrm-demo-<version>.zip
#   scripts/web-demo.sh package --base-href /demo/   for hosting in a sub-folder
#   scripts/web-demo.sh deploy         build + check + publish to Cloudflare Pages + verify
#
# Upload the zip's contents to a static web server: docs/WEB-DEMO.md#publish.
#
# The server sends the same headers the hosting must: cross-origin isolation
# (COOP/COEP) for the multi-threaded Wasm renderer, and application/wasm.

set -euo pipefail
cd "${0:A:h}/.."

setup() {
  # sqlite3.wasm must match the Dart sqlite3 package resolved in pubspec.lock.
  # Only sqlite3.wasm is used: the demo runs SQLite in the page (no shared
  # worker), so the generated worker is dropped.
  local version
  version=$(awk '/^  sqlite3:$/ {found=1} found && /version:/ {gsub(/"/, "", $2); print $2; exit}' pubspec.lock)
  [[ -n $version ]] || { print -u2 "error: sqlite3 not found in pubspec.lock"; exit 1; }
  local stamp=.dart_tool/sqlite3-wasm-version
  if [[ ! -f web/sqlite3.wasm || $(cat $stamp 2>/dev/null) != "$version" ]]; then
    dart run sqflite_common_ffi_web:setup --force \
      --sqlite3-wasm-url "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$version/sqlite3.wasm"
    print -r -- $version > $stamp
  fi
  rm -f web/sqflite_sw.js
}

build() {
  setup
  flutter build web --release --wasm --dart-define=DEMO_MODE=true "$@"
  # Not part of the site: the unused worker, and Flutter's build bookkeeping.
  rm -f build/web/sqflite_sw.js build/web/.last_build_id
}

serve() {
  local port=${1:-8080}
  if [[ ! -f build/web/main.dart.wasm ]]; then
    print -u2 "error: no Wasm build in build/web; run: scripts/web-demo.sh build"
    exit 1
  fi
  print "▶ Demo at http://localhost:$port  (Ctrl-C to stop)"
  exec python3 - "$port" build/web <<'PY'
import functools, http.server, sys

port, root = int(sys.argv[1]), sys.argv[2]


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.wasm': 'application/wasm',
        '.mjs': 'text/javascript',
        '.js': 'text/javascript',
        '.json': 'application/json',
    }

    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


http.server.ThreadingHTTPServer(
    ('127.0.0.1', port), functools.partial(Handler, directory=root)
).serve_forever()
PY
}

package() {
  build "$@"
  local version
  version=$(awk '/^version:/ {print $2; exit}' pubspec.yaml)
  local zip=dist/mylittlecrm-demo-${version%%+*}.zip
  mkdir -p dist
  rm -f $zip
  # -X: no extra file attributes.
  (cd build/web && zip -qrX ../../$zip .)
  print "\n✓ $zip ($(du -h $zip | awk '{print $1}')), $(unzip -Z1 $zip | wc -l | tr -d ' ') files"
  print "  Upload its contents to your web root; see docs/WEB-DEMO.md#publish"
}

# Publish build/web to Cloudflare Pages (#61). Wrangler uses CLOUDFLARE_API_TOKEN
# and CLOUDFLARE_ACCOUNT_ID when set (CI), otherwise your `wrangler login`.
# CF_PAGES_PROJECT / CF_PAGES_BRANCH override the project and branch; the
# project's production branch is main, so the default updates the live site.
# CF_PAGES_SITE is the production URL checked after the upload.
deploy() {
  local project=${CF_PAGES_PROJECT:-my-little-crm} branch=${CF_PAGES_BRANCH:-main}
  local wrangler=(npx --yes wrangler@${WRANGLER_VERSION:-4.131.1})
  build "$@"
  scripts/ci/check-web-demo.sh build/web
  local log=$(mktemp)
  $wrangler pages deploy build/web --project-name=$project --branch=$branch \
    --commit-hash=$(git rev-parse HEAD) --commit-dirty=true | tee $log
  local url
  url=$(grep -oE "https://[a-z0-9-]+\.$project\.pages\.dev" $log | tail -1 || true)
  rm -f $log
  [[ -n $url ]] || { print -u2 "error: no deployment URL in the wrangler output"; exit 1; }
  local sites=($url)
  [[ $branch == main ]] && sites+=(${CF_PAGES_SITE:-https://$project.pages.dev})
  scripts/ci/verify-web-deploy.sh $sites
  [[ -n ${GITHUB_OUTPUT:-} ]] && print -r -- "url=$url" >> $GITHUB_OUTPUT
  print "\n✓ deployed $url"
}

case ${1:-} in
  setup) setup ;;
  build) shift; build "$@" ;;
  package) shift; package "$@" ;;
  deploy) shift; deploy "$@" ;;
  serve) shift; serve "${1:-8080}" ;;
  ''|<->) build; serve "${1:-8080}" ;;
  *) print -u2 "usage: scripts/web-demo.sh [setup | build | package [--base-href /path/] | deploy | serve [port] | port]"; exit 2 ;;
esac

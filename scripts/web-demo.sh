#!/usr/bin/env zsh
# Build and/or serve the browser demo (#30): Flutter WebAssembly, DEMO_MODE,
# in-memory SQLite seeded with sample records. Nothing is persisted.
#
#   scripts/web-demo.sh setup          fetch web/sqlite3.wasm (needed once)
#   scripts/web-demo.sh build          setup + release Wasm build -> build/web
#   scripts/web-demo.sh serve [port]   serve build/web (default port 8080)
#   scripts/web-demo.sh [port]         build, then serve
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
  rm -f build/web/sqflite_sw.js
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

case ${1:-} in
  setup) setup ;;
  build) shift; build "$@" ;;
  serve) shift; serve "${1:-8080}" ;;
  ''|<->) build; serve "${1:-8080}" ;;
  *) print -u2 "usage: scripts/web-demo.sh [setup | build | serve [port] | port]"; exit 2 ;;
esac

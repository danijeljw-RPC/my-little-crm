#!/usr/bin/env bash
# Check a built browser demo (#30, #61) before it is uploaded anywhere.
#
#   scripts/ci/check-web-demo.sh [build/web]
#
# Fails if a required file is missing, if sqlite3.wasm or main.dart.wasm is
# not real WebAssembly (a bare `flutter build web` leaves sqlite3.wasm out, and
# the host then serves index.html in its place: "expected magic word 00 61 73
# 6d, found 3c 21 44 4f"), or if stray files would be published.
#
# Used by scripts/web-demo.sh deploy, .github/workflows/flutter-validation.yml
# and .github/workflows/web-demo-deploy.yml.
set -euo pipefail

dir=${1:-build/web}
[[ -d $dir ]] || { echo "::error::no web build at $dir; run: scripts/web-demo.sh build"; exit 1; }
cd "$dir"

fail() { echo "::error::$*"; exit 1; }

for f in index.html main.dart.wasm main.dart.mjs main.dart.js sqlite3.wasm _headers .htaccess; do
  [[ -s $f ]] || fail "missing $f in $dir (build with scripts/web-demo.sh build, not flutter build web)"
done

for f in sqlite3.wasm main.dart.wasm; do
  magic=$(od -An -tx1 -N4 "$f" | tr -d ' \n')
  [[ $magic == 0061736d ]] || fail "$f is not WebAssembly (first bytes $magic, want 0061736d)"
done

grep -q 'Cross-Origin-Embedder-Policy' _headers || fail "_headers lacks the COOP/COEP headers"
[[ ! -e sqflite_sw.js ]] || fail "sqflite_sw.js should not be published (the demo runs SQLite in the page)"

# Only the web build's own file types belong on a public site.
unexpected=""
while IFS= read -r f; do
  case $f in
    *.html|*.js|*.mjs|*.wasm|*.json|*.png|*.otf|*.ttf|*.frag|*.bin|*.symbols) ;;
    ./_headers|./.htaccess|*/NOTICES) ;;
    *) unexpected+=" $f" ;;
  esac
done < <(find . -type f)
[[ -z $unexpected ]] || fail "unexpected files:$unexpected"

echo "✓ $dir: $(find . -type f | wc -l | tr -d ' ') files, $(du -sh . | cut -f1); sqlite3.wasm and main.dart.wasm are WebAssembly"

#!/usr/bin/env zsh
# Regenerates the Google Play listing assets in docs/play-store/.
#   tool/store_listing/generate.sh
set -euo pipefail
cd "${0:A:h}/../.."

export FLUTTER_ROOT="${FLUTTER_ROOT:-$(cd "$(dirname "$(readlink -f "$(command -v flutter)")")/.." && pwd)}"
rm -rf tool/store_listing/out
flutter test tool/store_listing/screenshots_test.dart --update-goldens

for dir in phone tablet-7in tablet-10in; do
  rm -rf "docs/play-store/screenshots/$dir"
  mkdir -p "docs/play-store/screenshots/$dir"
  cp tool/store_listing/out/$dir/*.png "docs/play-store/screenshots/$dir/"
done
rm -rf tool/store_listing/out

python3 -I tool/store_listing/graphics.py

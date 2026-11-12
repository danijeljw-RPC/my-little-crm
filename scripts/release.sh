#!/usr/bin/env zsh
# Build a release-signed Android APK and, optionally, publish it as a GitHub release.
#
#   scripts/release.sh                  build + verify into dist/ (nothing is published)
#   scripts/release.sh --publish        ...then create GitHub release v<version>
#   scripts/release.sh --publish --draft  ...as a draft you publish from GitHub
#
# This is the ONLY build that uses the release key: it sets MLC_RELEASE_SIGNING=1, which
# android/app/build.gradle.kts checks. Everything else (flutter run, scripts/run.sh, plain
# `flutter build apk`) stays on the debug key. Needs android/key.properties, see
# docs/ANDROID-RELEASE.md.

set -euo pipefail
cd "${0:A:h}/.."

publish=false
draft=false
for arg in "$@"; do
  case $arg in
    --publish) publish=true ;;
    --draft) draft=true ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print -u2 "error: unknown option $arg (try --help)"; exit 2 ;;
  esac
done
$draft && ! $publish && { print -u2 "error: --draft only makes sense with --publish"; exit 2; }

die() { print -u2 "error: $*"; exit 1; }
step() { print "\n== $* =="; }

command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH"
[[ -f android/key.properties ]] || die "android/key.properties not found (see docs/ANDROID-RELEASE.md)"

# version: 1.0.0+15  ->  name 1.0.0, build number 15
version_line=$(grep -m1 '^version:' pubspec.yaml) || die "no version: line in pubspec.yaml"
full_version=${${version_line#version:}// /}
version=${full_version%%+*}
build_number=${full_version#*+}
[[ $build_number == $full_version ]] && die "pubspec.yaml version needs a build number, e.g. $version+1"
tag="v$version"
print "Releasing My Little CRM $version (build $build_number)"

find_apksigner() {
  local sdk dir
  command -v apksigner 2>/dev/null && return 0
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [[ -n $sdk && -d $sdk/build-tools ]] || continue
    # newest build-tools first
    for dir in ${(On)$(print -l $sdk/build-tools/*(N/))}; do
      [[ -x $dir/apksigner ]] && { print -r -- "$dir/apksigner"; return 0; }
    done
  done
  return 1
}
apksigner=$(find_apksigner) || die "apksigner not found; install Android SDK build-tools"

# Publishing pre-flight: fail before the slow build, not after it.
if $publish; then
  command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is not installed"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (run: gh auth login)"
  grep -q "^## \[$version\]" CHANGELOG.md || die "CHANGELOG.md has no '## [$version]' section"
  gh release view "$tag" >/dev/null 2>&1 && die "release $tag already exists; bump the version in pubspec.yaml"
  [[ -z $(git status --porcelain --untracked-files=no) ]] || die "uncommitted changes; commit them first"
  git fetch -q origin
  [[ -n $(git branch -r --contains HEAD 2>/dev/null) ]] || die "HEAD is not pushed; push it first"
fi

step "Building release-signed APK"
MLC_RELEASE_SIGNING=1 flutter build apk --release
apk=build/app/outputs/flutter-apk/app-release.apk
[[ -f $apk ]] || die "build finished but $apk is missing"

step "Verifying signature"
certs=$("$apksigner" verify --print-certs "$apk") || die "apksigner verify failed"
signer=$(print -r -- "$certs" | sed -n 's/^Signer #1 certificate DN: //p')
print "Signer: $signer"
[[ $signer == *"CN=Android Debug"* ]] && die "APK is signed with the DEBUG key; do not distribute it"
[[ -n $signer ]] || die "could not read the APK signer"

step "Packaging into dist/"
mkdir -p dist
name="my-little-crm-$version"
cp "$apk" "dist/$name.apk"
( cd dist && shasum -a 256 "$name.apk" > "$name.apk.sha256" )
if grep -q "^## \[$version\]" CHANGELOG.md; then
  awk -v v="$version" '$0 ~ "^## \\[" v "\\]" {f=1; next} /^## \[|^\[[0-9.]+\]:/ {f=0} f' \
    CHANGELOG.md > "dist/$name-notes.md"
else
  print "(no CHANGELOG.md section for $version; skipping release notes)"
fi
print "dist/$name.apk"
print "dist/$name.apk.sha256  $(cut -d' ' -f1 "dist/$name.apk.sha256")"

if ! $publish; then
  print "\nBuilt but not published. To publish: scripts/release.sh --publish"
  exit 0
fi

step "Creating GitHub release $tag"
gh_args=(release create "$tag" "dist/$name.apk" "dist/$name.apk.sha256"
  --title "My Little CRM $version" --notes-file "dist/$name-notes.md"
  --target "$(git rev-parse HEAD)")
$draft && gh_args+=(--draft)
gh "${gh_args[@]}"

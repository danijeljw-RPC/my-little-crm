#!/usr/bin/env zsh
# Build a release-signed Android APK and, optionally, publish it as a GitHub release.
#
#   scripts/release.sh                  build + verify into dist/ (nothing is published)
#   scripts/release.sh --aab            ...also build the Google Play app bundle (.aab)
#   scripts/release.sh --publish        ...then create GitHub release v<version>
#   scripts/release.sh --publish --draft  ...as a draft you publish from GitHub
#
#   scripts/release.sh --trigger        publish the FULL release from CI instead: switch to
#                                       main, pull, and push an empty "release" commit, which
#                                       starts .github/workflows/release.yml (Android, macOS
#                                       and Windows). No local build. Asks before pushing.
#   scripts/release.sh --trigger --yes  ...without asking
#
# The .aab is for uploading to Google Play Console by hand; it is never attached to the
# GitHub release (phones can't install an .aab).
#
# This is the ONLY build that uses the release key: it sets MLC_RELEASE_SIGNING=1, which
# android/app/build.gradle.kts checks. Everything else (flutter run, scripts/run.sh, plain
# `flutter build apk`) stays on the debug key. Needs android/key.properties, see
# docs/ANDROID-RELEASE.md.

set -euo pipefail
cd "${0:A:h}/.."

publish=false
draft=false
aab=false
trigger=false
yes=false
for arg in "$@"; do
  case $arg in
    --publish) publish=true ;;
    --draft) draft=true ;;
    --aab) aab=true ;;
    --trigger) trigger=true ;;
    --yes|-y) yes=true ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print -u2 "error: unknown option $arg (try --help)"; exit 2 ;;
  esac
done
$draft && ! $publish && { print -u2 "error: --draft only makes sense with --publish"; exit 2; }
$trigger && { $publish || $draft || $aab; } &&
  { print -u2 "error: --trigger releases from CI; it can't be combined with --publish, --draft or --aab"; exit 2; }
$yes && ! $trigger && { print -u2 "error: --yes only makes sense with --trigger"; exit 2; }

die() { print -u2 "error: $*"; exit 1; }
step() { print "\n== $* =="; }

# --trigger: the same as
#   git checkout main && git pull && git commit --allow-empty -m release && git push origin main
# with checks that stop BEFORE anything is pushed.
if $trigger; then
  [[ -z $(git status --porcelain --untracked-files=no) ]] ||
    die "uncommitted changes; commit or stash them first (they would be carried onto main)"

  step "Updating main"
  git checkout main
  git pull --ff-only origin main || die "main could not be fast-forwarded to origin/main; sort that out first"

  version_line=$(grep -m1 '^version:' pubspec.yaml) || die "no version: line in pubspec.yaml"
  full_version=${${version_line#version:}// /}
  version=${full_version%%+*}
  [[ ${full_version#*+} != $full_version ]] || die "pubspec.yaml version needs a build number, e.g. $version+1"
  tag="v$version"

  step "Checking $tag can be released"
  [[ $(git log -1 --format=%s) != [Rr]elease ]] ||
    die "main is already on a 'release' commit; check the Release run in GitHub Actions"
  grep -q "^## \[$version\]" CHANGELOG.md || die "CHANGELOG.md on main has no '## [$version]' section"
  [[ -z $(git ls-remote --tags origin "refs/tags/$tag") ]] ||
    die "tag $tag already exists on origin; bump the version in pubspec.yaml"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh release view "$tag" >/dev/null 2>&1 && die "release $tag already exists; bump the version in pubspec.yaml"
  else
    print "(gh not available or not logged in; skipped the GitHub release check, the tag check passed)"
  fi
  print "OK: My Little CRM $version (pubspec $full_version) at $(git log -1 --format='%h %s')"

  if ! $yes; then
    [[ -t 0 ]] || die "not a terminal; pass --yes to push without asking"
    read -r "answer?Push an empty 'release' commit to origin/main and publish $tag? [y/N] "
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || { print "Cancelled; nothing was committed or pushed."; exit 1; }
  fi

  step "Triggering the release workflow"
  git commit --allow-empty -m release
  if ! git push origin main; then
    git reset -q --soft HEAD~1
    die "push failed; the local 'release' commit was undone, nothing was published"
  fi
  print "\nPushed. GitHub Actions is now building and publishing $tag:"
  print "  https://github.com/danijeljw-RPC/my-little-crm/actions/workflows/release.yml"
  exit 0
fi

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
apk_sha256=$(print -r -- "$certs" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
[[ -n $apk_sha256 ]] || die "could not read the APK signer's SHA-256 fingerprint"

if $aab; then
  command -v keytool >/dev/null 2>&1 || die "keytool not found; install a JDK"
  step "Building release-signed app bundle (Google Play)"
  MLC_RELEASE_SIGNING=1 flutter build appbundle --release
  bundle=build/app/outputs/bundle/release/app-release.aab
  [[ -f $bundle ]] || die "build finished but $bundle is missing"

  step "Verifying bundle signature"
  bundle_certs=$(keytool -printcert -jarfile "$bundle") || die "keytool could not read the bundle signature"
  bundle_signer=$(print -r -- "$bundle_certs" | sed -n 's/^Owner: //p' | head -1)
  print "Signer: $bundle_signer"
  [[ $bundle_signer == *"CN=Android Debug"* ]] && die "bundle is signed with the DEBUG key; do not upload it"
  # keytool prints "SHA256: E1:C8:..."; apksigner prints "e1c8...". Compare normalised.
  bundle_sha256=$(print -r -- "$bundle_certs" | sed -n 's/^[[:space:]]*SHA256: //p' | head -1)
  bundle_sha256=${(L)${bundle_sha256//:/}}
  [[ $bundle_sha256 == $apk_sha256 ]] ||
    die "bundle signer ($bundle_sha256) differs from the APK signer ($apk_sha256)"
fi

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
if $aab; then
  cp "$bundle" "dist/$name.aab"
  ( cd dist && shasum -a 256 "$name.aab" > "$name.aab.sha256" )
  print "dist/$name.aab  (upload to Google Play Console; build $build_number)"
fi

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

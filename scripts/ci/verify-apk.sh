#!/usr/bin/env bash
# Verify that an APK is signed, and not with the Android debug key.
#
#   scripts/ci/verify-apk.sh path/to/app-release.apk
#
# Used by .github/workflows/release.yml and .github/workflows/android-apk.yml.
# Needs ANDROID_HOME (or ANDROID_SDK_ROOT) with build-tools installed.
# Prints the certificate details (not the public key) so a failure explains itself.
set -euo pipefail

apk=${1:?usage: verify-apk.sh <apk>}
[[ -f $apk ]] || { echo "::error::APK not found: $apk"; exit 1; }
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -n $sdk && -d $sdk/build-tools ]] || { echo "::error::no Android SDK build-tools (set ANDROID_HOME)"; exit 1; }

# Newest build-tools that actually ships apksigner (as scripts/release.sh does).
apksigner=""
for dir in $(ls -d "$sdk"/build-tools/*/ | sort -Vr); do
  if [[ -x ${dir}apksigner ]]; then apksigner=${dir}apksigner; break; fi
done
[[ -n $apksigner ]] || { echo "::error::apksigner not found under $sdk/build-tools"; exit 1; }
echo "Using $apksigner ($("$apksigner" --version))"

# Keep apksigner's own output and exit status.
if ! certs=$("$apksigner" verify --print-certs "$apk" 2>&1); then
  echo "$certs"
  echo "::error::apksigner verify failed for $apk"
  exit 1
fi
echo "$certs" | grep -v -i 'public key' || true

# The signer line format depends on the build-tools version, e.g.
#   Signer #1 certificate DN: ...                    (36.x)
#   V2 Signer: certificate DN: ...                   (37.x)
#   Signer (minSdkVersion=33, ...) certificate DN: ... (SDK-ranged signers)
# so take the first "certificate DN:" line of any form.
signer=$(echo "$certs" | sed -n 's/^.*[Ss]igner.*certificate DN: //p' | head -1)
echo "Signer: $signer"
[[ -n $signer ]] || { echo "::error::could not read the APK signer from the output above"; exit 1; }
[[ $signer != *"CN=Android Debug"* ]] || { echo "::error::APK is signed with the DEBUG key"; exit 1; }
echo "OK: $apk is release-signed"

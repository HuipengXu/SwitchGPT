#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
version="${SWITCHGPT_VERSION:-0.1.0}"
build_number="${SWITCHGPT_BUILD_NUMBER:-1}"
signing_identity="${SWITCHGPT_SIGNING_IDENTITY:-}"
keychain_profile="${SWITCHGPT_NOTARY_KEYCHAIN_PROFILE:-}"
release_directory="$repository_root/dist/release"
app_bundle="$release_directory/SwitchGPT.app"

cd "$repository_root"

if [[ -z "$signing_identity" ]]; then
  echo "SWITCHGPT_SIGNING_IDENTITY is required for notarization" >&2
  exit 64
fi
if [[ -z "$keychain_profile" ]]; then
  echo "SWITCHGPT_NOTARY_KEYCHAIN_PROFILE is required for notarization" >&2
  echo "Store Apple credentials in Keychain with xcrun notarytool store-credentials first." >&2
  exit 64
fi

SWITCHGPT_VERSION="$version" \
SWITCHGPT_BUILD_NUMBER="$build_number" \
SWITCHGPT_SIGNING_IDENTITY="$signing_identity" \
  "$script_directory/package-release.sh"

architectures="$(/usr/bin/lipo -archs "$app_bundle/Contents/MacOS/SwitchGPT")"
case "$architectures" in
  arm64|x86_64)
    architecture_label="$architectures"
    ;;
  "arm64 x86_64"|"x86_64 arm64")
    architecture_label="universal"
    ;;
  *)
    echo "unsupported release architectures: $architectures" >&2
    exit 1
    ;;
esac

archive="$release_directory/SwitchGPT-$version-macOS-$architecture_label.zip"
checksum="$archive.sha256"
notary_result="$(/usr/bin/mktemp -t switchgpt-notary-result)"
trap '/bin/rm -f "$notary_result"' EXIT

echo "Submitting the Developer ID archive to Apple Notary Service..."
if ! xcrun notarytool submit "$archive" \
  --keychain-profile "$keychain_profile" \
  --wait \
  --output-format json > "$notary_result"; then
  echo "Apple Notary Service submission failed" >&2
  exit 1
fi

notary_status="$(/usr/bin/plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)"
submission_id="$(/usr/bin/plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"
if [[ "$notary_status" != "Accepted" ]]; then
  echo "Apple Notary Service did not accept the archive (status: ${notary_status:-unknown})" >&2
  if [[ -n "$submission_id" ]]; then
    echo "submission id: $submission_id" >&2
    echo "Inspect it explicitly with xcrun notarytool log before retrying." >&2
  fi
  exit 1
fi
echo "Apple Notary Service accepted submission: $submission_id"

xcrun stapler staple -v "$app_bundle"
xcrun stapler validate -v "$app_bundle"
"$script_directory/verify-release-app.sh" --app "$app_bundle" --require-developer-id
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_bundle"

# Stapling changes the app bundle, so replace the submitted archive with the
# final ticket-bearing artifact and regenerate its checksum.
/bin/rm -f "$archive" "$checksum"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
(
  cd "$release_directory"
  /usr/bin/shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
)

echo "notarized release archive: $archive"
echo "sha256: $checksum"

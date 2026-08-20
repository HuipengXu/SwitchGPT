#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
version="${SWITCHGPT_VERSION:-0.1.0}"
build_number="${SWITCHGPT_BUILD_NUMBER:-1}"
signing_identity="${SWITCHGPT_SIGNING_IDENTITY:-}"
release_directory="$repository_root/dist/release"
app_bundle="$release_directory/SwitchGPT.app"

cd "$repository_root"

if [[ -z "$signing_identity" ]]; then
  echo "SWITCHGPT_SIGNING_IDENTITY is required for release packaging" >&2
  exit 64
fi

SWITCHGPT_VERSION="$version" \
SWITCHGPT_BUILD_NUMBER="$build_number" \
SWITCHGPT_SIGNING_IDENTITY="$signing_identity" \
  "$script_directory/build-release-app.sh"

if [[ ! -d "$app_bundle" || -L "$app_bundle" ]]; then
  echo "release app bundle is missing or unsafe: $app_bundle" >&2
  exit 1
fi

"$script_directory/verify-release-app.sh" --app "$app_bundle" --require-developer-id

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
verification_directory="$(/usr/bin/mktemp -d -t switchgpt-release-verification)"
trap '/bin/rm -rf "$verification_directory"' EXIT

/bin/rm -f "$archive" "$checksum"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
/usr/bin/ditto -x -k "$archive" "$verification_directory"
"$script_directory/verify-release-app.sh" \
  --app "$verification_directory/SwitchGPT.app" \
  --require-developer-id
(
  cd "$release_directory"
  /usr/bin/shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
)

echo "release archive: $archive"
echo "sha256: $checksum"

#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_name="SwitchGPT"
bundle_id="com.kunpeng.SwitchGPT"
version="${SWITCHGPT_VERSION:-0.1.0}"
build_number="${SWITCHGPT_BUILD_NUMBER:-1}"
signing_identity="${SWITCHGPT_SIGNING_IDENTITY:-}"
dist_directory="$repository_root/dist/release"
app_bundle="$dist_directory/$app_name.app"
app_contents="$app_bundle/Contents"
app_binary="$app_contents/MacOS/$app_name"

cd "$repository_root"

if [[ -z "$signing_identity" ]]; then
  echo "SWITCHGPT_SIGNING_IDENTITY is required for a distributable archive" >&2
  echo "Use an Apple Development identity for local validation or a Developer ID Application identity for distribution." >&2
  exit 64
fi

swift build -c release --product SwitchGPTApp
build_bin_dir="$(swift build -c release --show-bin-path)"
build_binary="$build_bin_dir/SwitchGPTApp"

/bin/rm -rf "$app_bundle"
/bin/mkdir -p "$app_contents/MacOS"
/bin/cp "$build_binary" "$app_binary"
/bin/cp "$repository_root/App/Info.plist" "$app_contents/Info.plist"
/usr/bin/plutil -lint "$app_contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$app_contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$build_number" "$app_contents/Info.plist"
/bin/chmod 755 "$app_binary"

if [[ ! -x "$app_binary" ]]; then
  echo "release executable was not staged: $app_binary" >&2
  exit 1
fi

/usr/bin/codesign --force --sign "$signing_identity" --timestamp --options runtime "$app_binary"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp --options runtime "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

actual_executable="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$app_contents/Info.plist")"
if [[ "$actual_executable" != "$app_name" ]]; then
  echo "bundle executable does not match staged binary" >&2
  exit 1
fi

echo "release app: $app_bundle"
echo "bundle id: $bundle_id"
echo "version: $version ($build_number)"
echo "signing identity: $signing_identity"

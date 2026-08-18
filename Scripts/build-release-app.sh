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
app_resources="$app_contents/Resources"
app_icon="$app_resources/AppIcon.icns"
helper_directory="$app_contents/Helpers"
recovery_helper="$helper_directory/SwitchGPTRecoverySupervisor"

cd "$repository_root"

if [[ -z "$signing_identity" ]]; then
  echo "SWITCHGPT_SIGNING_IDENTITY is required for a distributable archive" >&2
  echo "Use an Apple Development identity for local validation or a Developer ID Application identity for distribution." >&2
  exit 64
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "SWITCHGPT_VERSION must be a numeric macOS bundle version such as 0.1.0" >&2
  exit 64
fi
if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "SWITCHGPT_BUILD_NUMBER must contain one to three numeric components" >&2
  exit 64
fi

swift build -c release --product SwitchGPTApp
swift build -c release --product SwitchGPTRecoverySupervisor
build_bin_dir="$(swift build -c release --show-bin-path)"
build_binary="$build_bin_dir/SwitchGPTApp"
build_recovery_helper="$build_bin_dir/SwitchGPTRecoverySupervisor"

/bin/rm -rf "$app_bundle"
/bin/mkdir -p "$app_contents/MacOS"
/bin/mkdir -p "$app_resources"
/bin/mkdir -p "$helper_directory"
/bin/cp "$build_binary" "$app_binary"
/bin/cp "$build_recovery_helper" "$recovery_helper"
/bin/cp "$repository_root/App/Info.plist" "$app_contents/Info.plist"
/bin/cp "$repository_root/App/Assets/AppIcon.icns" "$app_icon"
/usr/bin/plutil -lint "$app_contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$app_contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$build_number" "$app_contents/Info.plist"
/bin/chmod 755 "$app_binary"
/bin/chmod 755 "$recovery_helper"

if [[ ! -x "$app_binary" ]]; then
  echo "release executable was not staged: $app_binary" >&2
  exit 1
fi

/usr/bin/codesign --force --sign "$signing_identity" --timestamp --options runtime "$recovery_helper"
signing_team="$(/usr/bin/codesign -dvv "$recovery_helper" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
if [[ -z "$signing_team" ]]; then
  echo "Signed recovery helper has no TeamIdentifier" >&2
  exit 1
fi
/usr/bin/plutil -replace SwitchGPTHostTeamIdentifier -string "$signing_team" "$app_contents/Info.plist"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp --options runtime "$app_binary"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp --options runtime "$app_bundle"
"$script_directory/verify-release-app.sh" --app "$app_bundle"

echo "release app: $app_bundle"
echo "bundle id: $bundle_id"
echo "version: $version ($build_number)"
echo "signing identity: verified without printing account metadata"

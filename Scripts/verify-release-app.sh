#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_bundle="$repository_root/dist/release/SwitchGPT.app"
require_developer_id=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || { echo "--app requires a path" >&2; exit 64; }
      app_bundle="$2"
      shift 2
      ;;
    --require-developer-id)
      require_developer_id=true
      shift
      ;;
    *)
      echo "usage: $0 [--app path] [--require-developer-id]" >&2
      exit 64
      ;;
  esac
done

if [[ ! -d "$app_bundle" || -L "$app_bundle" ]]; then
  echo "release app bundle is missing or unsafe: $app_bundle" >&2
  exit 1
fi

app_contents="$app_bundle/Contents"
info_plist="$app_contents/Info.plist"
app_binary="$app_contents/MacOS/SwitchGPT"
recovery_helper="$app_contents/Helpers/SwitchGPTRecoverySupervisor"
app_icon="$app_contents/Resources/AppIcon.icns"

for required_path in "$info_plist" "$app_binary" "$recovery_helper" "$app_icon"; do
  if [[ ! -e "$required_path" || -L "$required_path" ]]; then
    echo "required release path is missing or unsafe: $required_path" >&2
    exit 1
  fi
done

/usr/bin/plutil -lint "$info_plist" >/dev/null

bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
bundle_executable="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$info_plist")"
bundle_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
bundle_build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info_plist")"
declared_team="$(/usr/bin/plutil -extract SwitchGPTHostTeamIdentifier raw -o - "$info_plist")"

if [[ "$bundle_id" != "com.kunpeng.SwitchGPT" ]]; then
  echo "unexpected release bundle identifier: $bundle_id" >&2
  exit 1
fi
if [[ "$bundle_executable" != "SwitchGPT" ]]; then
  echo "unexpected release executable: $bundle_executable" >&2
  exit 1
fi
if [[ ! "$bundle_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "invalid CFBundleShortVersionString: $bundle_version" >&2
  exit 1
fi
if [[ ! "$bundle_build" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "invalid CFBundleVersion: $bundle_build" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"

signature_details() {
  /usr/bin/codesign -dvvv "$1" 2>&1
}

app_signature="$(signature_details "$app_bundle")"
helper_signature="$(signature_details "$recovery_helper")"
app_team="$(/usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}' <<< "$app_signature")"
helper_team="$(/usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}' <<< "$helper_signature")"
app_authority="$(/usr/bin/awk -F= '/^Authority=/{print $2; exit}' <<< "$app_signature")"
helper_authority="$(/usr/bin/awk -F= '/^Authority=/{print $2; exit}' <<< "$helper_signature")"
authority_class="${app_authority%%:*}"
app_identifier="$(/usr/bin/awk -F= '/^Identifier=/{print $2; exit}' <<< "$app_signature")"
helper_identifier="$(/usr/bin/awk -F= '/^Identifier=/{print $2; exit}' <<< "$helper_signature")"

if [[ -z "$app_team" || "$app_team" != "$helper_team" || "$app_team" != "$declared_team" ]]; then
  echo "app, helper, and declared Team ID do not match" >&2
  exit 1
fi
if [[ "$app_identifier" != "com.kunpeng.SwitchGPT" ]]; then
  echo "unexpected signed app identifier: $app_identifier" >&2
  exit 1
fi
if [[ "$helper_identifier" != "SwitchGPTRecoverySupervisor" ]]; then
  echo "unexpected signed recovery helper identifier: $helper_identifier" >&2
  exit 1
fi
if [[ "$app_authority" != "$helper_authority" ]]; then
  echo "app and recovery helper signing authorities do not match" >&2
  exit 1
fi
if [[ "$app_signature" != *"flags=0x10000(runtime)"* || "$helper_signature" != *"flags=0x10000(runtime)"* ]]; then
  echo "hardened runtime is missing from the app or recovery helper" >&2
  exit 1
fi
if [[ "$require_developer_id" == true && "$app_authority" != Developer\ ID\ Application:* ]]; then
  echo "public distribution requires a Developer ID Application signature" >&2
  echo "actual signature class: $authority_class" >&2
  exit 1
fi

architectures="$(/usr/bin/lipo -archs "$app_binary")"
helper_architectures="$(/usr/bin/lipo -archs "$recovery_helper")"
if [[ "$architectures" != "$helper_architectures" ]]; then
  echo "app and recovery helper architectures do not match" >&2
  exit 1
fi

echo "release verification passed"
echo "bundle: $bundle_id $bundle_version ($bundle_build)"
echo "architectures: $architectures"
echo "team: $app_team"
echo "signature class: $authority_class"

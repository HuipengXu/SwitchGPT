#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
artifact_root="$repository_root/.build/lifecycle-validation"
app_path="$artifact_root/SwitchGPTLifecycleValidation.app"
contents_path="$app_path/Contents"
signing_identity="${1:--}"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [codesign-identity]" >&2
  exit 64
fi

if [[ "$artifact_root" != "$repository_root/.build/lifecycle-validation" ]]; then
  echo "refusing unexpected artifact path" >&2
  exit 1
fi

cd "$repository_root"
swift build -c release
binary_path="$(swift build -c release --show-bin-path)"

rm -rf "$artifact_root"
mkdir -p \
  "$contents_path/MacOS" \
  "$contents_path/Library/LaunchAgents" \
  "$contents_path/Library/LaunchServices"

install -m 0644 Lifecycle/App/Info.plist "$contents_path/Info.plist"
install -m 0755 \
  "$binary_path/SwitchGPTLifecycleHost" \
  "$contents_path/MacOS/SwitchGPTLifecycleHost"
install -m 0755 \
  "$binary_path/SwitchGPTBootRecovery" \
  "$contents_path/Library/LaunchServices/SwitchGPTBootRecovery"
install -m 0644 \
  Lifecycle/LaunchAgents/com.switchgpt.recovery-at-login.plist \
  "$contents_path/Library/LaunchAgents/com.switchgpt.recovery-at-login.plist"

plutil -lint "$contents_path/Info.plist"
plutil -lint Lifecycle/BootRecovery/Info.plist
plutil -lint "$contents_path/Library/LaunchAgents/com.switchgpt.recovery-at-login.plist"
"$contents_path/MacOS/SwitchGPTLifecycleHost" validate-bundle

codesign \
  --force \
  --sign "$signing_identity" \
  --timestamp=none \
  --options runtime \
  "$contents_path/Library/LaunchServices/SwitchGPTBootRecovery"
codesign \
  --force \
  --sign "$signing_identity" \
  --timestamp=none \
  --options runtime \
  "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
"$contents_path/MacOS/SwitchGPTLifecycleHost" validate-bundle
"$contents_path/MacOS/SwitchGPTLifecycleHost" registration-preflight
"$contents_path/MacOS/SwitchGPTLifecycleHost" service-status
"$repository_root/Scripts/audit-lifecycle-host-capabilities.sh"

printf '%s\n' "$app_path"

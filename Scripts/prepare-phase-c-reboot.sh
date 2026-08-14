#!/bin/bash

set -u
set -o pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="$HOME/Applications/SwitchGPTLifecycleValidation.app"
host_path="$app_path/Contents/MacOS/SwitchGPTLifecycleHost"
session_path="$HOME/Library/Application Support/com.switchgpt.lifecycle-validation/system-activation/sessions/phase-c-reboot-lifecycle"
auth_hash_path="$session_path/pre-reboot-auth.sha256"

if [[ $# -ne 2 \
  || "${1:-}" != "--confirm-system-service-mutation" \
  || "${2:-}" != "--confirm-reboot-required" ]]; then
  echo "usage: $0 --confirm-system-service-mutation --confirm-reboot-required" >&2
  exit 64
fi
if [[ ! -x "$host_path" || -L "$app_path" ]]; then
  echo "installed Phase C candidate is missing or unsafe" >&2
  exit 1
fi

auth_path="$HOME/.codex/auth.json"
if [[ ! -f "$auth_path" || -L "$auth_path" ]]; then
  echo "active authentication metadata is unavailable" >&2
  exit 1
fi
auth_hash_before="$(shasum -a 256 "$auth_path" | awk '{print $1}')"

codesign --verify --deep --strict --verbose=2 "$app_path" || exit 1
"$host_path" validate-bundle || exit 1
"$host_path" registration-preflight || exit 1
"$host_path" validate-install-location || exit 1

residue_before="$(
  SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
    "$repository_root/Scripts/audit-lifecycle-residue.sh"
)" || exit 1
printf '%s\n' "$residue_before"
if [[ "$residue_before" != *'"serviceStatus":"notRegistered"'* \
  || "$residue_before" != *'"installedPlistPresent":false'* \
  || "$residue_before" != *'"launchdJobPresent":false'* \
  || "$residue_before" != *'"recoveryProcessPresent":false'* ]]; then
  echo "refusing Phase C because the baseline is not explicitly unregistered and clean" >&2
  exit 1
fi
delivery_before="$("$host_path" phase-c-delivery-status)" || exit 1
printf '%s\n' "$delivery_before"
if [[ "$delivery_before" != *'"outcome":"notPrepared"'* ]]; then
  echo "Phase C evidence already exists; do not retry" >&2
  exit 1
fi

set +e
phase_output="$(
  "$host_path" phase-c-register-for-reboot \
    --confirm-system-service-mutation \
    --confirm-reboot-required
)"
phase_status=$?
set -e
printf '%s\n' "$phase_output"

if [[ $phase_status -ne 0 \
  || "$phase_output" != *'"outcome":"rebootLifecycleArmed"'* \
  || "$phase_output" != *'"registration":"registeredEnabled"'* \
  || "$phase_output" != *'"evidenceStatus":"armedOnCurrentBoot"'* ]]; then
  echo "Phase C did not arm cleanly; attempting the one owned emergency cleanup" >&2
  "$host_path" phase-c-emergency-unregister || true
  echo "Phase C stopped and must not be retried" >&2
  exit 1
fi

status_after="$("$host_path" service-status)" || exit 1
delivery_after="$("$host_path" phase-c-delivery-status)" || exit 1
residue_after="$(
  SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
    "$repository_root/Scripts/audit-lifecycle-residue.sh"
)" || exit 1
printf '%s\n%s\n%s\n' "$status_after" "$delivery_after" "$residue_after"
if [[ "$status_after" != *'"outcome":"enabled"'* \
  || "$delivery_after" != *'"outcome":"armedOnCurrentBoot"'* \
  || "$residue_after" != *'"serviceStatus":"enabled"'* \
  || "$residue_after" != *'"installedPlistPresent":false'* \
  || "$residue_after" != *'"recoveryProcessPresent":false'* ]]; then
  echo "Phase C post-registration state is ambiguous; attempting owned cleanup" >&2
  "$host_path" phase-c-emergency-unregister || true
  exit 1
fi

auth_hash_after="$(shasum -a 256 "$auth_path" | awk '{print $1}')"
if [[ "$auth_hash_after" != "$auth_hash_before" ]]; then
  echo '{"activeAuthHash":"changed"}' >&2
  "$host_path" phase-c-emergency-unregister || true
  exit 1
fi
echo '{"activeAuthHash":"unchanged"}'

if [[ -e "$auth_hash_path" || -L "$auth_hash_path" ]]; then
  echo "pre-reboot authentication metadata already exists; owned cleanup required" >&2
  "$host_path" phase-c-emergency-unregister || true
  exit 1
fi
umask 077
set -o noclobber
printf '%s\n' "$auth_hash_before" > "$auth_hash_path" || {
  "$host_path" phase-c-emergency-unregister || true
  exit 1
}
chmod 600 "$auth_hash_path"
/bin/sync
read -r hash_owner hash_mode hash_links < <(stat -f '%u %Lp %l' "$auth_hash_path")
if [[ "$hash_owner" -ne "$UID" || "$hash_mode" -ne 600 || "$hash_links" -ne 1 ]]; then
  echo "pre-reboot authentication metadata permissions are unsafe" >&2
  "$host_path" phase-c-emergency-unregister || true
  exit 1
fi

echo '{"phaseC":"armedAwaitingSeparatelyConfirmedReboot"}'

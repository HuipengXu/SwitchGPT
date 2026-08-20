#!/bin/bash

set -u
set -o pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="$HOME/Applications/SwitchGPTLifecycleValidation.app"
host_path="$app_path/Contents/MacOS/SwitchGPTLifecycleHost"
session_path="$HOME/Library/Application Support/com.switchgpt.lifecycle-validation/system-activation/sessions/phase-c-reboot-lifecycle"
evidence_path="$session_path/reboot-delivery/delivered-boot.identifier"
auth_hash_path="$session_path/pre-reboot-auth.sha256"

if [[ $# -ne 1 || "${1:-}" != "--confirm-system-service-mutation" ]]; then
  echo "usage: $0 --confirm-system-service-mutation" >&2
  exit 64
fi
if [[ ! -x "$host_path" || -L "$app_path" ]]; then
  echo "installed Phase C candidate is missing or unsafe" >&2
  exit 1
fi
if [[ ! -f "$evidence_path" || -L "$evidence_path" \
  || ! -f "$auth_hash_path" || -L "$auth_hash_path" ]]; then
  echo "Phase C reboot evidence or authentication metadata is unavailable" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path" || exit 1
"$host_path" validate-bundle || exit 1
"$host_path" registration-preflight || exit 1
"$host_path" validate-install-location || exit 1
delivery_status="$("$host_path" phase-c-delivery-status)" || exit 1
service_status="$("$host_path" service-status)" || exit 1
residue_before="$(
  SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
    "$repository_root/Scripts/audit-lifecycle-residue.sh"
)" || exit 1
printf '%s\n%s\n%s\n' "$delivery_status" "$service_status" "$residue_before"
if [[ "$delivery_status" != *'"outcome":"deliveredOnCurrentBoot"'* \
  || "$service_status" != *'"outcome":"enabled"'* \
  || "$residue_before" != *'"serviceStatus":"enabled"'* \
  || "$residue_before" != *'"installedPlistPresent":false'* \
  || "$residue_before" != *'"recoveryProcessPresent":false'* ]]; then
  echo "Phase C delivery is not uniquely proven; do not unregister automatically" >&2
  exit 1
fi

evidence_age_seconds="$(( $(date +%s) - $(stat -f %m "$evidence_path") ))"
if [[ "$evidence_age_seconds" -lt 300 ]]; then
  echo "five-minute no-repeat observation window has not elapsed" >&2
  exit 1
fi
if pgrep -x SwitchGPTBootRecovery >/dev/null 2>&1; then
  echo "recovery helper is unexpectedly still running" >&2
  exit 1
fi

expected_auth_hash="$(tr -d '\n' < "$auth_hash_path")"
active_auth_hash="$(shasum -a 256 "$HOME/.codex/auth.json" | awk '{print $1}')"
if [[ ${#expected_auth_hash} -ne 64 || "$active_auth_hash" != "$expected_auth_hash" ]]; then
  echo '{"activeAuthHash":"changedOrUnsafe"}' >&2
  exit 1
fi
echo '{"activeAuthHash":"unchanged"}'

set +e
phase_output="$(
  "$host_path" phase-c-unregister-after-reboot \
    --confirm-system-service-mutation
)"
phase_status=$?
set -e
printf '%s\n' "$phase_output"
if [[ $phase_status -ne 0 \
  || "$phase_output" != *'"outcome":"rebootLifecycleUnregistrationCompleted"'* \
  || "$phase_output" != *'"unregistration":"unregistered"'* ]]; then
  echo "Phase C cleanup is not proven; do not retry automatically" >&2
  exit 1
fi

for observation in immediate delayed; do
  residue="$(
    SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
      "$repository_root/Scripts/audit-lifecycle-residue.sh"
  )" || exit 1
  printf '%s\n' "$residue"
  if [[ "$residue" != *'"serviceStatus":"notRegistered"'* \
    || "$residue" != *'"installedPlistPresent":false'* \
    || "$residue" != *'"launchdJobPresent":false'* \
    || "$residue" != *'"recoveryProcessPresent":false'* ]]; then
    echo "Phase C zero residue is not proven; do not retry" >&2
    exit 1
  fi
  if [[ "$observation" == immediate ]]; then
    /bin/sleep 5
  fi
done

echo '{"phaseC":"completedWithUniqueDeliveryAndZeroResidue"}'

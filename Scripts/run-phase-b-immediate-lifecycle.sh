#!/bin/bash

set -u
set -o pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="$HOME/Applications/SwitchGPTLifecycleValidation.app"
host_path="$app_path/Contents/MacOS/SwitchGPTLifecycleHost"
confirmation="${1:-}"

has_zero_residue() {
  local evidence="$1"
  [[ "$evidence" == *'"installedPlistPresent":false'* \
    && "$evidence" == *'"launchdJobPresent":false'* \
    && "$evidence" == *'"recoveryProcessPresent":false'* ]]
}

has_terminal_service_status() {
  local evidence="$1"
  [[ "$evidence" == *'"serviceStatus":"notFound"'* \
    || "$evidence" == *'"serviceStatus":"notRegistered"'* ]]
}

if [[ "$confirmation" != "--confirm-system-service-mutation" || $# -ne 1 ]]; then
  echo "usage: $0 --confirm-system-service-mutation" >&2
  exit 64
fi
if [[ ! -x "$host_path" || -L "$app_path" ]]; then
  echo "installed Phase B candidate is missing or unsafe" >&2
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

residue_before="$(
  SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
    "$repository_root/Scripts/audit-lifecycle-residue.sh"
)" || exit 1
printf '%s\n' "$residue_before"
if ! has_zero_residue "$residue_before" \
  || ! has_terminal_service_status "$residue_before"; then
  echo "refusing Phase B because lifecycle residue is present" >&2
  exit 1
fi

set +e
phase_output="$("$host_path" phase-b-register-and-unregister --confirm-system-service-mutation)"
phase_status=$?
set -e
printf '%s\n' "$phase_output"

if [[ $phase_status -ne 0 ]]; then
  echo "activation host exited unexpectedly; attempting the one owned cleanup entry" >&2
  "$host_path" phase-b-emergency-unregister || true
fi

residue_after="$(
  SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
    "$repository_root/Scripts/audit-lifecycle-residue.sh"
)"
printf '%s\n' "$residue_after"
/bin/sleep 5
residue_observed="$(
  SWITCHGPT_LIFECYCLE_APP_PATH="$app_path" \
    "$repository_root/Scripts/audit-lifecycle-residue.sh"
)"
printf '%s\n' "$residue_observed"

auth_hash_after="$(shasum -a 256 "$auth_path" | awk '{print $1}')"
if [[ "$auth_hash_after" != "$auth_hash_before" ]]; then
  echo '{"activeAuthHash":"changed"}' >&2
  exit 1
fi
echo '{"activeAuthHash":"unchanged"}'

for evidence in "$residue_after" "$residue_observed"; do
  if ! has_zero_residue "$evidence" \
    || ! has_terminal_service_status "$evidence"; then
    echo "Phase B cleanup is not proven; do not retry" >&2
    exit 1
  fi
done

if [[ $phase_status -ne 0 ]]; then
  echo "Phase B host crashed even though residue is currently absent; do not retry" >&2
  exit 1
fi

if [[ "$phase_output" != *'"outcome":"immediateLifecycleCompleted"'* ]]; then
  echo "Phase B did not reach the immediate lifecycle command; do not retry automatically" >&2
  exit 1
fi
if [[ "$phase_output" != *'"registration":"registeredEnabled"'* \
  && "$phase_output" != *'"registration":"registeredAwaitingApproval"'* \
  && "$phase_output" != *'"registration":"registrationUnconfirmed"'* ]]; then
  echo "Phase B did not prove that this invocation spent the registration attempt" >&2
  exit 1
fi
if [[ "$phase_output" != *'"unregistration":"unregistered"'* \
  && "$phase_output" != *'"unregistration":"alreadyUnregistered"'* \
  && "$phase_output" != *'"unregistration":"unregistrationUnconfirmed"'* ]]; then
  echo "Phase B did not spend the owned cleanup attempt" >&2
  exit 1
fi

echo '{"phaseB":"completedWithZeroResidue"}'

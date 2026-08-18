#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
source_app="$repository_root/.build/lifecycle-reboot/SwitchGPTLifecycleValidation.app"
destination_parent="$HOME/Applications"
destination_app="$destination_parent/SwitchGPTLifecycleValidation.app"
completed_phase_b_app="$destination_parent/SwitchGPTLifecycleValidation-PhaseB-Completed.app"
staged_app="$destination_parent/.SwitchGPTLifecycleValidation.phase-c.staged.app"
confirmation="${1:-}"
phase_b_attempts="$HOME/Library/Application Support/com.switchgpt.lifecycle-validation/system-activation/sessions/phase-b-immediate-lifecycle/activation-attempts"

if [[ "$confirmation" != "--prepare-phase-c-candidate" || $# -ne 1 ]]; then
  echo "usage: $0 --prepare-phase-c-candidate" >&2
  exit 64
fi
if [[ ! -d "$source_app" || -L "$source_app" ]]; then
  echo "signed reboot candidate is missing or unsafe" >&2
  exit 1
fi
if [[ -L "$destination_parent" || ! -d "$destination_parent" ]]; then
  echo "Applications destination is missing or unsafe" >&2
  exit 1
fi
read -r parent_owner parent_mode < <(stat -f '%u %Lp' "$destination_parent")
if [[ "$parent_owner" -ne "$UID" || $((8#$parent_mode & 8#022)) -ne 0 ]]; then
  echo "Applications destination ownership or permissions are unsafe" >&2
  exit 1
fi
if [[ -e "$staged_app" || -L "$staged_app" || -e "$completed_phase_b_app" \
  || -L "$completed_phase_b_app" ]]; then
  echo "Phase C staging or completed Phase B archive already exists" >&2
  exit 1
fi
for marker in registration.reserved unregistration.reserved; do
  marker_path="$phase_b_attempts/$marker"
  if [[ ! -f "$marker_path" || -L "$marker_path" \
    || "$(< "$marker_path")" != "reserved" ]]; then
    echo "completed Phase B ownership evidence is missing or unsafe" >&2
    exit 1
  fi
  read -r marker_owner marker_mode marker_links < <(stat -f '%u %Lp %l' "$marker_path")
  if [[ "$marker_owner" -ne "$UID" || "$marker_mode" -ne 600 \
    || "$marker_links" -ne 1 ]]; then
    echo "completed Phase B ownership evidence permissions are unsafe" >&2
    exit 1
  fi
done

codesign --verify --deep --strict --verbose=2 "$source_app"
"$source_app/Contents/MacOS/SwitchGPTLifecycleHost" validate-bundle
"$source_app/Contents/MacOS/SwitchGPTLifecycleHost" registration-preflight

if [[ -e "$destination_app" || -L "$destination_app" ]]; then
  if [[ -L "$destination_app" || ! -d "$destination_app" ]]; then
    echo "existing fixed-path candidate is unsafe" >&2
    exit 1
  fi
  codesign --verify --deep --strict --verbose=2 "$destination_app"
  current_status="$("$destination_app/Contents/MacOS/SwitchGPTLifecycleHost" service-status)"
  if [[ "$current_status" != *'"outcome":"notRegistered"'* ]]; then
    echo "refusing to replace a candidate whose service is not explicitly unregistered" >&2
    exit 1
  fi
fi

ditto "$source_app" "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"
"$staged_app/Contents/MacOS/SwitchGPTLifecycleHost" validate-bundle
"$staged_app/Contents/MacOS/SwitchGPTLifecycleHost" registration-preflight

if [[ -e "$destination_app" ]]; then
  mv "$destination_app" "$completed_phase_b_app"
fi
if ! mv "$staged_app" "$destination_app"; then
  if [[ -e "$completed_phase_b_app" && ! -e "$destination_app" ]]; then
    mv "$completed_phase_b_app" "$destination_app"
  fi
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$destination_app"
"$destination_app/Contents/MacOS/SwitchGPTLifecycleHost" validate-bundle
"$destination_app/Contents/MacOS/SwitchGPTLifecycleHost" registration-preflight
"$destination_app/Contents/MacOS/SwitchGPTLifecycleHost" validate-install-location
printf '%s\n' "$destination_app"

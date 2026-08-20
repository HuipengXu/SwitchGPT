#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
source_app="$repository_root/.build/lifecycle-activation/SwitchGPTLifecycleValidation.app"
destination_parent="$HOME/Applications"
destination_app="$destination_parent/SwitchGPTLifecycleValidation.app"
confirmation="${1:-}"

if [[ "$confirmation" != "--prepare-phase-b-candidate" || $# -ne 1 ]]; then
  echo "usage: $0 --prepare-phase-b-candidate" >&2
  exit 64
fi
if [[ ! -d "$source_app" || -L "$source_app" ]]; then
  echo "signed activation candidate is missing or unsafe" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$source_app"
"$source_app/Contents/MacOS/SwitchGPTLifecycleHost" validate-bundle
"$source_app/Contents/MacOS/SwitchGPTLifecycleHost" registration-preflight

if [[ -L "$destination_parent" ]]; then
  echo "refusing a symbolic-link Applications directory" >&2
  exit 1
fi
if [[ -e "$destination_parent" && ! -d "$destination_parent" ]]; then
  echo "Applications destination is not a directory" >&2
  exit 1
fi
if [[ ! -e "$destination_parent" ]]; then
  old_umask="$(umask)"
  umask 077
  mkdir "$destination_parent"
  umask "$old_umask"
fi
read -r parent_owner parent_mode < <(stat -f '%u %Lp' "$destination_parent")
if [[ "$parent_owner" -ne "$UID" || $((8#$parent_mode & 8#022)) -ne 0 ]]; then
  echo "Applications destination ownership or permissions are unsafe" >&2
  exit 1
fi
if [[ -e "$destination_app" || -L "$destination_app" ]]; then
  echo "refusing to overwrite existing Phase B candidate" >&2
  exit 1
fi

ditto "$source_app" "$destination_app"
codesign --verify --deep --strict --verbose=2 "$destination_app"
"$destination_app/Contents/MacOS/SwitchGPTLifecycleHost" validate-bundle
"$destination_app/Contents/MacOS/SwitchGPTLifecycleHost" registration-preflight

printf '%s\n' "$destination_app"

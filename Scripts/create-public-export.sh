#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
export_root="${1:-$repository_root/.build/public-export}"
expected_root="$repository_root/.build/public-export"

if [[ "$export_root" != "$expected_root" ]]; then
  echo "refusing unexpected export path: $export_root" >&2
  exit 64
fi

cd "$repository_root"
/bin/rm -rf "$export_root"
/bin/mkdir -p "$export_root"

public_entries=(
  ".github"
  ".gitignore"
  "App"
  "CHANGELOG.md"
  "CODE_OF_CONDUCT.md"
  "CONTRIBUTING.md"
  "LICENSE"
  "Lifecycle"
  "Package.swift"
  "README.md"
  "SECURITY.md"
  "Scripts"
  "Sources"
  "Tests"
  "website"
  "docs/MACOS_RECOVERY_ACTIVATION.md"
  "docs/ONE_SHOT_SUPERVISOR.md"
  "docs/PHASE_D_UPGRADE_LIFECYCLE.md"
  "docs/PUBLIC_RELEASE.md"
  "docs/REAL_ACCOUNT_SWITCH_TEST_RUNBOOK.md"
  "docs/SAFETY_CORE.md"
  "docs/SMAPPSERVICE_VALIDATION_RUNBOOK.md"
  "script"
)

for entry in "${public_entries[@]}"; do
  source_path="$repository_root/$entry"
  destination_path="$export_root/$entry"
  if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
    echo "missing public entry: $entry" >&2
    exit 1
  fi
  /bin/mkdir -p "$(dirname "$destination_path")"
  if [[ -d "$source_path" && ! -L "$source_path" ]]; then
    if [[ "$entry" == "website" ]]; then
      /usr/bin/rsync -a --exclude node_modules --exclude dist --exclude .vercel "$source_path/" "$destination_path/"
    else
      /usr/bin/ditto "$source_path" "$destination_path"
    fi
  else
    /bin/cp -p "$source_path" "$destination_path"
  fi
done

if /usr/bin/find "$export_root" \( -path '*/outputs/*' -o -path '*/work/*' -o -name 'auth.json' \) -print -quit | /usr/bin/grep -q .; then
  echo "private validation material entered public export" >&2
  exit 1
fi

echo "public export: $export_root"

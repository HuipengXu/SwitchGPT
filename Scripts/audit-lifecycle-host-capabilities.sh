#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
host_path="$repository_root/.build/lifecycle-validation/SwitchGPTLifecycleValidation.app/Contents/MacOS/SwitchGPTLifecycleHost"

if [[ ! -x "$host_path" ]]; then
  echo '{"hostPresent":false,"mutationSelectorsPresent":null}'
  exit 1
fi

selectors="$(
  /usr/bin/strings "$host_path" \
    | /usr/bin/awk '/^registerAndReturnError:$|^unregisterAndReturnError:$/ { print }' \
    || true
)"

if [[ -n "$selectors" ]]; then
  echo '{"hostPresent":true,"mutationSelectorsPresent":true}'
  exit 1
fi

echo '{"hostPresent":true,"mutationSelectorsPresent":false}'

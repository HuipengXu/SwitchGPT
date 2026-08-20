#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
host_path="$repository_root/.build/lifecycle-activation/SwitchGPTLifecycleValidation.app/Contents/MacOS/SwitchGPTLifecycleHost"

if [[ ! -x "$host_path" ]]; then
  echo '{"hostPresent":false,"registerSelectorPresent":null,"unregisterSelectorPresent":null,"systemSettingsSelectorPresent":null}'
  exit 1
fi

symbols="$(/usr/bin/strings "$host_path")"
register_present=false
unregister_present=false
system_settings_present=false

if /usr/bin/grep -Fq 'registerAndReturnError:' <<<"$symbols"; then
  register_present=true
fi
if /usr/bin/grep -Fq 'unregisterAndReturnError:' <<<"$symbols"; then
  unregister_present=true
fi
if /usr/bin/grep -Fq 'openSystemSettingsLoginItems' <<<"$symbols"; then
  system_settings_present=true
fi

printf '{"hostPresent":true,"registerSelectorPresent":%s,"unregisterSelectorPresent":%s,"systemSettingsSelectorPresent":%s}\n' \
  "$register_present" \
  "$unregister_present" \
  "$system_settings_present"

if [[ "$register_present" != true || "$unregister_present" != true || "$system_settings_present" != false ]]; then
  exit 1
fi

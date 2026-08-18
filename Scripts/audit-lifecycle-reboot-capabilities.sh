#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_path="$repository_root/.build/lifecycle-reboot/SwitchGPTLifecycleValidation.app/Contents/MacOS/SwitchGPTLifecycleHost"

host_present=false
register_selector_present=false
unregister_selector_present=false
system_settings_selector_present=false

if [[ -x "$host_path" ]]; then
  host_present=true
  if strings "$host_path" | grep -Fq 'registerAndReturnError:'; then
    register_selector_present=true
  fi
  if strings "$host_path" | grep -Fq 'unregisterAndReturnError:'; then
    unregister_selector_present=true
  fi
  if strings "$host_path" | grep -Fq 'openSystemSettingsLoginItems'; then
    system_settings_selector_present=true
  fi
fi

printf '{"hostPresent":%s,"registerSelectorPresent":%s,"unregisterSelectorPresent":%s,"systemSettingsSelectorPresent":%s}\n' \
  "$host_present" \
  "$register_selector_present" \
  "$unregister_selector_present" \
  "$system_settings_selector_present"

if [[ "$host_present" != true \
  || "$register_selector_present" != true \
  || "$unregister_selector_present" != true \
  || "$system_settings_selector_present" != false ]]; then
  exit 1
fi

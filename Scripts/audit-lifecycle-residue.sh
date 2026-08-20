#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
default_app_path="$repository_root/.build/lifecycle-validation/SwitchGPTLifecycleValidation.app"
installed_app_path="$HOME/Applications/SwitchGPTLifecycleValidation.app"
app_path="${SWITCHGPT_LIFECYCLE_APP_PATH:-$default_app_path}"
if [[ "$app_path" != "$default_app_path" && "$app_path" != "$installed_app_path" ]]; then
  echo "refusing unexpected lifecycle app path" >&2
  exit 64
fi
host_path="$app_path/Contents/MacOS/SwitchGPTLifecycleHost"
label="com.switchgpt.recovery-at-login"

service_status="artifactMissing"
if [[ -x "$host_path" ]]; then
  service_output="$($host_path service-status)"
  service_status="$(/usr/bin/sed -n 's/.*"outcome":"\([^"]*\)".*/\1/p' <<<"$service_output")"
  if [[ -z "$service_status" ]]; then
    service_status="unreadable"
  fi
fi

launchd_job_present=false
if /bin/launchctl print "gui/$(/usr/bin/id -u)/$label" >/dev/null 2>&1; then
  launchd_job_present=true
fi

installed_plist_present=false
for candidate in \
  "$HOME/Library/LaunchAgents/$label.plist" \
  "/Library/LaunchAgents/$label.plist" \
  "/Library/LaunchDaemons/$label.plist"
do
  if [[ -e "$candidate" || -L "$candidate" ]]; then
    installed_plist_present=true
  fi
done

recovery_process_present=false
if /usr/bin/pgrep -x SwitchGPTBootRecovery >/dev/null 2>&1; then
  recovery_process_present=true
fi

printf '{"installedPlistPresent":%s,"launchdJobPresent":%s,"recoveryProcessPresent":%s,"serviceStatus":"%s"}\n' \
  "$installed_plist_present" \
  "$launchd_job_present" \
  "$recovery_process_present" \
  "$service_status"

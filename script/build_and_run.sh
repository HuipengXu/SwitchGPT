#!/usr/bin/env bash

set -euo pipefail

mode="${1:-run}"
app_name="SwitchGPT"
bundle_id="com.kunpeng.SwitchGPT"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repository_root/dist"
app_bundle="$dist_dir/$app_name.app"
app_contents="$app_bundle/Contents"
app_macos="$app_contents/MacOS"
app_binary="$app_macos/$app_name"
info_plist="$app_contents/Info.plist"

cd "$repository_root"

# Only stop this exact app process. ChatGPT and all lifecycle validation hosts
# are deliberately outside this run-loop's process scope.
pkill -x "$app_name" >/dev/null 2>&1 || true

swift build -c debug --product SwitchGPTApp
build_bin_dir="$(swift build -c debug --show-bin-path)"
build_binary="$build_bin_dir/SwitchGPTApp"

rm -rf "$app_bundle"
mkdir -p "$app_macos"
cp "$build_binary" "$app_binary"
cp "$repository_root/App/Info.plist" "$info_plist"
chmod 755 "$app_binary"

signing_identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:/{print $2; exit}')"
if [[ -n "$signing_identity" ]]; then
  codesign --force --sign "$signing_identity" --timestamp=none --options runtime "$app_binary" >/dev/null
  codesign --force --sign "$signing_identity" --timestamp=none --options runtime "$app_bundle" >/dev/null
  echo "Signed with Apple Development identity"
else
  codesign --force --sign - --timestamp=none "$app_binary" >/dev/null
  codesign --force --sign - --timestamp=none "$app_bundle" >/dev/null
  echo "Apple Development identity unavailable; using ad hoc signing for local launch"
fi

codesign --verify --deep --strict "$app_bundle"

open_app() {
  /usr/bin/open -n "$app_bundle"
}

verify_process() {
  for _ in {1..30}; do
    if pgrep -x "$app_name" >/dev/null 2>&1; then
      echo "Running: $app_name"
      return 0
    fi
    sleep 0.2
  done

  echo "App process did not stay alive: $app_name" >&2
  return 1
}

case "$mode" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$app_binary"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$app_name\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$bundle_id\""
    ;;
  --verify|verify)
    open_app
    verify_process
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

#!/bin/bash

set -euo pipefail

scan_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
strict=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "--root requires a directory" >&2; exit 64; }
      scan_root="$(cd "$2" && pwd)"
      shift 2
      ;;
    --strict)
      strict=true
      shift
      ;;
    *)
      echo "usage: $0 [--strict] [--root directory]" >&2
      exit 64
      ;;
  esac
done

cd "$scan_root"

failures=0

retired_submit_pattern='launchctl[[:space:]]+sub''mit'
runtime_roots=()
for candidate in App Lifecycle Scripts Sources script; do
  if [[ -e "$candidate" ]]; then
    runtime_roots+=("$candidate")
  fi
done

if [[ "${#runtime_roots[@]}" -gt 0 ]]; then
  retired_submit_paths="$(/usr/bin/rg -Il --hidden "$retired_submit_pattern" "${runtime_roots[@]}" 2>/dev/null || true)"
  if [[ -n "$retired_submit_paths" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      echo "retired submitted-job control path detected in: $path" >&2
      failures=$((failures + 1))
    done <<< "$retired_submit_paths"
  fi
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_paths=(git ls-files -z)
else
  tracked_paths=(find . -type f -not -path './.git/*' -print0)
fi

while IFS= read -r -d '' path; do
  case "$path" in
    *auth.json|*.token|*cookies*|*.p12|*.p8|*.mobileprovision|*.pem|*.key)
      echo "forbidden credential-like tracked path: $path" >&2
      failures=$((failures + 1))
      ;;
    ./outputs/*|outputs/*|./work/*|work/*|./docs/PROJECT_CONTEXT.md|docs/PROJECT_CONTEXT.md)
      if [[ "$strict" == true ]]; then
        echo "private validation path is not allowed in strict public tree: $path" >&2
        failures=$((failures + 1))
      fi
      ;;
  esac
done < <("${tracked_paths[@]}" 2>/dev/null)

secret_pattern='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|(sk|rk)-[A-Za-z0-9]{20,}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----'
secret_paths="$(mktemp -t switchgpt-public-secret-paths)"
trap 'rm -f "$secret_paths"' EXIT
if /usr/bin/rg -Il --hidden \
  -g '!.git/**' \
  -g '!.build/**' \
  -g '!dist/**' \
  "$secret_pattern" . >"$secret_paths" 2>/dev/null; then
  while IFS= read -r path; do
    echo "credential-like content detected in: $path" >&2
    failures=$((failures + 1))
  done < "$secret_paths"
fi

if [[ "$failures" -ne 0 ]]; then
  echo "public repository audit failed: $failures finding(s)" >&2
  exit 1
fi

echo "public repository audit passed"

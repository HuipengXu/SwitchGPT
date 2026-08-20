#!/bin/bash

set -euo pipefail

repository_root=""
require_single_commit=false
require_no_remotes=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "--repo requires a directory" >&2; exit 64; }
      repository_root="$(cd "$2" && pwd)"
      shift 2
      ;;
    --single-commit)
      require_single_commit=true
      shift
      ;;
    --require-no-remotes)
      require_no_remotes=true
      shift
      ;;
    *)
      echo "usage: $0 --repo directory [--single-commit] [--require-no-remotes]" >&2
      exit 64
      ;;
  esac
done

[[ -n "$repository_root" ]] || {
  echo "--repo is required" >&2
  exit 64
}

/usr/bin/git -C "$repository_root" rev-parse --is-inside-work-tree >/dev/null

failures=0
commit_count="$(/usr/bin/git -C "$repository_root" rev-list --all --count)"

if [[ "$require_single_commit" == true && "$commit_count" -ne 1 ]]; then
  echo "public candidate must contain exactly one commit; found $commit_count" >&2
  failures=$((failures + 1))
fi

if [[ "$require_no_remotes" == true ]]; then
  remote_count="$(/usr/bin/git -C "$repository_root" remote | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
  if [[ "$remote_count" -ne 0 ]]; then
    echo "public candidate must not have a configured remote" >&2
    failures=$((failures + 1))
  fi
fi

while IFS= read -r commit; do
  while IFS= read -r tracked_path; do
    case "$tracked_path" in
      outputs/*|work/*|docs/PROJECT_CONTEXT.md|*auth.json|*.token|*cookies*|*.p12|*.p8|*.mobileprovision|*.pem|*.key)
        echo "forbidden path in public history: $commit:$tracked_path" >&2
        failures=$((failures + 1))
        ;;
    esac
  done < <(/usr/bin/git -C "$repository_root" ls-tree -r --name-only "$commit")
done < <(/usr/bin/git -C "$repository_root" rev-list --all)

secret_pattern='eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|(sk|rk)-[A-Za-z0-9]{20,}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----'
while IFS= read -r commit; do
  secret_matches="$(/usr/bin/git -C "$repository_root" grep -Il -E "$secret_pattern" "$commit" -- . 2>/dev/null || true)"
  if [[ -n "$secret_matches" ]]; then
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      echo "credential-like content in public history: $match" >&2
      failures=$((failures + 1))
    done <<< "$secret_matches"
  fi
done < <(/usr/bin/git -C "$repository_root" rev-list --all)

if [[ "$failures" -ne 0 ]]; then
  echo "public history audit failed: $failures finding(s)" >&2
  exit 1
fi

echo "public history audit passed: $commit_count commit(s)"

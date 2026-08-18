#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
export_root="$repository_root/.build/public-export"
candidate_root="$repository_root/.build/public-release-repo"
expected_candidate_root="$repository_root/.build/public-release-repo"

if [[ "$candidate_root" != "$expected_candidate_root" ]]; then
  echo "refusing unexpected public candidate path: $candidate_root" >&2
  exit 64
fi

if [[ -n "$(/usr/bin/git -C "$repository_root" status --porcelain --untracked-files=normal)" ]]; then
  echo "refusing to prepare a public candidate from a dirty worktree" >&2
  exit 1
fi

"$script_directory/create-public-export.sh" "$export_root"

/bin/rm -rf "$candidate_root"
/bin/mkdir -m 700 -p "$candidate_root"
/usr/bin/rsync -a --exclude .git "$export_root/" "$candidate_root/"

/usr/bin/git -C "$candidate_root" init -q -b main
/usr/bin/git -C "$candidate_root" config user.name "SwitchGPT Release Builder"
/usr/bin/git -C "$candidate_root" config user.email "noreply@switchgpt.local"
/usr/bin/git -C "$candidate_root" add --all
/usr/bin/git -C "$candidate_root" commit -q -m "SwitchGPT 0.1.0 public release candidate"

"$script_directory/audit-public-repo.sh" --strict --root "$candidate_root"
"$script_directory/audit-public-history.sh" \
  --repo "$candidate_root" \
  --single-commit \
  --require-no-remotes

if [[ -n "$(/usr/bin/git -C "$candidate_root" status --porcelain --untracked-files=all)" ]]; then
  echo "public candidate worktree is unexpectedly dirty" >&2
  exit 1
fi

candidate_commit="$(/usr/bin/git -C "$candidate_root" rev-parse HEAD)"
echo "public release candidate: $candidate_root"
echo "candidate commit: $candidate_commit"

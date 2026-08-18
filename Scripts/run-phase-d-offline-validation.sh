#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"

cd "$repository_root"
xcrun swift test --filter UpgradeLifecycleTests
xcrun swift run SwitchGPTSafetySimulator matrix

#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="${M4_RESULT_ROOT:-$repo_root/.m4-results}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
result_dir="$result_root/$timestamp"
derived_data="$result_dir/DerivedData"

mkdir -p "$result_dir"
cd "$repo_root"

"$repo_root/scripts/check_release_hygiene.sh" | tee "$result_dir/hygiene.log"

xcodebuild \
    -quiet \
    -project WaterDropTodo.xcodeproj \
    -scheme WaterDropTodo \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_dir/ReleaseTests.xcresult" \
    ENABLE_TESTABILITY=YES \
    ENABLE_HARDENED_RUNTIME=NO \
    test | tee "$result_dir/release-test.log"

release_app="$derived_data/Build/Products/Release/WaterDropTodo.app"
[[ -d "$release_app" ]] || {
    echo "M4 Release gate failed: built app not found" >&2
    exit 1
}

if rg -a -n 'Metal 液体 Spike|跨窗口动画 Spike' "$release_app"; then
    echo "M4 Release gate failed: debug panel content found in Release app" >&2
    exit 1
fi

echo "M4 Release gate passed: $result_dir"

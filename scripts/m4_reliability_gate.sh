#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="${M4_RESULT_ROOT:-$repo_root/.m4-results}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
result_dir="$result_root/$timestamp-reliability"
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
    -resultBundlePath "$result_dir/reliability.xcresult" \
    ENABLE_TESTABILITY=YES \
    ENABLE_HARDENED_RUNTIME=NO \
    -only-testing:WaterDropTodoTests \
    test | tee "$result_dir/reliability.log"

echo "M4B reliability gate passed: $result_dir"

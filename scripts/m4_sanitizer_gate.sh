#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "thread" && "$1" != "address" ) ]]; then
    echo "usage: $0 thread|address" >&2
    exit 2
fi

sanitizer="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="${M4_RESULT_ROOT:-$repo_root/.m4-results}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
result_dir="$result_root/$timestamp-$sanitizer"
derived_data="$result_dir/DerivedData"
mkdir -p "$result_dir"
cd "$repo_root"

common=(
    -project WaterDropTodo.xcodeproj
    -scheme WaterDropTodo
    -configuration Debug
    -destination 'platform=macOS'
    -derivedDataPath "$derived_data"
    -resultBundlePath "$result_dir/${sanitizer}.xcresult"
)

if [[ "$sanitizer" == "thread" ]]; then
    xcodebuild "${common[@]}" \
        -enableThreadSanitizer YES \
        CODE_SIGNING_ALLOWED=NO \
        -only-testing:WaterDropTodoTests \
        test | tee "$result_dir/thread-sanitizer.log"
else
    xcodebuild "${common[@]}" \
        -enableAddressSanitizer YES \
        -only-testing:WaterDropTodoUITests/WaterDropTodoUITests/testExample \
        -only-testing:WaterDropTodoUITests/WaterDropTodoUITests/testListRowTransitionReachesScreenBottom \
        test | tee "$result_dir/address-sanitizer.log"
fi

echo "M4 $sanitizer sanitizer gate passed: $result_dir"

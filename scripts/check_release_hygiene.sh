#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail() {
    echo "M4 hygiene failed: $1" >&2
    exit 1
}

git diff --check

strict_concurrency_count="$(grep -c 'SWIFT_STRICT_CONCURRENCY = complete;' WaterDropTodo.xcodeproj/project.pbxproj)"
[[ "$strict_concurrency_count" -ge 2 ]] \
    || fail "Strict Concurrency Complete is not pinned for Debug and Release"

grep -q 'SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;' WaterDropTodo.xcodeproj/project.pbxproj \
    || fail "Release warnings are not treated as errors"

grep -q 'ENABLE_HARDENED_RUNTIME = YES;' WaterDropTodo.xcodeproj/project.pbxproj \
    || fail "Release Hardened Runtime is not enabled"

entitlements="WaterDropTodo/WaterDropTodo.entitlements"
[[ -f "$entitlements" ]] || fail "app entitlements file is missing"
plutil -lint "$entitlements" >/dev/null
[[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw "$entitlements")" == "true" ]] \
    || fail "App Sandbox entitlement is missing"

shared_scheme="WaterDropTodo.xcodeproj/xcshareddata/xcschemes/WaterDropTodo.xcscheme"
[[ -f "$shared_scheme" ]] || fail "shared WaterDropTodo scheme is missing"
xmllint --noout "$shared_scheme"

package_lock="WaterDropTodo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
[[ -f "$package_lock" ]] || fail "Package.resolved is missing"
jq -e '
    (.pins | length == 1) and
    (.pins[0].identity == "keyboardshortcuts") and
    (.pins[0].state.version == "3.0.1")
' "$package_lock" >/dev/null || fail "KeyboardShortcuts must be the only dependency at exactly 3.0.1"

if rg -n --hidden --glob '!scripts/check_release_hygiene.sh' \
    --glob '!.git/**' \
    '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|notarytool.*(--password|--apple-id)|AC_PASSWORD=|APPLE_ID_PASSWORD=)' .; then
    fail "possible signing/notary secret found"
fi

if rg -n 'AppLog\.(info|error)\([^\n]*(task\.title|record\.title|input\.title)' WaterDropTodo; then
    fail "task title appears in a log call"
fi

while IFS= read -r -d '' asset_json; do
    jq empty "$asset_json"
done < <(find WaterDropTodo/Assets.xcassets -name Contents.json -print0)

app_icon_catalog="WaterDropTodo/Assets.xcassets/AppIcon.appiconset/Contents.json"
[[ "$(jq '[.images[] | select(.filename != null)] | length' "$app_icon_catalog")" == "10" ]] \
    || fail "AppIcon must provide all 10 macOS image slots"
while IFS= read -r icon_name; do
    [[ -s "WaterDropTodo/Assets.xcassets/AppIcon.appiconset/$icon_name" ]] \
        || fail "AppIcon file is missing or empty: $icon_name"
done < <(jq -r '.images[].filename' "$app_icon_catalog")

if rg -n 'LiquidDebugPanel|Metal 液体 Spike' WaterDropTodo; then
    fail "obsolete liquid style controls must not appear in the app UI"
fi

echo "M4 hygiene passed"

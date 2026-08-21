#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
    echo "usage: $0 <app-path> local|signed [expected-version] [expected-build]" >&2
    exit 2
fi

app_path="$1"
mode="$2"
expected_version="${3:-}"
expected_build="${4:-}"

if [[ "$mode" != "local" && "$mode" != "signed" ]]; then
    echo "M4C verification failed: mode must be local or signed" >&2
    exit 2
fi

[[ -d "$app_path" ]] || {
    echo "M4C verification failed: app not found at $app_path" >&2
    exit 1
}

info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/WaterDropTodo"
icon="$app_path/Contents/Resources/AppIcon.icns"
[[ -f "$info_plist" ]] || { echo "M4C verification failed: Info.plist missing" >&2; exit 1; }
[[ -x "$executable" ]] || { echo "M4C verification failed: executable missing" >&2; exit 1; }
[[ -s "$icon" ]] || { echo "M4C verification failed: AppIcon.icns missing or empty" >&2; exit 1; }

bundle_id="$(plutil -extract CFBundleIdentifier raw "$info_plist")"
display_name="$(plutil -extract CFBundleDisplayName raw "$info_plist")"
version="$(plutil -extract CFBundleShortVersionString raw "$info_plist")"
build="$(plutil -extract CFBundleVersion raw "$info_plist")"
minimum_system="$(plutil -extract LSMinimumSystemVersion raw "$info_plist")"

[[ "$bundle_id" == "com.liuliuliu.WaterDropTodo" ]] \
    || { echo "M4C verification failed: unexpected Bundle ID $bundle_id" >&2; exit 1; }
[[ "$display_name" == "水滴待办" ]] \
    || { echo "M4C verification failed: unexpected display name $display_name" >&2; exit 1; }
[[ "$minimum_system" == "13.0" ]] \
    || { echo "M4C verification failed: unexpected minimum macOS $minimum_system" >&2; exit 1; }
[[ -z "$expected_version" || "$version" == "$expected_version" ]] \
    || { echo "M4C verification failed: expected version $expected_version, got $version" >&2; exit 1; }
[[ -z "$expected_build" || "$build" == "$expected_build" ]] \
    || { echo "M4C verification failed: expected build $expected_build, got $build" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$app_path"

verification_dir="${M4C_VERIFY_OUTPUT_DIR:-$(dirname "$app_path")/verification}"
mkdir -p "$verification_dir"
codesign -dv --verbose=4 "$app_path" 2> "$verification_dir/codesign-details.txt"
rg -q '^CodeDirectory .*flags=.*runtime' "$verification_dir/codesign-details.txt" \
    || { echo "M4C verification failed: Hardened Runtime signature flag missing" >&2; exit 1; }
codesign -d --entitlements :- "$app_path" \
    > "$verification_dir/entitlements.plist" \
    2> "$verification_dir/entitlements-details.txt"
plutil -lint "$verification_dir/entitlements.plist" >/dev/null
[[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw "$verification_dir/entitlements.plist")" == "true" ]] \
    || { echo "M4C verification failed: App Sandbox entitlement missing" >&2; exit 1; }
[[ "$(plutil -extract 'com\.apple\.security\.files\.user-selected\.read-write' raw "$verification_dir/entitlements.plist")" == "true" ]] \
    || { echo "M4C verification failed: user-selected file entitlement missing" >&2; exit 1; }

if [[ "$mode" == "signed" ]]; then
    rg -q '^Authority=Developer ID Application:' "$verification_dir/codesign-details.txt" \
        || { echo "M4C verification failed: Developer ID authority missing" >&2; exit 1; }
    spctl --assess --type execute --verbose=4 "$app_path" \
        > "$verification_dir/gatekeeper.txt" 2>&1
else
    rg -q '^Signature=adhoc$' "$verification_dir/codesign-details.txt" \
        || { echo "M4C verification failed: expected ad-hoc signature" >&2; exit 1; }
    set +e
    spctl --assess --type execute --verbose=4 "$app_path" \
        > "$verification_dir/gatekeeper.txt" 2>&1
    gatekeeper_status=$?
    set -e
    printf '%s\n' "$gatekeeper_status" > "$verification_dir/gatekeeper-exit-status.txt"
fi

cat > "$verification_dir/bundle-metadata.txt" <<EOF
Bundle ID: $bundle_id
Display name: $display_name
Version: $version
Build: $build
Minimum macOS: $minimum_system
Signature mode: $mode
EOF

echo "M4C app verification passed: $app_path ($version/$build, $mode)"

#!/bin/bash
set -euo pipefail

mode="${1:-dry-run}"
if [[ "$mode" != "dry-run" && "$mode" != "signed" ]]; then
    echo "usage: $0 dry-run|signed" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="${M4_RESULT_ROOT:-$repo_root/.m4-results}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
version="${M4C_VERSION:-0.1.0}"
build="${M4C_BUILD:-1}"
result_dir="$result_root/$timestamp-m4c-$mode-v$version-$build"
archive_path="$result_dir/WaterDropTodo.xcarchive"
export_path="$result_dir/export"
staging_path="$result_dir/dmg-root"
mount_path="$result_dir/dmg-mount"
dmg_path="$result_dir/WaterDropTodo-$version-$build.dmg"
verification_path="$result_dir/verification"
app_name="水滴待办.app"
mounted=false

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "M4C release failed: M4C_VERSION must use x.y.z" >&2; exit 2; }
[[ "$build" =~ ^[1-9][0-9]*$ ]] \
    || { echo "M4C release failed: M4C_BUILD must be a positive integer" >&2; exit 2; }

cleanup() {
    if [[ "$mounted" == "true" ]]; then
        hdiutil detach "$mount_path" -quiet 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

mkdir -p "$result_dir" "$export_path" "$staging_path" "$mount_path" "$verification_path"
cd "$repo_root"

worktree_state="clean"
if ! git diff --quiet \
    || ! git diff --cached --quiet \
    || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    worktree_state="dirty"
fi
if [[ "$mode" == "signed" && "$worktree_state" != "clean" ]]; then
    echo "M4C release failed: signed releases require a clean worktree" >&2
    exit 1
fi

if [[ "$mode" == "signed" ]]; then
    : "${M4C_DEVELOPER_IDENTITY:?set M4C_DEVELOPER_IDENTITY to the Developer ID Application identity}"
    : "${M4C_TEAM_ID:?set M4C_TEAM_ID to the Apple Developer Team ID}"
    : "${M4C_NOTARY_PROFILE:?set M4C_NOTARY_PROFILE to a notarytool keychain profile}"
fi

"$repo_root/scripts/check_release_hygiene.sh" | tee "$result_dir/hygiene.log"

archive_settings=(
    -project WaterDropTodo.xcodeproj
    -scheme WaterDropTodo
    -configuration Release
    -destination 'generic/platform=macOS'
    -archivePath "$archive_path"
    MARKETING_VERSION="$version"
    CURRENT_PROJECT_VERSION="$build"
    SKIP_INSTALL=NO
)

if [[ "$mode" == "signed" ]]; then
    xcodebuild -quiet archive "${archive_settings[@]}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$M4C_DEVELOPER_IDENTITY" \
        DEVELOPMENT_TEAM="$M4C_TEAM_ID"

    export_options="$result_dir/ExportOptions.plist"
    plutil -create xml1 "$export_options"
    plutil -insert method -string developer-id "$export_options"
    plutil -insert signingStyle -string manual "$export_options"
    plutil -insert signingCertificate -string "$M4C_DEVELOPER_IDENTITY" "$export_options"
    plutil -insert teamID -string "$M4C_TEAM_ID" "$export_options"
    plutil -insert stripSwiftSymbols -bool true "$export_options"
    xcodebuild -quiet -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options"
    source_app="$export_path/WaterDropTodo.app"
else
    xcodebuild -quiet archive "${archive_settings[@]}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY=- \
        AD_HOC_CODE_SIGNING_ALLOWED=YES \
        DEVELOPMENT_TEAM=
    source_app="$archive_path/Products/Applications/WaterDropTodo.app"
fi

[[ -d "$source_app" ]] \
    || { echo "M4C release failed: archived app not found" >&2; exit 1; }

ditto "$source_app" "$staging_path/$app_name"

ln -s /Applications "$staging_path/Applications"
cp "$repo_root/README.md" "$staging_path/README.md"

M4C_VERIFY_OUTPUT_DIR="$verification_path/staged-app" \
    "$repo_root/scripts/m4c_verify_app.sh" \
    "$staging_path/$app_name" \
    "$([[ "$mode" == "signed" ]] && echo signed || echo local)" \
    "$version" \
    "$build"

hdiutil create -quiet \
    -volname "水滴待办 $version" \
    -srcfolder "$staging_path" \
    -format UDZO \
    "$dmg_path"
hdiutil verify "$dmg_path" > "$result_dir/hdiutil-verify.txt"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_path" "$dmg_path"
mounted=true

[[ -d "$mount_path/$app_name" ]] \
    || { echo "M4C release failed: app missing from mounted DMG" >&2; exit 1; }
[[ -L "$mount_path/Applications" ]] \
    || { echo "M4C release failed: /Applications shortcut missing from DMG" >&2; exit 1; }
M4C_VERIFY_OUTPUT_DIR="$verification_path/mounted-app" \
    "$repo_root/scripts/m4c_verify_app.sh" \
    "$mount_path/$app_name" \
    "$([[ "$mode" == "signed" ]] && echo signed || echo local)" \
    "$version" \
    "$build"

hdiutil detach "$mount_path" -quiet
mounted=false

notarization_status="not-submitted-no-credentials"
archive_classification="developer-id-app-archive"
if [[ "$mode" == "dry-run" ]]; then
    archive_classification="generic-ad-hoc-archive-no-distribution-identity"
fi
if [[ "$mode" == "signed" ]]; then
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$M4C_NOTARY_PROFILE" \
        --wait \
        --output-format json > "$result_dir/notary-result.json"
    [[ "$(jq -r '.status' "$result_dir/notary-result.json")" == "Accepted" ]] \
        || { echo "M4C release failed: notarization was not accepted" >&2; exit 1; }
    xcrun stapler staple "$dmg_path" | tee "$result_dir/stapler-staple.txt"
    xcrun stapler validate "$dmg_path" | tee "$result_dir/stapler-validate.txt"
    notarization_status="accepted-and-stapled"
fi

checksum="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "$(basename "$dmg_path")" \
    > "$dmg_path.sha256"

commit="$(git rev-parse HEAD)"
xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed 's/ $//')"
jq -n \
    --arg createdAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg mode "$mode" \
    --arg version "$version" \
    --arg build "$build" \
    --arg bundleID "com.liuliuliu.WaterDropTodo" \
    --arg commit "$commit" \
    --arg worktree "$worktree_state" \
    --arg xcode "$xcode_version" \
    --arg minimumMacOS "13.0" \
    --arg notarization "$notarization_status" \
    --arg archiveClassification "$archive_classification" \
    --arg checksum "$checksum" \
    --arg artifact "$(basename "$dmg_path")" \
    '{createdAt: $createdAt, mode: $mode, version: $version, build: $build,
      bundleID: $bundleID, commit: $commit, worktree: $worktree, xcode: $xcode,
      minimumMacOS: $minimumMacOS, notarization: $notarization,
      archiveClassification: $archiveClassification,
      sha256: $checksum, artifact: $artifact}' \
    > "$result_dir/release-manifest.json"

cat > "$result_dir/README.md" <<EOF
# 水滴待办 $version ($build) 发布产物

- 模式：$mode
- 工作区：$worktree_state
- DMG：$(basename "$dmg_path")
- SHA-256：$checksum
- 公证：$notarization_status
- Archive 分类：$archive_classification

dry-run 使用本机 ad-hoc 签名；没有分发身份时 Xcode 将其归类为 generic archive，
但仍会验证 Archive 内应用、Hardened Runtime、沙盒权限和 DMG 流程。该产物不能对外分发。
只有 signed 模式通过 Developer ID、notarytool、staple 和 Gatekeeper 校验后才是候选内测包。
EOF

echo "M4C $mode release pipeline passed: $result_dir"

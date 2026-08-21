#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="${M4_RESULT_ROOT:-$repo_root/.m4-results}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
result_dir="${M4_COMPAT_RESULT_DIR:-$result_root/$timestamp-compatibility}"

mkdir -p "$result_dir"
cd "$repo_root"

xcrun swift \
    -module-cache-path "$result_dir/ModuleCache" \
    "$repo_root/scripts/m4_display_snapshot.swift" > "$result_dir/displays.json"

model="$(sysctl -n hw.model)"
architecture="$(uname -m)"
os_version="$(sw_vers -productVersion)"
os_build="$(sw_vers -buildVersion)"
xcode_version="$(xcodebuild -version | sed -n '1p')"

jq -n \
    --arg capturedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg model "$model" \
    --arg architecture "$architecture" \
    --arg osVersion "$os_version" \
    --arg osBuild "$os_build" \
    --arg xcodeVersion "$xcode_version" \
    --slurpfile display "$result_dir/displays.json" \
    '{capturedAt: $capturedAt, model: $model, architecture: $architecture,
      osVersion: $osVersion, osBuild: $osBuild, xcodeVersion: $xcodeVersion,
      display: $display[0]}' > "$result_dir/compatibility.json"

cat > "$result_dir/compatibility.md" <<EOF
# M4B 兼容性快照

- 采集时间：$(date '+%Y-%m-%d %H:%M:%S %Z')
- 机型：$model
- 架构：$architecture
- macOS：$os_version ($os_build)
- Xcode：$xcode_version
- 屏幕数量：$(jq -r '.displayCount' "$result_dir/displays.json")
- 检测到刘海：$(jq -r '.hasNotch' "$result_dir/displays.json")
- 镜像：$(jq -r '.isMirrored' "$result_dir/displays.json")
- Reduce Motion：$(jq -r '.reduceMotion' "$result_dir/displays.json")

此快照只证明当前设备和当前屏幕配置；其他 macOS 版本、屏幕尺寸、外接屏与镜像组合仍需分别登记实机证据。
EOF

echo "M4B compatibility snapshot saved: $result_dir"

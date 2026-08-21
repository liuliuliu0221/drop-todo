#!/bin/bash
set -euo pipefail

mode="${1:-smoke}"
if [[ "$mode" != "smoke" && "$mode" != "full" ]]; then
    echo "usage: $0 smoke|full" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
result_root="${M4_RESULT_ROOT:-$repo_root/.m4-results}"
timestamp="$(date '+%Y%m%d-%H%M%S')"
result_dir="$result_root/$timestamp-performance-$mode"
derived_data="$result_dir/DerivedData"
benchmark_store_name="WaterDropTodo-M4B-$timestamp"
app_log="$result_dir/benchmark-app.log"
sample_csv="$result_dir/steady-state.csv"

if [[ "$mode" == "full" ]]; then
    steady_seconds="${M4_STEADY_SECONDS:-1800}"
    warmup_seconds="${M4_WARMUP_SECONDS:-15}"
    sample_interval="${M4_SAMPLE_INTERVAL:-5}"
    trace_duration="${M4_TRACE_DURATION:-60s}"
else
    steady_seconds="${M4_STEADY_SECONDS:-30}"
    warmup_seconds="${M4_WARMUP_SECONDS:-5}"
    sample_interval="${M4_SAMPLE_INTERVAL:-2}"
    trace_duration="${M4_TRACE_DURATION:-3s}"
fi

mkdir -p "$result_dir"
cd "$repo_root"

M4_COMPAT_RESULT_DIR="$result_dir/compatibility" \
    "$repo_root/scripts/m4_compatibility_snapshot.sh"

echo "M4B performance ${mode}: building Release app"
xcodebuild -quiet \
    -project WaterDropTodo.xcodeproj \
    -scheme WaterDropTodo \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    build

app_executable="$derived_data/Build/Products/Release/WaterDropTodo.app/Contents/MacOS/WaterDropTodo"
[[ -x "$app_executable" ]] || {
    echo "M4B performance gate failed: Release executable not found" >&2
    exit 1
}

app_pid=""
cleanup() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

start_benchmark() {
    local store_name="$1"
    local log_path="$2"

    "$app_executable" \
        --skip-device-gate \
        "--m4-benchmark-store-name=$store_name" \
        --m4-benchmark-tasks=8 > "$log_path" 2>&1 &
    app_pid=$!

    for _ in {1..75}; do
        rg -q '^M4_BENCHMARK_READY count=8$' "$log_path" && break
        kill -0 "$app_pid" 2>/dev/null || {
            echo "M4B performance gate failed: app exited during startup" >&2
            exit 1
        }
        sleep 0.2
    done
    rg -q '^M4_BENCHMARK_READY count=8$' "$log_path" || {
        echo "M4B performance gate failed: benchmark fixture was not created" >&2
        exit 1
    }
}

start_benchmark "$benchmark_store_name" "$app_log"

echo "M4B performance ${mode}: warming up for ${warmup_seconds}s"
sleep "$warmup_seconds"
printf 'elapsed_seconds,cpu_percent,rss_kb\n' > "$sample_csv"
started_at="$(date '+%s')"
next_progress=60
echo "M4B performance ${mode}: sampling steady state for ${steady_seconds}s"
while true; do
    now="$(date '+%s')"
    elapsed=$((now - started_at))
    (( elapsed >= steady_seconds )) && break
    sample="$(ps -p "$app_pid" -o %cpu= -o rss= | awk '{$1=$1; print}')"
    [[ -n "$sample" ]] || {
        echo "M4B performance gate failed: app exited during steady-state sampling" >&2
        exit 1
    }
    cpu="$(awk '{print $1}' <<< "$sample")"
    rss="$(awk '{print $2}' <<< "$sample")"
    printf '%s,%s,%s\n' "$elapsed" "$cpu" "$rss" >> "$sample_csv"
    if (( elapsed >= next_progress )); then
        echo "M4B performance ${mode}: steady-state ${elapsed}/${steady_seconds}s"
        next_progress=$((next_progress + 60))
    fi
    sleep "$sample_interval"
done

cleanup
app_pid=""

sample_count="$(awk -F, 'NR > 1 {count += 1} END {print count + 0}' "$sample_csv")"
avg_cpu="$(awk -F, 'NR > 1 {sum += $2; count += 1} END {printf "%.3f", sum / count}' "$sample_csv")"
peak_rss_kb="$(awk -F, 'NR > 1 && $3 > peak {peak = $3} END {print peak + 0}' "$sample_csv")"
first_rss_kb="$(awk -F, 'NR == 2 {print $3}' "$sample_csv")"
last_rss_kb="$(awk -F, 'END {print $3}' "$sample_csv")"
growth_rss_kb=$((last_rss_kb - first_rss_kb))
p95_cpu="$(tail -n +2 "$sample_csv" | cut -d, -f2 | sort -n | awk '{v[NR]=$1} END {i=int((NR*95+99)/100); printf "%.3f", v[i]}')"

cat > "$result_dir/summary.md" <<EOF
# M4B 性能采样（${mode}）

- 稳态时长：${steady_seconds}s（预热 ${warmup_seconds}s）
- 样本数：$sample_count
- 平均 CPU：${avg_cpu}%
- CPU P95：${p95_cpu}%
- 峰值 RSS：$((peak_rss_kb / 1024)) MB
- RSS 首尾变化：$((growth_rss_kb / 1024)) MB
- 基准任务：8 个 active，花园覆盖层保持空闲
- 能耗采样：macOS 不支持 Power Profiler，使用 Activity Monitor trace 记录替代指标
EOF

for template in "Time Profiler" "Allocations" "Leaks" "Activity Monitor"; do
    slug="$(tr '[:upper:] ' '[:lower:]-' <<< "$template")"
    trace_log="$result_dir/$slug.log"
    trace_app_log="$result_dir/$slug-app.log"
    start_benchmark "$benchmark_store_name-$slug" "$trace_app_log"
    sleep 1

    echo "M4B performance ${mode}: recording $template (${trace_duration})"
    if ! xcrun xctrace record --no-prompt \
        --template "$template" \
        --time-limit "$trace_duration" \
        --output "$result_dir/$slug.trace" \
        --attach "$app_pid" > "$trace_log" 2>&1; then
        echo "M4B performance gate failed: $template recording failed" >&2
        sed -n '1,120p' "$trace_log" >&2
        exit 1
    fi

    cleanup
    app_pid=""
    if ! xcrun xctrace export \
        --input "$result_dir/$slug.trace" \
        --toc > "$result_dir/$slug-toc.xml" 2>&1; then
        echo "M4B performance gate failed: $template trace cannot be exported" >&2
        exit 1
    fi
done

if [[ "$mode" == "full" ]]; then
    awk -v value="$avg_cpu" 'BEGIN {exit !(value <= 2.0)}' || {
        echo "M4B performance gate failed: average CPU ${avg_cpu}% > 2%" >&2
        exit 1
    }
    (( peak_rss_kb <= 153600 )) || {
        echo "M4B performance gate failed: peak RSS exceeds 150 MB" >&2
        exit 1
    }
    (( growth_rss_kb <= 10240 )) || {
        echo "M4B performance gate failed: RSS grew by more than 10 MB" >&2
        exit 1
    }
fi

echo "M4B performance $mode gate passed: $result_dir"

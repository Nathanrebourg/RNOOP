#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
plan_work="$(mktemp -d "${TMPDIR:-/tmp}/noop-weekly-plan.XXXXXX")"
trap 'rm -rf "$plan_work"' EXIT
swiftc -module-cache-path "$plan_work/cache" -O \
  "$repo_root/Packages/StrandAnalytics/Sources/StrandAnalytics/WeeklyPlan.swift" \
  "$repo_root/Tools/Oracles/WeeklyPlan/main.swift" -o "$plan_work/oracle"
"$plan_work/oracle" > "$plan_work/stdout.txt"
diff -u "$repo_root/Tools/Oracles/WeeklyPlan/stdout.txt" "$plan_work/stdout.txt"
cat "$plan_work/stdout.txt"

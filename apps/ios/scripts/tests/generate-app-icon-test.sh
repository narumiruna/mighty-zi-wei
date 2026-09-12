#!/bin/bash
set -euo pipefail

scripts_dir=$(cd "$(dirname "$0")/.." && pwd)
repository_dir=$(cd "$scripts_dir/../../.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/mighty-app-icon-test.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

export SDKROOT
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

render() {
  xcrun --sdk macosx swift \
    -module-cache-path "$work_dir/module-cache" \
    "$scripts_dir/generate-app-icon.swift" "$@"
}

render "$work_dir/first.xcassets"
render "$work_dir/second.xcassets"
icon_set="$work_dir/first.xcassets/AppIcon.appiconset"
metadata=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$icon_set/AppIcon.png")
grep -q 'pixelWidth: 1024' <<< "$metadata"
grep -q 'pixelHeight: 1024' <<< "$metadata"
grep -q 'hasAlpha: no' <<< "$metadata"

cmp "$icon_set/AppIcon.png" "$work_dir/second.xcassets/AppIcon.appiconset/AppIcon.png"
cmp "$icon_set/Contents.json" "$work_dir/second.xcassets/AppIcon.appiconset/Contents.json"
[ "$(plutil -extract images.0.filename raw -o - "$icon_set/Contents.json")" = 'AppIcon.png' ]
[ "$(plutil -extract images.0.size raw -o - "$icon_set/Contents.json")" = '1024x1024' ]
[ "$(plutil -extract images.0.idiom raw -o - "$icon_set/Contents.json")" = 'universal' ]
[ "$(plutil -extract images.0.platform raw -o - "$icon_set/Contents.json")" = 'ios' ]

assert_rejected() {
  if render "$@" > "$work_dir/error.log" 2>&1; then
    printf '錯誤：腳本接受了不合法的輸出路徑。\n' >&2
    exit 1
  fi
  grep -q '請指定 repository 外的 .xcassets 輸出路徑' "$work_dir/error.log"
}

assert_rejected
assert_rejected "$work_dir/not-a-catalog"
assert_rejected "$repository_dir/RejectedAppIcon.xcassets"
[ ! -e "$repository_dir/RejectedAppIcon.xcassets" ]
ln -s "$repository_dir" "$work_dir/repository-link"
assert_rejected "$work_dir/repository-link/RejectedAppIcon.xcassets"
[ ! -e "$repository_dir/RejectedAppIcon.xcassets" ]

printf 'App icon 驗證通過：尺寸、不透明度、可重現性、asset 設定與輸出路徑限制。\n'

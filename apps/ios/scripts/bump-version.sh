#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "用法：just bump <major|minor|patch>" >&2
    exit 2
fi

bump_type="$1"
case "$bump_type" in
    major|minor|patch) ;;
    *)
        echo "不支援的版本類型：${bump_type}（僅接受 major、minor 或 patch）" >&2
        exit 2
        ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="$(cd -- "$script_dir/.." && pwd)"
project_file="$ios_dir/project.yml"

version_count="$(grep -Ec '^[[:space:]]*MARKETING_VERSION: "[0-9]+\.[0-9]+\.[0-9]+"$' "$project_file" || true)"
if [[ "$version_count" -ne 1 ]]; then
    echo "無法從 project.yml 唯一識別目前版本。" >&2
    exit 1
fi

current_version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION: "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$project_file")"
IFS=. read -r major minor patch <<< "$current_version"

case "$bump_type" in
    major)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
    minor)
        minor=$((minor + 1))
        patch=0
        ;;
    patch)
        patch=$((patch + 1))
        ;;
esac

next_version="$major.$minor.$patch"
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "找不到 xcodegen，版本未變更。" >&2
    exit 1
fi

project_dir="$ios_dir/MightyZiWei.xcodeproj"
backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/mighty-zi-wei-version.XXXXXX")"
project_existed=false
rollback_needed=false

cleanup() {
    status=$?
    trap - EXIT

    if [[ "$rollback_needed" == true ]]; then
        set +e
        restore_failed=false
        cp -p "$backup_dir/project.yml" "$project_file" || restore_failed=true
        rm -rf "$project_dir" || restore_failed=true
        if [[ "$project_existed" == true ]]; then
            cp -Rp "$backup_dir/MightyZiWei.xcodeproj" "$project_dir" || restore_failed=true
        fi

        if [[ "$restore_failed" == true ]]; then
            echo "版本升級失敗，且無法完整還原版本檔案；備份位於 $backup_dir。" >&2
            exit "$status"
        fi
        echo "版本升級失敗；已還原 project.yml 與 Xcode 專案。" >&2
    fi

    rm -rf "$backup_dir"
    exit "$status"
}
trap cleanup EXIT

cp -p "$project_file" "$backup_dir/project.yml"
if [[ -d "$project_dir" ]]; then
    cp -Rp "$project_dir" "$backup_dir/MightyZiWei.xcodeproj"
    project_existed=true
fi
rollback_needed=true

CURRENT_VERSION="$current_version" NEXT_VERSION="$next_version" perl -pi -e \
    's/(MARKETING_VERSION: ")\Q$ENV{CURRENT_VERSION}\E(")/$1$ENV{NEXT_VERSION}$2/' \
    "$project_file"

(
    cd "$ios_dir"
    xcodegen generate
)
rollback_needed=false

echo "版本已從 $current_version 升級至 ${next_version}。"

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
CURRENT_VERSION="$current_version" NEXT_VERSION="$next_version" perl -pi -e \
    's/(MARKETING_VERSION: ")\Q$ENV{CURRENT_VERSION}\E(")/$1$ENV{NEXT_VERSION}$2/' \
    "$project_file"

(
    cd "$ios_dir"
    xcodegen generate
)

echo "版本已從 $current_version 升級至 ${next_version}。"

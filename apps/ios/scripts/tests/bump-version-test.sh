#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_script="$script_dir/../bump-version.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/mighty-zi-wei-version-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

fixture_dir="$test_dir/ios"
mkdir -p "$fixture_dir/scripts" "$fixture_dir/MightyZiWei.xcodeproj" "$test_dir/bin" "$test_dir/tmp"
cp "$source_script" "$fixture_dir/scripts/bump-version.sh"
chmod +x "$fixture_dir/scripts/bump-version.sh"

cat > "$fixture_dir/project.yml" <<'YAML'
settings:
  base:
    MARKETING_VERSION: "1.1.0"
YAML
printf '原始 Xcode 專案\n' > "$fixture_dir/MightyZiWei.xcodeproj/project.pbxproj"

cat > "$test_dir/bin/xcodegen" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

grep -q 'MARKETING_VERSION: "1.1.1"' project.yml
printf '未完成的 Xcode 專案\n' > MightyZiWei.xcodeproj/project.pbxproj
exit 42
BASH
chmod +x "$test_dir/bin/xcodegen"

set +e
PATH="$test_dir/bin:$PATH" TMPDIR="$test_dir/tmp" \
    "$fixture_dir/scripts/bump-version.sh" patch \
    > "$test_dir/stdout" 2> "$test_dir/stderr"
status=$?
set -e

if [[ "$status" -ne 42 ]]; then
    echo "預期 xcodegen 失敗狀態為 42，實際為 $status。" >&2
    exit 1
fi
if ! grep -q 'MARKETING_VERSION: "1.1.0"' "$fixture_dir/project.yml"; then
    echo "xcodegen 失敗後未還原 project.yml。" >&2
    exit 1
fi
if [[ "$(cat "$fixture_dir/MightyZiWei.xcodeproj/project.pbxproj")" != "原始 Xcode 專案" ]]; then
    echo "xcodegen 失敗後未還原 Xcode 專案。" >&2
    exit 1
fi
if ! grep -q '已還原 project.yml 與 Xcode 專案' "$test_dir/stderr"; then
    echo "xcodegen 失敗後未回報還原結果。" >&2
    exit 1
fi
if find "$test_dir/tmp" -mindepth 1 -print -quit | grep -q .; then
    echo "版本還原後仍殘留暫存備份。" >&2
    exit 1
fi

set +e
PATH="/usr/bin:/bin" TMPDIR="$test_dir/tmp" \
    "$fixture_dir/scripts/bump-version.sh" patch \
    > "$test_dir/missing-stdout" 2> "$test_dir/missing-stderr"
missing_status=$?
set -e

if [[ "$missing_status" -eq 0 ]]; then
    echo "找不到 xcodegen 時版本升級不應成功。" >&2
    exit 1
fi
if ! grep -q 'MARKETING_VERSION: "1.1.0"' "$fixture_dir/project.yml"; then
    echo "找不到 xcodegen 時不應修改 project.yml。" >&2
    exit 1
fi
if ! grep -q '找不到 xcodegen，版本未變更' "$test_dir/missing-stderr"; then
    echo "找不到 xcodegen 時未回報版本保持不變。" >&2
    exit 1
fi

echo "版本升級失敗還原測試通過。"

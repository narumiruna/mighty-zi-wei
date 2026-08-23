set shell := ["bash", "-euo", "pipefail", "-c"]

xcode_dev_dir := env_var_or_default("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
project := "MightyZiWei.xcodeproj"
scheme := "MightyZiWei"
simulator := env_var_or_default("SIMULATOR", "iPhone 17 Pro")
archive_path := "/tmp/MightyZiWei.xcarchive"
upload_path := "/tmp/MightyZiWei-upload"
export_options := "Configuration/TestFlightExternalExportOptions.plist"

[default]
list:
    @just --list

# 依 project.yml 產生 Xcode 專案
generate:
    xcodegen generate

# 產生並開啟 Xcode 專案
open: generate
    open {{project}}

# 建置 iOS 模擬器版本
build: generate
    DEVELOPER_DIR={{xcode_dev_dir}} xcodebuild build \
        -project {{project}} \
        -scheme {{scheme}} \
        -destination 'generic/platform=iOS Simulator' \
        CODE_SIGNING_ALLOWED=NO

# 執行單元測試與 UI 測試
test: generate
    DEVELOPER_DIR={{xcode_dev_dir}} xcodebuild test \
        -project {{project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        CODE_SIGNING_ALLOWED=NO

# 建立 TestFlight Release archive
archive: generate
    rm -rf {{archive_path}}
    DEVELOPER_DIR={{xcode_dev_dir}} xcodebuild archive \
        -project {{project}} \
        -scheme {{scheme}} \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -archivePath {{archive_path}} \
        -allowProvisioningUpdates

# 上傳可供外部測試的 TestFlight 建置
upload: archive
    rm -rf {{upload_path}}
    DEVELOPER_DIR={{xcode_dev_dir}} xcodebuild -exportArchive \
        -archivePath {{archive_path}} \
        -exportPath {{upload_path}} \
        -exportOptionsPlist {{export_options}} \
        -allowProvisioningUpdates

# 清除本機 TestFlight 產物
clean:
    rm -rf {{archive_path}} {{upload_path}}

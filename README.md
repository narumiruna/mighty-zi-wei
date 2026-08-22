# 很牛的紫微斗數

很牛的紫微斗數是一款 iPhone 原生紫微斗數 App。

第一版以台灣傳統三合派為主、中州派為輔，提供 deterministic 排盤、十二宮閱讀、基本解讀、裝置端 AI 整理與本機儲存。

## MVP 功能

- 輸入公曆出生日期、當地民用時間與 IANA 時區。
- 依 `taiwan-traditional-sanhe` v1 計算命宮、身宮、十二宮干支、五行局與 MVP 星曜。
- 以極簡 SwiftUI 命盤查看十二宮與宮位詳情。
- 顯示附有已驗證依據的五類基本解讀。
- Apple Foundation Models 可用時，在裝置端整理解讀文字。
- Apple Intelligence 不可用、生成失敗或驗證失敗時，自動使用完整基本解讀。
- 使用 SwiftData 儲存、重新命名與刪除命盤。
- 不需要帳號、server、訂閱、API key 或 token。

## 技術需求

- Xcode 26 或更新版本。
- iOS 26 SDK。
- XcodeGen 2.46 或相容版本。

## 產生專案

```sh
brew install xcodegen
xcodegen generate
open MightyZiWei.xcodeproj
```

`project.yml` 是 Xcode project 的 source of truth。

## 建置與測試

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
-project MightyZiWei.xcodeproj \
-scheme MightyZiWei \
-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
CODE_SIGNING_ALLOWED=NO
```

## 架構

```mermaid
flowchart TD
    Input["出生資料"]
    Core["ZiWeiCore"]
    Chart["ZiWeiChart"]
    Facts["ChartFacts"]
    Seeds["InterpretationSeeds"]
    AI["Foundation Models"]
    Fallback["Deterministic renderer"]
    UI["SwiftUI"]
    Store["SwiftData"]

    Input --> Core
    Core --> Chart
    Chart --> Facts
    Facts --> Seeds
    Seeds --> AI
    Seeds --> Fallback
    AI --> UI
    Fallback --> UI
    Chart --> UI
    Chart --> Store
```

`ZiWeiCore` 不依賴 SwiftUI、UIKit、Foundation Models 或 SwiftData。

Foundation Models 不參與排盤，也不能新增 App 未提供的命理含義。

## 隱私

App 不會將出生資料、命盤、prompt 或解讀傳送到開發者控制的伺服器。

詳細內容請參閱 `Documentation/PRIVACY.md`。

## 驗證截圖

| 首頁 | 命盤 | 解讀 |
| --- | --- | --- |
| ![首頁](Documentation/Screenshots/home.png) | ![十二宮命盤](Documentation/Screenshots/chart.png) | ![基本解讀](Documentation/Screenshots/interpretation.png) |

Dark Mode 與最大 Dynamic Type 的驗證截圖也保存在 `Documentation/Screenshots/`。

## 規則狀態

完整規則、來源與流派差異記錄於 `RULESET.md`。

正式發布前仍須完成文件列出的三合派專家審查與獨立 golden chart 人工核對。

## 授權

本專案依 repository 內的 `LICENSE` 提供。

# 命盤 AI 流程改版接續事項

## 目前狀態

目前工作分支是 `narumi/feat/ai-flow-redesign`。
可執行計畫位於 `docs/plans/2026-08-27_ai-flow-redesign-plan.md`，狀態仍是 `IN PROGRESS`。
本次已完成主要介面、狀態管理、SwiftData 保存、相容解碼、測試與文件改版，但尚未完成最終驗證與計畫結案。
`.openexecutive/` 是本工作範圍外的未追蹤內容，不得修改、刪除或加入提交。

## 已有驗證證據

- 最終小幅修改前的完整單元測試曾執行 168 項並全數通過。
- 加入 malformed JSON regression test、preview 焦點恢復與 warning 修正後，`MightyZiWeiTests` 最終執行 169 項並全數通過，exit code 是 0，沒有 compiler warning。
- 命盤助理主要流程、多輪問答、傳送預覽取消、跨分頁請求、unsupported、失敗與停止、解讀成功與 fallback、草稿切換、保存更新、空狀態、最大 Dynamic Type、Dark Mode 與語音 focused UI tests 都曾分別通過。
- 使用 `.env` 的 synthetic chart 非 CI smoke test 已完成真實連線、AI 整理解讀與兩輪問答，過程沒有輸出或保存 secret，暫存 harness 已刪除。
- `xcodegen generate` 已成功，`.pbxproj` 差異只有新增兩個 Swift source 的必要 reference 與 Sources entries。
- Debug generic simulator build 與 Release generic iOS build曾通過且沒有 warning，但需要在最後修改後重跑。

## 已知失敗

完整 `just test` 最近一次 exit code 是 65。
該次執行的 168 個單元測試通過，但 UI suite 有三項失敗：`test只有草稿時切換命盤會先確認且取消不清除內容`、`test回答失敗與停止都保留問題並提供恢復路徑`、`test實用功能的出生檢查個資確認傳送預覽與本機對話保存`。
第一項與第三項失敗在共用 `scrollToElement` 的 hittable assertion，第二項沒有在期限內找到 cancelled state。
這三項先前單獨執行曾通過，因此需要先重跑個別測試，再判斷是 suite 隔離、模擬器狀態或真實 regression。
該次結果位於 `/Users/narumi.chen/Library/Developer/Xcode/DerivedData/MightyZiWei-fnilirugnqjibiftlfhkdtndgqhz/Logs/Test/Test-MightyZiWei-2026.08.27_17-10-16-+0800.xcresult`。
本機 `.xcresult` 不得加入 repository。

## 剩餘工作

- [ ] 個別重跑三項曾在完整 suite 失敗的 UI tests，保存各自的 exit code、測試數量與結果。
- [ ] 重跑最大 Dynamic Type、強制 Dark Mode、Increase Contrast、語音及傳送預覽返回修改 UI tests，確認 preview 返回後 composer 恢復焦點，確認送出後不會重新叫出鍵盤。
- [ ] 使用 VoiceOver 線性走查目前命盤、能力邊界、傳送預覽、loading、success、unsupported、cancelled、error、保存狀態、追問與切換 dialog。
- [ ] 使用 simulator hardware keyboard 與 Full Keyboard Access 或 Switch Control 走查焦點順序、返回、取消、確認與 composer 操作。
- [ ] 在 Light、Dark 與 Increase Contrast 下檢查 badge、secondary text、disabled reason、error 與 selected state，確認狀態不只靠顏色表達。
- [ ] 以 mock provider 逐項走查無命盤、第一題、後續追問、unsupported、timeout、validation failure、停止、tab 切換、保存、再次保存、切換命盤及清除。
- [ ] 重跑完整 `just test`，只有 exit code 0 且完整 unit 與 UI suite 零失敗才可勾選計畫項目。
- [ ] 重跑 Debug generic simulator build 與 Release generic iOS build，確認 Swift 6 Strict Concurrency、iOS 26 deployment target 與 signing-independent build 沒有 warning 或 error。
- [ ] 執行最終 `git diff --check`、逐檔 diff、binary extension 搜尋與 secret pattern 搜尋，並確認沒有 `.xcresult`、圖片、音訊、API response、暫存 harness或 generated noise。
- [ ] 將每項通過證據同步回計畫，逐項完成 Completion Checklist，並確認沒有未勾選項目。
- [ ] 只有所有必要 checkbox 都通過後，才把計畫狀態改為 `DONE` 並依原指示刪除完成的 plan file。

## 建議命令

```bash
cd apps/ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -quiet \
  -project MightyZiWei.xcodeproj \
  -scheme MightyZiWei \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MightyZiWeiTests
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer SIMULATOR='iPhone 17e' just test
```

## 完成原則

不得隱藏完整測試目前失敗的事實。
不得把 `.env`、API key、真實 API response、本機測試產物或任何圖片加入提交。
不得修改 API key、endpoint 或 model 的設定設計。
只有計畫全部驗證通過後才能宣告 `DONE`。

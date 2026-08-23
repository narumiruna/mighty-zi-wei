# iztro 實作參考指南

## 定位

Repository 根目錄的 `references/iztro/` 是固定修訂版本的外部開源實作參考。

它適合用來尋找規則表、排盤演算法、測試案例與資料結構的比較線索。

它不是古籍來源、目前產品規格、已驗證命盤事實或解讀文案來源。

產品排盤仍以根目錄的 `RULESET.md` 為唯一 canonical specification。

子模組採 MIT License，引用或改作程式碼時必須保留適用的授權聲明。

## 查找順序

1. 先用 `git submodule status references/iztro` 記錄目前固定的 commit。
2. 四化表與天干資料優先查看 `references/iztro/src/data/heavenlyStems.ts`。
3. 星曜屬性與亮度表優先查看 `references/iztro/src/data/stars.ts`。
4. 命身宮、十二宮與五行局規則優先查看 `references/iztro/src/astro/palace.ts`。
5. 主星與輔煞星安置演算法優先查看 `references/iztro/src/star/`。
6. 日期邊界、流派設定與排盤組裝優先查看 `references/iztro/src/astro/astro.ts`。
7. 預期行為與邊界案例優先查看 `references/iztro/src/__tests__/`。
8. 只讀取與當前問題直接相關的檔案與測試，不要一次載入整個子模組。

## 比對要求

比對時應記錄輸入條件、iztro commit、檔案路徑、符號名稱、產品規則與差異結果。

應優先檢查閏月、晚子時換日、年界、庚干四化、流派設定與廟旺利陷等高差異項目。

iztro 的預設值、註解、測試與輸出只能證明該版本的實作行為，不能單獨證明傳統規則正確。

iztro 與 `RULESET.md` 一致時，可把它列為交叉比對證據，但不能取代產品 regression fixture。

iztro 與 `RULESET.md` 不一致時，應記錄差異並停止移植，不得自行選擇其一。

任何要採納的外部規則仍須完成來源查證、專家核對、ruleset version 更新與 regression fixture。

不得直接引用 iztro 的 AI 解讀、網站文案或未追溯來源的結論作為本 Skill 的解讀依據。

## 更新子模組

更新前應先閱讀上游變更紀錄並確認更新範圍。

更新後應重新比對上述高差異項目，並執行本 repository 的排盤 regression tests。

提交更新時應在變更說明中記錄舊 commit、新 commit 與確認過的規則差異。

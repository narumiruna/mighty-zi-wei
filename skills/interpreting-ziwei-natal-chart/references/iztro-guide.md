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
8. 結構化宮位查詢優先查看 `references/iztro/src/astro/analyzer.ts`、`FunctionalPalace.ts` 與 `FunctionalSurpalaces.ts`。
9. 正體中文詞彙可查看 `references/iztro/src/i18n/locales/zh-TW/`，但每個詞仍須人工檢查。
10. 只讀取與當前問題直接相關的檔案與測試，不要一次載入整個子模組。

## 可借鏡的分析方法

可借鏡 `target`、`opposite`、`wealth` 與 `career` 的分欄方式，將本宮、對宮與兩個三合宮分開記錄。

實際寫入本 Skill 時應使用產品 stable palace ID，並保留每個三合宮的實際宮名。

可借鏡 `have()`、`haveOneOf()` 與 `notHave()` 的量詞區分，避免把部分命中誤寫成完整組合。

可借鏡星曜、宮位、四化與三方四正分層查詢的方式，但只能查詢產品已提供的 `ChartFact`。

可借鏡 `isEmpty()` 將空宮限制為沒有主星的做法，但空宮結論仍須由產品 facts 完整證明。

可借鏡 `toJSON()` 的純資料快照概念，讓比較資料不混入方法、執行狀態或未揭露設定。

## 比對要求

比對時應記錄輸入條件、iztro commit、檔案路徑、符號名稱、產品規則與差異結果。

應優先檢查閏月、晚子時換日、年界、庚干四化、流派設定與廟旺利陷等高差異項目。

iztro 的預設值、註解、測試與輸出只能證明該版本的實作行為，不能單獨證明傳統規則正確。

iztro 與 `RULESET.md` 一致時，可把它列為交叉比對證據，但不能取代產品 regression fixture。

iztro 與 `RULESET.md` 不一致時，應記錄差異並停止移植，不得自行選擇其一。

任何要採納的外部規則仍須完成來源查證、專家核對、ruleset version 更新與 regression fixture。

不得直接引用 iztro 的 AI 解讀、網站文案或未追溯來源的結論作為本 Skill 的解讀依據。

## 已確認的規則差異

iztro 的 `fixLeap=true` 以農曆十五日為界分割閏月，與產品將整個閏月作下月不同。

上述閏月行為可在 `references/iztro/src/utils/index.ts` 的 `fixLunarMonthIndex()` 查核。

iztro 的 `dayDivide` 預設為 `forward`，會把晚子時推至次日，與產品採 local civil midnight 不同。

上述晚子時設定可在 `references/iztro/src/astro/astro.ts` 與 `references/iztro/src/data/types/astro.ts` 查核。

iztro 可設定 `default` 與 `zhongzhou` 安星方法，產品目前只採 `taiwan-traditional-sanhe` v1。

iztro 提供廟旺利陷、運限、飛化、自化與夾宮分析，這些功能目前不在產品支援範圍內。

iztro 的正體中文資料仍可能殘留非正體字形或非台灣慣用詞，不得直接複製到產品或 Skill。

iztro 的原始碼註解、型別說明與實際預設值可能不一致，必須以程式、型別、測試與執行結果交叉查核。

## 交叉比對案例

優先選擇非閏月、非晚子時、非年界且不涉及歷史時區變化的本命盤案例。

比對時固定使用 iztro 的 `default` 安星方法，並排除廟旺利陷、運限、飛化、自化與未支援星曜。

iztro 不接受 IANA 時區作為排盤輸入，因此不能用來驗證產品的時區、夏令時間或不存在當地時間處理。

上游測試輸入可以成為產品 regression fixture 的候選，但預期結果必須再由 `RULESET.md` 與獨立來源核對。

每筆比較紀錄至少包含輸入、產品 ruleset、iztro commit、iztro 設定、比較欄位、相同項目、差異項目與處置。

## 禁止直接採用的內容

不得採用廟旺利陷、運限、自化、飛化、宮干四化、夾宮、中州派地盤或中州派人盤作為目前解讀依據。

不得採用產品未列入 `Star.allCases` 的其他星曜建立命盤 fact 或解讀訊號。

不得把 iztro 的性別參數或順逆行規則延伸成性別人格、職業或關係結論。

不得把上游測試通過描述為產品規則已獲古籍、專家或實證確認。

## 更新子模組

更新前應先閱讀上游變更紀錄並確認更新範圍。

更新後應重新比對上述高差異項目，並執行本 repository 的排盤 regression tests。

提交更新時應在變更說明中記錄舊 commit、新 commit 與確認過的規則差異。

# 產品整合邊界

本檔案記錄目前 iOS interpretation model 與 validator 尚未實作的 Skill 契約。

## 目前產品能力

`InterpretationSection` 目前只有 `evidenceFactIDs`，沒有 seed IDs。

`InterpretationValidator` 目前會檢查 fact ID 存在、分類、長度與一小組禁止片語。

它不會驗證 section content 是否由某個 approved seed meaning 支持。

它也不能證明 evidence fact 與 meaning 在語意上相符。

因此「產品 validator 通過」不等於「本 Skill 的 seed 與 fact 雙重證據契約通過」。

## 本 Skill 的額外限制

Agent 必須直接讀取當次 payload 中的 seeds，並依 [InterpretationSeed 支援矩陣](seed-support-matrix.md) 驗證來源與契約。

每個個人化子句都要列 seed ID、原始 meaning 與該 seed 的全部 evidence fact IDs。

產品回應若沒有 seed ID，不得自動視為符合本 Skill。

只有 fact ID 的產品 section 只能證明盤面位置，不能替任意心理含義背書。

未支援的輔煞、身宮、四化、三方四正與祿馬維持 facts-only。

## 安全字詞限制

產品現行禁止片語不是完整的正體中文確定性或高風險語意分類器。

「必然」、「遲早」、「不會長壽」及其他同義句可能不在產品黑名單內。

本 Skill 不依賴該黑名單核准 meaning。

本 Skill 先限制輸出只能使用 approved seed，再執行非宿命語氣與高風險主題檢查。

## 可安全宣稱的範圍

可以宣稱本 Skill 的知識、來源、approved seed 支援狀態與 Agent 工作流程已完成治理。

不得宣稱 iOS `InterpretationValidator` 已完整實作本 Skill 的 seed 契約。

不得把 iOS 測試通過描述為模型輸出語意已獲完整驗證。

## 未來產品工作

以下是產品整合工作，不在本 Skill 知識補充任務內。

- 在結構化輸出加入 seed IDs。
- 驗證 seed ID 存在、原始 meaning、category 與完整 evidence。
- 讓每個 section 只能使用允許的 deterministic 組合。
- 建立確定性與高風險主題的正體中文測試矩陣。
- 區分古籍引用、一般知識與個人命盤解讀的 validator 路徑。

上述工作未完成前，Agent 必須執行本檔案的額外限制，不能把責任交給產品 validator。

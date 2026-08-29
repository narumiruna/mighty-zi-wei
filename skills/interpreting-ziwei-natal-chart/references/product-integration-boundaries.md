# 產品整合邊界

本檔案記錄目前 iOS interpretation model 與 validator 已實作及尚未實作的 Skill 契約。

## 目前產品能力

`InterpretationSection` 同時保存 `evidenceSeedIDs` 與 `evidenceFactIDs`。

命盤助理的回答與保存對話也會保存兩種 evidence IDs；舊版保存對話缺少 seed IDs 時仍可讀取，但不得回溯宣稱已通過新版 seed 驗證。

`InterpretationValidator` 會檢查下列項目：

- 五個分類完整且不重複。
- section content 非空白。
- seed ID 存在且不重複。
- seed category 與 section category 相同。
- seed 的 evidence 非空、不重複且全部存在於當次 facts。
- section 的 fact IDs 依 seed IDs 順序完整展開、去除重複後完全一致。
- 一小組禁止片語。

`ConversationAnswerValidator` 對可回答內容執行相同的 seed 與 fact 完整對應檢查。

無法回答時，seed 與 fact IDs 都必須為空，且安全檢查通過後會保留模型提供的具體替代提問方向。

本機基本解讀直接使用 deterministic seeds 產生內容，優先顯示非 baseline 線索，並把 App 產生的盤面顯示文字、核准 meaning 與生活核對問題分層呈現。

AI 命盤解讀與問答的 strict JSON Schema 都要求 `evidenceSeedIDs` 與 `evidenceFactIDs`。

## 尚未完成的語意保證

validator 可以證明回應引用哪些 approved seeds，以及引用的 facts 是否完整對應。

validator 仍不能證明模型產生的每一個子句都只重述所引用 seed 的 meaning。

validator 也不能證明兩個 seed 之間由模型描述的情境差異、因果或衝突關係在命理上成立。

因此「產品 validator 通過」只能表示格式、安全字詞及 seed-fact 引用契約通過，不能宣稱模型文字已完成逐句語意證明。

Agent 提供個人命盤解讀時，仍須直接讀取當次 payload 中的 seeds，並依 [InterpretationSeed 支援矩陣](seed-support-matrix.md) 逐句檢查。

## 安全字詞限制

產品現行禁止片語不是完整的正體中文確定性或高風險語意分類器。

「必然」、「遲早」、「不會長壽」及其他同義句可能不在產品黑名單內。

本 Skill 不依賴該黑名單核准 meaning。

本 Skill 先限制輸出只能使用 approved seed，再執行非宿命語氣與高風險主題檢查。

## 可安全宣稱的範圍

可以宣稱產品已驗證 section 或回答引用的 seed 存在、分類正確，而且 fact evidence 完整對應。

可以宣稱本機 renderer 只使用 App 提供的 deterministic seeds 與 facts。

不得宣稱產品已自動證明 AI 每個子句與 seed meaning 完全相符。

不得把 iOS 測試通過描述為模型實際輸出已通過正體中文人工品質審查。

## 後續產品工作

- 建立可逐句對應 seed ID 的結構化內容，而不是只在 section 層級引用。
- 讓 AI 只能選擇 deterministic 內容片段與核准的組合方式。
- 建立確定性與高風險主題的正體中文測試矩陣。
- 以代表性命盤執行人工可讀性、具體度與辨識度評測。
- 區分古籍引用、一般知識與個人命盤解讀的 validator 路徑。

上述工作未完成前，Agent 必須執行本檔案的額外限制，不能把逐句語意核對責任交給產品 validator。

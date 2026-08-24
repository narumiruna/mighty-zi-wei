---
name: interpreting-ziwei-natal-chart
description: 研究、核對或解讀紫微斗數本命盤時使用，包含三合派判讀、命身十二宮、十四主星、生年四化、三方四正、古籍來源查證、ChartFact 證據與台灣正體中文解讀文案。
---

# 紫微斗數本命盤解讀

以 `taiwan-traditional-sanhe` ruleset 為主；中州派目前只提供反宿命編輯方向與待核對差異，不提供未具頁碼證據的技術規則；產出有來源、有盤面依據且不宿命化的本命盤解讀。

## 工作流程

1. 先分清楚輸入是已驗證命盤事實、一般知識問題，還是待查證的古籍說法。
2. 命盤解讀只使用已驗證的 `ChartFact` 與核准的 `InterpretationSeed`，不得從對話、姓名或主觀敘述創造命盤事實。
3. 已有完整公曆當地日期、當地時間與 IANA 時區，但尚無命盤事實時，將腳本路徑解析至本 Skill 目錄後執行 `uv run python <Skill 目錄>/scripts/generate_chart_facts.py --date YYYY-MM-DD --time HH:MM --timezone Asia/Taipei`，只採用成功輸出的 facts 與 seeds。
4. 缺少日期、時間或時區，或腳本驗證失敗時，列出缺少資料並停止該項判斷，不得手動補星。
5. 解讀前讀取 [判讀原則](references/interpretation-principles.md)。
6. 需要星曜、宮位、身宮、四化或三方四正的安全現代語句時讀取 [本命盤現代功能語句](references/modern-functional-language.md)，並遵守其中的權威層級。
7. 提供個人命盤解讀前讀取 [InterpretationSeed 支援矩陣](references/seed-support-matrix.md)，只解讀目前有 approved seed 的項目。
8. 透過 iOS interpretation model 或 validator 工作時讀取 [產品整合邊界](references/product-integration-boundaries.md)，不得把只有 fact IDs 的產品回應視為已通過本 Skill 的 seed 契約。
9. 需要核對原文時依 [來源指南](references/source-guide.md) 只讀取相關章節。
10. 需要評估外部主張、作者、版本或中州派書目時讀取 [外部來源證據帳](references/source-evidence.md)。
11. 遇到流派差異、規則衝突或產品未支援項目時讀取 [規則邊界與差異](references/canonical-boundaries.md)。
12. 需要比較外部排盤資料或實作時讀取 [iztro 實作參考指南](references/iztro-guide.md)，不得把比較結果直接升格為產品規則。
13. 依命宮、實際存在的十四主星 seeds 與 baseline seeds 分析；身宮、輔煞、四化、三方四正及其他宮位若沒有 approved seed，只列 facts 與不支援限制。
14. 先記錄盤面事實，再列使用的 seed ID 與原始 meaning，最後才提出不超出 meaning 的綜合解讀。
15. 每個個人化解讀子句至少引用一個實際存在的 seed ID 及其全部 evidence fact IDs，且每項古籍主張標示來源檔案與章節。
16. 輸出前檢查是否混入未驗證位置、未核准 meaning、單星定論、流派混用、宿命斷言或專業建議。

## 解讀方法

- 以本宮為起點，列出對宮與兩個三合宮的 facts；只有對應 approved seeds 存在時才解讀其作用。
- 不以單一星曜、單一宮位或單一四化直接定論。
- 只在每個訊號各有 approved seed 時找重複支持，再處理互相牽制的訊號。
- 把古籍的身分、性別、疾病、刑剋、貧富與壽命敘述視為歷史文本，不直接套用於現代個人。
- 將中州派說法標為補充，不得暗中覆蓋目前 canonical ruleset。
- 未經專家核對的整理只能標為待審資料，不得宣稱已驗證。

## 輸出格式

命盤解讀使用以下順序：

1. `盤面事實`：列出使用的 fact ID 與顯示文字。
2. `核准含義`：逐項列出 seed ID、原始 meaning 與全部 evidence fact IDs。
3. `判讀脈絡`：只說明 approved seeds 能共同支持的內容，不用沒有 seed 的身宮、輔煞、四化或三方四正 meaning。
4. `綜合解讀`：使用「可能」、「傾向」與「可以觀察」等可核對語氣。
5. `限制`：列出只有 facts、缺少 seed、資料不足、流派差異與尚未人工核對的部分。
6. `來源`：列出使用的參考檔案與章節。

一般知識或古籍核對不需要虛構 fact ID，但必須清楚區分原文、現代轉譯與目前規則。

## 安全限制

- 不提供確定的死亡、疾病、災禍、婚姻破裂、犯罪、懷孕或財富預測。
- 不提供醫療診斷、法律策略、投資標的或重大人生決策指示。
- 不根據性別、職業、家庭結構或社會身分重述古籍偏見。
- 不把紫微斗數解讀描述為科學證明或客觀事實。
- 涉及高風險問題時，只能提供自我反思角度並建議尋求合格專業協助。

## 完成條件

- 每個個人化解讀子句都能追溯到有效 seed ID、原始 meaning 與其全部 fact IDs。
- 每項古籍主張都能追溯到指定來源與章節。
- 已清楚標示事實、推論、綜合解讀與限制。
- 未超出本命盤、生年四化及目前 ruleset 的支援範圍。
- 一般知識回答已標示 canonical、產品現行語句、古籍原文、現代轉譯或待審狀態。

維護本 Skill 的知識內容時，依 [本命盤知識完整度量表](references/completeness-rubric.md) 執行檢查，只有腳本總分為 100 才能宣稱宣告範圍的知識覆蓋完整。

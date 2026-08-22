# 很牛的紫微斗數 / Mighty Zi Wei

## 1. Product goal

建立一款簡單、漂亮、一次買斷的純 iOS 紫微斗數 App。

核心價值：

* 正確計算紫微斗數命盤。
* 用清楚、現代的方式呈現命盤。
* 使用 Apple Foundation Models 提供自然語言解讀。
* 命盤計算與基本功能可以完全離線使用。
* 不需要帳號、server 或訂閱。

第一版不追求成為功能最完整的紫微斗數工具。

第一版應優先做到：

> 算得對、看得懂、解讀有趣、操作簡單。

---

# 2. Technical direction

使用：

* Swift
* SwiftUI
* Foundation Models
* SwiftData
* XCTest / Swift Testing

Platform baseline：

* iPhone only。
* 最低支援 iOS 26.0。
* 使用支援 Foundation Models framework 的 Xcode 與 iOS SDK。
* Foundation Models framework 可以存在，但 Apple Intelligence model 仍可能因裝置、設定、語言或下載狀態而不可用。

UI policy：

* 所有新 UI 預設使用 SwiftUI。
* UIKit 只用於 SwiftUI 無法合理處理的特殊 rendering、gesture、performance 或 platform integration。
* UIKit 必須隔離在 SwiftUI wrapper 後方。
* 不預先引入 UIKit。

Apple 官方支援透過 `UIViewRepresentable` 和 `UIViewControllerRepresentable` 將 UIKit 元件嵌入 SwiftUI，因此之後如果命盤 renderer 需要 UIKit，不需要重構整個 App。

---

# 3. Architecture

```mermaid
flowchart TD
    Input["出生資料"]
    Core["ZiWeiCore"]
    Chart["ZiWeiChart"]
    Facts["ChartFacts"]
    AI["Foundation Models"]
    Result["Interpretation"]
    UI["SwiftUI"]

    Input --> Core
    Core --> Chart
    Chart --> Facts

    Chart --> UI
    Facts --> AI
    AI --> Result
    Result --> UI
```

核心原則：

> Foundation Models 永遠不負責排命盤。

所有紫微斗數規則都必須由 deterministic Swift code 計算。

Foundation Models 只負責：

* 整理。
* 解釋。
* 摘要。
* 轉換語氣。
* 根據已計算好的命盤回答問題。

---

# 4. Project structure

```text
MightyZiWei/
├── App/
│   └── MightyZiWeiApp.swift
│
├── Features/
│   ├── Home/
│   ├── BirthInput/
│   ├── Chart/
│   ├── Interpretation/
│   ├── SavedCharts/
│   └── Settings/
│
├── Domain/
│   ├── BirthProfile.swift
│   ├── ZiWeiChart.swift
│   ├── Palace.swift
│   ├── Star.swift
│   ├── Transformation.swift
│   └── ChartFact.swift
│
├── ZiWeiCore/
│   ├── Calendar/
│   ├── Calculator/
│   ├── Rules/
│   └── Tables/
│
├── AI/
│   ├── FoundationModelInterpreter.swift
│   ├── Interpretation.swift
│   └── Prompts/
│
├── Persistence/
│   └── ChartStore.swift
│
└── Platform/
    └── UIKit/
```

`ZiWeiCore` 不得 import：

```swift
SwiftUI
UIKit
FoundationModels
SwiftData
```

它必須是一個單純、可測試的 domain engine。

---

# 5. MVP user flow

```mermaid
flowchart LR
    A["首頁"]
    B["輸入出生資料"]
    C["產生命盤"]
    D["查看十二宮"]
    E["AI 解讀"]
    F["儲存命盤"]

    A --> B
    B --> C
    C --> D
    D --> E
    D --> F
```

第一版只需要五個主要畫面：

1. 首頁。
2. 出生資料輸入。
3. 命盤。
4. 解讀。
5. 已儲存命盤。

Settings 使用 secondary screen 或 sheet，不算主要流程畫面。
自由問答不屬於第一版主要流程。

---

# 6. Birth input

MVP 輸入：

* 名稱或暱稱，可留空。
* 公曆出生日期。
* 出生地當地民用時間，精確到分鐘。
* IANA time zone identifier，例如 `Asia/Taipei`。
* 傳統排盤使用的性別選項：男或女。

性別欄位只用於傳統排盤規則，不代表使用者的性別認同。
如果 MVP 命盤規則實際不使用性別，UI 可以延後詢問，直到大限等功能需要時再加入。

MVP 不直接輸入農曆日期。
App 負責將公曆日期轉換為排盤需要的農曆日期，並正確處理閏月。

時區預設為 `Asia/Taipei`，但使用者可以為海外出生資料選擇其他時區。
歷史夏令時間依 time zone database 換算。
MVP 不使用真太陽時，也不要求經緯度。

`BirthProfile` 必須保存使用者輸入的 local date、local time、calendar identifier 與 time zone identifier，不得只保存一個失去輸入語意的 `Date`。

`taiwan-traditional-sanhe` v1 以民用日期的午夜作為換日點。
23:00 至 00:59 都屬子時，但 23:00 至 23:59 不提前改用次日日期。
不支援出生時間未知的排盤；UI 必須清楚說明原因，而不是自行假設午時或其他時間。

UX 應優先使用 Apple 標準 controls。

不要一開始建立自訂 date picker、time picker 或 navigation。

---

# 7. Zi Wei calculation engine

這是 App 最重要、也是最需要測試的部分。

MVP 採用台灣常見的傳統三合派作為基準。

Rule set identity：

```text
ruleSetID: taiwan-traditional-sanhe
ruleSetVersion: 1
```

MVP 不提供流派切換，也不宣稱這是唯一正確的排盤方式。
產品內應說明不同流派的命盤可能略有差異。

第一階段至少建立：

* 十二宮。
* 命宮。
* 身宮。
* 宮位天干地支。
* 五行局。
* 十四主星。
* 生年四化：化祿、化權、化科、化忌。
* 六吉：左輔、右弼、文昌、文曲、天魁、天鉞。
* 六煞：擎羊、陀羅、火星、鈴星、地空、地劫。
* 祿存與天馬。
* 三方四正關係。

MVP 不建立自化、飛化、流出或其他飛星派專屬規則。
MVP 不包含大限、流年、流月或流日。

之後再逐步加入：

* 大限。
* 流年。
* 流月。
* 流日。
* 更多輔星與煞星。

## Rule

在開始 Phase 1 前，必須建立獨立的 `RULESET.md`。

`RULESET.md` 至少必須逐項定義：

* 公曆轉農曆與閏月規則。
* 子時與換日規則。
* 命宮與身宮。
* 十二宮排列。
* 宮位天干地支。
* 五行局。
* 十四主星安星法。
* 生年四化表。
* MVP 所有吉曜、煞曜、祿存與天馬的安星法。
* 每條規則採用的書籍版本、頁碼或其他可追溯來源。
* 已知流派差異與 v1 的選擇。

規則來源以公開出版資料為主，網路排盤網站只能用於交叉比對，不能作為唯一來源。
正式發布前應由至少一位熟悉台灣傳統三合派的人檢查 rule set 與 golden charts。

每一個排盤規則都必須：

* deterministic。
* 可以單獨測試。
* 不依賴 LLM。
* 有可追溯來源或獨立 reference fixture。
* 綁定 `ruleSetID` 與 `ruleSetVersion`。
* 避免把大量規則散落在 UI code。

---

# 8. Golden chart tests

建立一組已知正確命盤。

例如：

```text
Fixtures/
├── chart_001.json
├── chart_002.json
├── chart_003.json
└── ...
```

每個 fixture 包含：

```text
fixture schema version
ruleSetID + ruleSetVersion
source reference
公曆 local date + local time + time zone
預期農曆日期與閏月狀態
預期命宮
預期身宮
預期五行局
預期十四主星位置
預期四化
預期 MVP 輔星與煞星位置
```

Fixture 必須涵蓋一般案例與邊界案例，包括子時前後、午夜前後、農曆新年、閏月、不同時區與歷史夏令時間。
至少一部分 fixture 必須由人工依獨立來源核對，不能全部由待測程式自行產生。

所有 calculation engine 修改都必須通過這組 golden tests。

這會是 coding agent 最重要的安全網之一。

---

# 9. Chart facts

不要直接把完整 domain object dump 給 LLM。

建立中介 representation：

```swift
struct ChartFact: Identifiable, Codable {
    let id: String
    let category: Category
    let subject: Subject
    let value: Value
    let displayText: String
}
```

`subject` 與 `value` 必須是 App 產生的 typed data。
`displayText` 只用於顯示與 prompt，不是事實的唯一資料來源。

ID 使用語義穩定的 key，不使用依輸出順序編號的 `F001`。

例如：

```text
natal.palace.life.branch: 命宮位於午宮。
natal.star.ziwei.palace: 紫微星位於命宮。
natal.star.tianfu.palace: 天府星位於財帛宮。
natal.transformation.lu.star: 武曲化祿。
```

流程變成：

```mermaid
flowchart LR
    Chart["ZiWeiChart"]
    Facts["Verified Chart Facts"]
    LLM["Foundation Model"]

    Chart --> Facts --> LLM
```

這層非常重要。

---

# 10. Foundation Models integration

使用 Apple：

```swift
import FoundationModels
```

以：

```swift
LanguageModelSession
```

作為 AI 解讀入口。

Apple 的 Foundation Models framework 提供 stateful session、structured generation、streaming 與 tool calling。

MVP 不需要 tool calling。

第一版只使用：

* Instructions。
* Prompt。
* `@Generable`。
* Streaming。

---

# 11. AI boundary

System instruction 必須明確要求：

```text
You interpret Zi Wei Dou Shu charts.

Only use facts explicitly provided by the application.

Never calculate or infer star positions, palaces, transformations,
calendar conversions, or other chart facts.

Do not invent missing chart information.

Clearly distinguish chart facts from interpretation.
```

這是整個 AI layer 最重要的 rule。

---

# 12. Structured interpretation

不要讓模型直接回傳一大段 Markdown。

使用 `@Generable`。

Apple Foundation Models 的 guided generation 可以直接產生符合 Swift structure 的結果，而不是依賴模型自行產生 JSON。

例如：

```swift
@Generable
struct ChartInterpretation {
    let summary: String
    let sections: [InterpretationSection]
}

@Generable
struct InterpretationSection {
    let title: String
    let content: String
    let evidenceFactIDs: [String]
}
```

結果可以是：

```text
整體性格

你通常具有較強的主導性，
也比較重視自己的判斷。

依據：
- natal.star.ziwei.palace 紫微位於命宮
- natal.palace.life.transformation.quan 化權位於命宮
```

這樣使用者可以知道 AI 為什麼這樣解讀。

Structured generation 只保證輸出結構，不保證內容真實。
App 必須在顯示前驗證每一個 `evidenceFactID` 都存在於本次提供的 `ChartFacts`。
Evidence 的原始文字必須由 App 根據 ID 顯示，不得採用模型自行重述的事實。
沒有有效 evidence 的 section 必須捨棄或改用 deterministic fallback。
模型產生的內容不得寫回或修改 `ChartFacts`。

---

# 13. Initial interpretation categories

MVP 固定提供：

* 命盤總覽。
* 個性。
* 工作與事業。
* 財務傾向。
* 感情與人際。

暫時不要加入：

* 健康診斷。
* 投資建議。
* 法律建議。
* 精確事件預測。
* 「今年一定會發生什麼」這類高度確定式描述。

所有解讀都必須使用可能性與自我反思語氣，不得把命理解讀描述為已證實事實。
首次使用解讀功能及 Settings / About 應說明內容僅供娛樂與自我反思，不應取代專業意見或重大人生決策。

---

# 14. Ask your chart — Post-MVP

自由問答不屬於 MVP。
完成固定分類解讀、grounding validation 與 fallback 後，才評估加入簡單問答：

```text
「我的工作性格如何？」

「我比較適合穩定還是創業？」

「我的人際關係有什麼特色？」
```

流程：

```mermaid
flowchart LR
    Question["User question"]
    Facts["Chart facts"]
    Session["LanguageModelSession"]
    Answer["Answer"]

    Question --> Session
    Facts --> Session
    Session --> Answer
```

模型仍然只能使用 `ChartFacts`。
使用者問題不能覆寫 system instructions。
App 必須拒絕超出可用 facts、健康、投資、法律或精確事件預測範圍的問題。
Foundation Models 不可用時，隱藏或停用自由問答入口；MVP 的 deterministic fallback 只保證固定解讀分類。

---

# 15. Foundation Models availability

App 不得假設 Foundation Models 一定存在。

Apple 明確要求在使用前檢查 `SystemLanguageModel.availability`，因為 Apple Intelligence 可能：

* 未啟用。
* 裝置不支援。
* 模型尚未下載完成。
* 目前語言或 locale 不適用。

Availability check 不是唯一的錯誤處理。
即使模型 initially available，App 也必須處理 session 建立失敗、generation error、內容驗證失敗與使用者取消。

因此：

```mermaid
flowchart TD
    A["查看解讀"]
    B{"Foundation Model available?"}
    C["AI interpretation"]
    D["Fallback interpretation"]

    A --> B
    B -->|Yes| C
    B -->|No| D
    C -->|Generation or validation failed| D
```

使用者主動取消 generation 時應停止工作並保留目前 UI，不應把取消視為錯誤或自動開始 fallback。

---

# 16. AI fallback

App 是付費買斷產品，因此不能讓不支援 Apple Intelligence 的使用者看到一個壞掉的核心功能。

第一版至少準備 deterministic fallback：

```text
ChartFact
+
Rule-based interpretation templates
```

例如：

```text
紫微位於命宮
→
「紫微坐命通常著重自主、管理與整體掌控。」
```

Foundation Models 可以把這些 rule-based meanings 組合成更自然的文章。

Fallback 必須完整涵蓋 MVP 的五個固定分類：命盤總覽、個性、工作與事業、財務傾向、感情與人際。
每段 fallback 也必須顯示 App 產生的 evidence facts。

如果模型不可用、generation 失敗或輸出未通過 grounding validation：

直接顯示原始 rule-based interpretation。

同一個解讀畫面應清楚標示目前顯示的是 on-device AI 整理版本或 deterministic 基本解讀，但不應把 fallback 呈現成錯誤頁。

---

# 17. Chart UI

MVP 命盤使用 SwiftUI。

十二宮可以先以：

```swift
Grid
LazyVGrid
Canvas
```

等 SwiftUI API 實作。

只有出現以下問題才考慮 UIKit：

* SwiftUI rendering 明顯有性能問題。
* zoom / pan interaction 難以可靠實作。
* layout 無法穩定控制。
* 有 UIKit-only platform capability。

不要因為「之後可能需要」而提前使用 UIKit。

---

# 18. Visual direction

設計方向：

* Minimal。
* 現代。
* 不要傳統算命網站風格。
* 不使用大量金色、紅色、龍、八卦等裝飾。
* 十二宮是主要視覺焦點。
* AI 解讀像現代閱讀 App，而不是聊天機器人。

首頁應該簡單到：

```text
很牛的紫微斗數

[ 排一張命盤 ]

最近命盤
────────
Narumi
2026/08/22
```

---

# 19. Persistence

使用 SwiftData 儲存：

```swift
SavedChart
```

包含：

* UUID。
* 名稱。
* 正規化且完整的 `BirthProfile`。
* `ruleSetID`。
* `ruleSetVersion`。
* App schema version。
* 建立時間。
* 更新時間。
* 可重新產生的 `ZiWeiChart` cache。

`BirthProfile` 是 source of truth。
`ZiWeiChart` 是 derived cache，不是不可變的歷史事實。

開啟已儲存命盤時，如果 rule set 或 schema version 不相容，App 必須重新計算命盤或執行明確 migration。
不得在規則修正後靜默顯示舊的錯誤 cache。
如果重新計算可能改變結果，應在 release notes 或命盤畫面向使用者說明。

MVP 不永久保存 AI interpretation。
AI 或 fallback interpretation 由目前命盤重新產生。

---

# 20. Privacy

MVP：

* 不建立帳號。
* 不建立 backend。
* 不使用 cloud database。
* App 不將出生資料、ChartFacts、prompt 或 interpretation 傳送到開發者控制的 server。
* AI 只使用 on-device `SystemLanguageModel`。
* 不加入第三方 analytics 或 crash reporting SDK。
* 提供刪除單張命盤與刪除所有本機資料的功能。

Apple 將 `SystemLanguageModel` 定義為 Apple Intelligence 的 on-device language model。

SwiftData 資料仍可能由 iOS 納入使用者的 encrypted device backup 或裝置轉移流程。
除非 App 明確排除 backup 並完成驗證，產品不得宣稱資料「只留在這一台 iPhone」。

建議產品文案：

> App 不會將你的出生資料或命盤傳送到我們的伺服器。

---

# 21. Monetization

商業模式：

```text
Paid App
```

不是：

```text
Free
+
In-App Purchase
```

不是：

```text
Subscription
```

第一版不放：

* 廣告。
* token 點數。
* AI credits。
* 登入。
* 會員制度。

---

# 22. MVP non-goals

第一版明確不做：

* Android。
* Web。
* 帳號。
* Cloud sync。
* 社群。
* 命盤分享圖片。
* 合盤。
* 每日運勢。
* 流日。
* Push notification。
* ChatGPT / Claude API。
* Server-side AI。
* 複雜 UIKit renderer。

---

# 23. Development phases

## Phase 0 — Project foundation

完成：

* Xcode project。
* SwiftUI App。
* Domain structure。
* Testing setup。
* CI。
* AGENTS.md。
* 基本 navigation。

完成條件：

```text
App builds
Tests pass
CI passes
```

---

## Phase 1 — ZiWeiCore

完成 deterministic engine：

```text
BirthProfile
→
ZiWeiChart
```

以及 golden tests。

這個 phase 不做 AI。

完成條件：

> 給定 fixture 出生資料，產生的命盤完全符合預期結果。

---

## Phase 2 — Chart UI

完成：

* BirthInputView。
* ChartView。
* 十二宮。
* 星曜顯示。
* 點擊宮位查看詳細資訊。

完成條件：

> 使用者可以從輸入出生資料一路看到完整基本命盤。

---

## Phase 3 — ChartFacts

建立：

```text
ZiWeiChart
→
[ChartFact]
```

並為每一個 fact 建立 stable ID。

完成條件：

> AI 不需要理解 `ZiWeiChart` implementation 就能取得所有需要資訊。

---

## Phase 4 — Foundation Models

加入：

* availability detection。
* `LanguageModelSession`。
* instructions。
* `@Generable` output。
* streaming。
* error handling。

完成條件：

> Foundation Models 可以只根據 ChartFacts 產生結構化解讀。

---

## Phase 5 — Fallback interpretation

建立 deterministic interpretation rules。

完成條件：

> 關閉 Apple Intelligence 或使用不支援的裝置時，App 仍然具有可用的命盤解讀功能。

---

## Phase 6 — Persistence

加入：

* SwiftData。
* Saved charts。
* Delete。
* Rename。

---

## Phase 7 — Polish

完成：

* Accessibility。
* Dynamic Type。
* Dark Mode。
* loading states。
* empty states。
* error states。
* animations。
* App icon。
* screenshots。

---

## Phase 8 — TestFlight

測試：

* Foundation Models available。
* Apple Intelligence disabled。
* model not ready。
* unsupported device。
* Traditional Chinese。
* multiple birth times。
* edge dates。
* different Dynamic Type sizes。
* Dark Mode。

---

# 24. Coding-agent rules

Coding agent 必須遵守：

```text
- Use SwiftUI for new UI by default.
- Treat UIKit as an exception, not an alternative default.
- Keep ZiWeiCore independent from UI and Foundation Models.
- Never use an LLM to calculate chart facts.
- Every chart calculation rule must be deterministic and tested.
- Add a regression fixture for every discovered chart calculation bug.
- Feed only verified ChartFacts into Foundation Models.
- Never let generated interpretation mutate ZiWeiChart.
- Prefer @Generable structured output over parsing generated JSON.
- Always handle SystemLanguageModel availability.
- Keep the App functional when Foundation Models is unavailable.
- Prefer Apple system controls and standard platform behavior.
- Do not introduce a backend unless a product requirement explicitly
  requires one.
```

---

# 25. MVP success criteria

第一版完成時，應該可以做到：

```text
輸入生日
    ↓
正確排命盤
    ↓
漂亮地查看十二宮
    ↓
查看 AI 解讀
    ↓
詢問自己的命盤
    ↓
儲存命盤
```

而且：

```text
No account
No server
No subscription
No API key
No token cost
```

---

# 26. Unknowns to resolve

目前不要讓 coding agent 自己猜這些事情。

需要另外明確決定：

1. 採用哪一派紫微斗數排盤規則。
2. MVP 包含哪些輔星。
3. 是否加入真太陽時。
4. 是否處理夏令時間與出生地。
5. 大限是否進 MVP。
6. Foundation Models 對繁體中文解讀品質是否達標。
7. 最低支援的 iOS 版本。
8. 不支援 Apple Intelligence 的裝置要提供多完整的 fallback 解讀。

這些應在實作相關功能前轉成明確 specification。

---

# 27. Recommended first milestone

第一個 milestone 不要做整個 App。

只做：

```text
BirthProfile
    ↓
ZiWeiCore
    ↓
ZiWeiChart
    ↓
Golden tests
```

UI 只做一個非常簡單的 debug screen。

Foundation Models 也先不要接。

第一個真正需要證明的問題是：

> 「我們能不能穩定、可測試地算出正確的紫微斗數命盤？」

等這件事完成，再開始做漂亮 UI 與 AI。

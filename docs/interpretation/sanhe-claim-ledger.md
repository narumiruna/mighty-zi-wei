# 三合派新增解讀主張證據帳

## 狀態與範圍

本帳只記錄五項功能計畫內的新解讀主張，不修改 `taiwan-traditional-sanhe` v1 排盤規則。
新增身宮、四化與三方四正含義目前全部為 `editorial-pending-review`，不進入 `InterpretationSeedBuilder` 的執行集合。
下列定位能證明 repository 有該編輯轉譯，不能證明其命理效度、古籍逐句依據或專家認證。
目前沒有接受本批範圍的人工審閱紀錄，agent 不得填寫審閱者或核准日期。

## 共用來源

- 編輯來源：`skills/interpreting-ziwei-natal-chart/references/modern-functional-language.md`。
- 結構來源：`RULESET.md` 第 7、12、13 節，以及 `Interpretation/ChartFactBuilder.swift` 的 typed facts。
- 文本邊界：`skills/interpreting-ziwei-natal-chart/references/source-evidence.md` 的 E01、E02、E08、E09。
- 古籍索引：`skills/interpreting-ziwei-natal-chart/references/source-guide.md`。
- 權威層級：現行產品 seeds 只是目前 App 契約允許使用，不等於新增編輯主張已經審閱。

本帳的 `Interpretation/` 路徑相對於 `apps/ios/MightyZiWei/`。

## 身宮六種落宮

必要條件是 `natal.palace.body.branch` 與對應宮位 branch fact 的 typed value 相同。
兩項 evidence 都必須引用，不能只靠身宮顯示文字猜測。
下列 meaning 原樣保留編輯來源「身宮」一節，不因建立本帳而升格。

| claim ID | 對應宮位 fact | 待審 meaning |
| --- | --- | --- |
| `modern.body.life` | `natal.palace.life.branch` | 身宮在命宮時，自我定位與行動方式可能較常直接成為實踐重點。 |
| `modern.body.spouse` | `natal.palace.spouse.branch` | 身宮在夫妻宮時，一對一合作、承諾與協商可能較常成為投入重點。 |
| `modern.body.wealth` | `natal.palace.wealth.branch` | 身宮在財帛宮時，資源取得、配置與維持可能較常成為投入重點。 |
| `modern.body.travel` | `natal.palace.travel.branch` | 身宮在遷移宮時，外部環境、場域轉換與對外互動可能較常成為投入重點。 |
| `modern.body.career` | `natal.palace.career.branch` | 身宮在官祿宮時，工作角色、責任承接與產出可能較常成為投入重點。 |
| `modern.body.fortune` | `natal.palace.fortune.branch` | 身宮在福德宮時，內在價值、恢復方式與心理空間可能較常成為投入重點。 |

每項正例須由 canonical 排盤產生對應同宮 facts，反例須包括缺身宮 fact、缺對應宮位 fact、branch 不同及重複 ID。
排除事件、身分、固定人格、財富或關係結果推論。
目前只顯示同宮事實，不能輸出本表個人化 meaning。

## 生年四化四類

來源定位為編輯來源「生年四化」的同名章節。
必要 evidence 是 `natal.transformation.<kind>.star`、其指定星曜的 `natal.star.<star>.palace`，以及落宮 branch fact。
四化 fact 指向的星曜必須與星曜位置 fact 完整配對，不從顯示文字擷取另一個落宮。

| claim ID | 待審 meaning 範圍 | 排除條件 |
| --- | --- | --- |
| `modern.transformation.lu` | 化星功能在落宮領域可能增加投入與回饋。 | 不推論收入、收益、財富或持續成功。 |
| `modern.transformation.quan` | 化星功能在落宮領域可能涉及推動與責任分配。 | 不推論權位、支配他人或升遷。 |
| `modern.transformation.ke` | 化星功能在落宮領域可能涉及整理、表達與被看見。 | 不推論學歷、名聲、考試或成就。 |
| `modern.transformation.ji` | 化星功能在落宮領域可能涉及反覆處理與調整需求。 | 不推論疾病、災禍、損失或關係破裂。 |

本表只摘要原編輯條目，最終執行 meaning 與適用宮位限制仍須逐條審閱。
正例須涵蓋四種 canonical 化星配對，反例包含未知化星、缺星曜位置、錯誤宮位及 unsupported 高風險問題。
只證明四化名稱存在不能產生個人化含義。

## 四宮的三方四正

結構只依 `natal.palace.<palace>.sanFangSiZheng` 及四宮各自的 branch facts。
下表順序固定為本宮、三合宮一、三合宮二、對宮，沿用來源的 stable IDs。

| claim ID | 本宮 | 三合宮一 | 三合宮二 | 對宮 |
| --- | --- | --- | --- | --- |
| `structure.relation.life` | `life` | `wealth` | `career` | `travel` |
| `structure.relation.wealth` | `wealth` | `career` | `life` | `fortune` |
| `structure.relation.career` | `career` | `life` | `wealth` | `spouse` |
| `structure.relation.travel` | `travel` | `fortune` | `spouse` | `life` |

關係集合為 canonical 結構；把本宮、對宮與三合宮描述為直接場域、拉力或資源仍是待審轉譯。
正例要同時驗證四宮身分及 branch 關係，反例包括錯置對宮／三合宮、缺少關係 fact 與借星改寫本宮位置。
導覽可以標示這些結構，但不以教學代替個人化組合規則。

## 支持與牽制試點

本批上限四條且至少各有一條支持及牽制規則，現階段尚未有符合全部條件的試點入列。
缺少的是可支持特定組合 meaning 的來源、適用條件及人工審閱，不是星曜位置資料。
不把兩條主星既有 meaning 自動串成新組合，也不自行選擇格局或命名待補規則。
因此五項功能計畫中「凍結有限試點清單」與「啟用綜合解讀」仍未完成。

試點入列時必須逐條記錄以下資料，缺一不可：

1. 唯一 rule ID、claim ID、內容版本及支持／牽制類型。
2. 固定來源修訂與章節，或合法出版版本及頁碼。
3. 精確必要條件、排除條件與全部 evidence fact IDs。
4. 精確 meaning、適用分類、禁止推論及與其他規則的去重關係。
5. 由 canonical facts 重現的正例與缺條件、衝突、重複訊號反例。
6. 人工審閱者、接受範圍、日期、所審內容版本及可追溯結論。

沒有完整封閉 facts 集合時，缺少某訊號不能視為該訊號不存在。
同一 fact 的重述不能重複計為獨立支持。

## 既有契約修復證據

2026-09-12 核對格式化 commit `3c9db88` 的前一版 `InterpretationSeedBuilder.swift`，其 SHA-256 等於舊 seed contract 的 `c7c22022a3ad75a48b88dfcf23e4387569a4fb7b74c84cb8e261064535b4946d`。
以目前 `xcrun swift-format format` 格式化該舊版後，輸出與現行 builder 逐 byte 相同，現行 SHA-256 為 `549d5261f856d9157a09523bd0756a06e528279fc512d9a2ea3c414de4d09aa2`。
此次只修正格式化造成的契約漂移，沒有改變任何既有 seed ID、meaning、分類、evidence 或核准範圍。
新增 `scripts/tests/test_seed_contract.py` 驗證不同縮排的 enum 集合、精確 seeds，以及 meaning、evidence、落宮、ID 和 hash 竄改均被拒絕。
程式碼契約核對不能代替本帳新主張的人工審閱。

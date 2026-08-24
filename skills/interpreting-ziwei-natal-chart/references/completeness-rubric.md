# 本命盤知識完整度量表

本量表把「完整度 100 分」限定為本 Skill 宣告的知識、來源治理、支援狀態與安全路由均完整。

範圍包含十四主星、六吉、六煞、祿存、天馬、生年四化、十二宮、身宮、三方四正、來源追溯、approved seed 支援矩陣與停止條件。

範圍不包含廟旺利陷、格局定論、大限、流年、流月、流日、自化、飛化、宮干四化、夾宮、中州派地盤或人盤。

100 分不表示紫微斗數已獲科學證明，也不表示待審現代語句已成為 approved seed。

100 分要求沒有 seed 的項目必須被明確降級為一般知識或盤面 facts，不得假裝可進行個人化解讀。

## 執行方式

本機完整檢查與反例測試：

```bash
uv run --with hanzidentifier==1.3.0 python skills/interpreting-ziwei-natal-chart/scripts/check_knowledge_coverage.py --self-test
```

同時重查維基文庫固定 revision metadata 與內容 hash：

```bash
uv run --with hanzidentifier==1.3.0 python skills/interpreting-ziwei-natal-chart/scripts/check_knowledge_coverage.py --online --self-test
```

腳本只有總分為 100 時才回傳成功。

網路查核失敗時會明確失敗，不會以舊 cache 冒充當次線上驗證。

## 分項

| 分項 | 分數 | 100 分狀態的通過條件 |
| --- | ---: | --- |
| 範圍、權威狀態與安全 | 10 | 明分一般知識、canonical、approved seed、產品語句與待審轉譯，並禁止把完整度誤述為科學或專家認證。 |
| 來源 provenance 與內容完整性 | 15 | 修訂建立時間不晚於擷取時間，raw 與 rendered revision hashes 相符，分檔快照 hash、來源 anchor 與 rendered 文字覆蓋率通過，且 E01 至 E08 各自具有可支持與不能支持事項。 |
| 十四主星 claim schema | 15 | 14 顆主星各有唯一 ID、功能、資源、張力、核對問題、來源狀態，且安全欄位沒有宿命斷言。 |
| 六吉六煞、祿存與天馬 claim schema | 15 | 14 顆支援星曜各有唯一 ID、六欄語句與禁止推論，並把地空 nomenclature crosswalk 標為未解。 |
| 十二宮與身宮 | 15 | 12 宮各有功能、核對問題與禁止推論，6 種身宮落宮都有 claim，且沒有 seed 時停止個人化含義。 |
| 生年四化與三方四正 | 10 | 四化各有安全句型，12 宮關係以 stable IDs 解析並符合 `P + 4`、`P + 8`、`P + 6`。 |
| approved seed 支援矩陣 | 10 | 驗證 builder hash、五個 baseline 精確契約、十四主星 70 組 meaning 精確契約、seed 與 fact manifest hashes，並列出實際可用與未支援項目。 |
| Skill 契約、產品邊界、語言與維護 | 10 | 本機連結、產品 enums、公開 fact ID、[產品未實作契約](product-integration-boundaries.md)、台灣正體中文、檔案大小及 checker 反例測試全部通過。 |
| **總分** | **100** | 所有自動條件均通過，人工待審事項維持正確狀態標籤。 |

## Checker 能證明的事項

Checker 會解析每個主星、支援星曜、宮位與四化章節的欄位，不只搜尋 claim ID 是否出現。

Checker 會拒絕錯誤或重複 claim ID、缺欄位、非問句核對問題，以及安全欄位中的常見宿命斷言。

Checker 會驗證每個來源檔的 frontmatter、最小內容、預期章節、SHA-256 與來源 anchors。

線上模式會比對 rendered revision，要求各分檔的大部分實質文字確實出現在固定修訂頁面中。

Checker 會驗證 revision 建立時間不晚於擷取時間。

`--online` 會從 MediaWiki API 重新下載固定 revision，核對 revision ID、timestamp 與來源內容 SHA-256。

Checker 會逐項驗證 E01 至 E08 都有自己的支持與不支持邊界。

線上模式會驗證 E03 兩筆詳細書目確實含 `0470017` 與 `rarecatx0428879`，並核對 E05 與 E06 的頁面內容識別。

E04 的 CText 可能回傳真人驗證頁，因此自動 gate 只確認 HTTPS 可達，並明示內容識別依人工與 Firecrawl 查核。

Checker 會用 `hanzidentifier` 檢查 authored prose 與所有核准 seed meanings，並另查台灣慣用詞。

Checker 會把 Swift enum 當集合比對，避免只有宣告順序改變就產生假陰性。

Checker 會解析三方四正 stable IDs，不依賴顯示文字的固定表格格式。

`--self-test` 會注入宿命危害語句與錯誤 claim ID，確認 checker 確實失敗。

## Checker 不能證明的事項

來源 hash 只能證明保存內容沒有靜默改變，不能證明古籍已完成版本學校勘。

安全字詞檢查不能取代 approved seed 限制、人工內容審核或產品端結構化驗證。

目前 iOS validator 尚未實作 seed IDs 與 meaning 契約，詳細限制讀取 [產品整合邊界](product-integration-boundaries.md)。

本量表的 100 分不表示 iOS validator 已完成該整合工作。

條目齊全不能把 `editorial-pending-review` 自動升格為 approved seed。

書目與出版社簡介不能證明中州派逐星、四化或排盤技術規則。

因此 [InterpretationSeed 支援矩陣](seed-support-matrix.md) 的未支援項目即使知識條目完整，也只能回答一般知識與顯示 facts。

## 人工審核佇列

- `RULESET.md` 的 canonical tables 尚待熟悉台灣傳統三合派者核對。
- 一部分 golden charts 尚待人工 reviewer 核對。
- `editorial-pending-review` 語句尚待命理專家與內容安全 reviewer 核對。
- 《紫微斗數全書》的天空與產品地空 crosswalk 尚待專家及版本校勘。
- 中州派逐星技術規則、閏月差異與庚干四化差異尚待合法頁碼級證據。
- 古籍作者、成書年代、異文與疑似轉錄錯字尚待文獻學校勘。

人工審核未完成時，不得改稱「專家認證完整度」、「規則正確度」或「個人命盤 meaning 覆蓋率」100 分。

## 降分與停止條件

來源 revision 時間矛盾、hash 不符、預期章節缺失或證據帳缺少逐項限制時，來源分項歸零。

產品 enum 或 fact ID 改變但知識清單未同步時，產品契約分項歸零。

安全語句出現宿命斷言、checker 反例未被攔截，或未明示產品 validator 的 seed 契約缺口時，Skill 契約分項歸零。

SKILL.md 沒有把未具 seed 的項目停止於 facts 時，approved seed 分項歸零。

需要超出量表範圍的知識時，明示目前不支援，不以搜尋結果臨時擴張 100 分範圍。

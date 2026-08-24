# InterpretationSeed 支援矩陣

本檔案界定哪些知識目前能進入個人命盤解讀，哪些只能作為一般知識或盤面事實展示。

## 核准定義

本 Skill 所稱 approved seed，只指目前 repository 的 `InterpretationSeedBuilder` 依完整 facts deterministic 產生，且通過 `generate_chart_facts.py` 的 [seed contract](seed-contract.json) 驗證。

驗證範圍包含 builder 來源 hash、五個 baseline 的精確 ID、category、meaning 與 evidence，以及十四主星 70 組 category meaning 的精確文字、seed ID、星曜、落宮、category 與對應星曜 evidence。

使用者自行提供、外部網站提供、模型產生或無法證明 builder 來源的 seed 一律視為未核准。

目前 `InterpretationSeed` model 沒有 status、claim ID 或來源版本欄位，因此「核准」是本 Skill 對資料來源的額外限制，不是 model 自帶保證。

未來 model 增加可驗證 provenance 前，不得把任意同形 JSON 當成 approved seed。

## 目前可用 seeds

### 五個 baseline seeds

- `seed.overview.baseline` 引用 `natal.bureau`。
- `seed.personality.baseline` 引用 `natal.palace.life.branch`。
- `seed.career.baseline` 引用 `natal.palace.career.branch`。
- `seed.wealth.baseline` 引用 `natal.palace.wealth.branch`。
- `seed.relationships.baseline` 引用 `natal.palace.spouse.branch`。

### 十四主星 seeds

每顆主星只會依實際落宮產生一個 `seed.<category>.<star>.<palace>`。

seed 的 meaning 已由 `InterpretationSeedBuilder` 按落宮分類選擇 overview、personality、career、wealth 或 relationships 語句。

個人解讀只能使用實際 payload 中存在的 seed ID、meaning 與 evidence fact IDs，不得從 [本命盤現代功能語句](modern-functional-language.md) 自行合成新的 seed。

十四主星的 stable star IDs 為 `ziWei`、`tianJi`、`taiYang`、`wuQu`、`tianTong`、`lianZhen`、`tianFu`、`taiYin`、`tanLang`、`juMen`、`tianXiang`、`tianLiang`、`qiSha` 與 `poJun`。

## 目前沒有 approved seed 的項目

- 六吉：左輔、右弼、文昌、文曲、天魁與天鉞。
- 六煞：擎羊、陀羅、火星、鈴星、地空與地劫。
- 其他支援星曜：祿存與天馬。
- 身宮六種落宮的投入重點語句。
- 生年化祿、化權、化科與化忌的功能語句。
- 三方四正的資源、拉力與牽制語句。
- 兄弟、子女、疾厄、遷移、僕役、田宅、福德與父母宮的獨立宮位 meaning。
- 任何兩星、星系、格局或祿馬組合 meaning。

上述項目可以回答一般知識，也可以顯示已驗證盤面位置或關係。

上述項目目前不得產生個人化功能解讀。

## 星曜與宮位組合規則

不得把一個一般星曜功能與一個一般宮位功能直接串接成個人判斷。

目前唯一可用的星曜落宮組合，是 payload 中 `InterpretationSeedBuilder` 已產生的主星 seed meaning。

該 seed 只支持它自己的 category 語句，不支持其他宮位主題、輔煞修飾或三方延伸。

主星落入子女、疾厄、父母等目前映射為 overview 的宮位時，只能使用該 overview seed，不得自行補入宮位事件或健康含義。

疾厄、財帛、夫妻、子女與父母宮的禁止推論永遠優先，不能被星曜或四化語句繞過。

六吉六煞沒有 seed 時，只列星曜位於哪一宮，不描述它如何修飾主星。

三方四正沒有 meaning seed 時，只列四宮集合，不把三合宮寫成資源或結果。

## 輸出證據契約

每一個個人化解讀子句都必須同時列出：

1. 實際存在的 seed ID。
2. 該 seed 的原始 meaning。
3. 該 seed 的全部 evidence fact IDs。
4. 由 App 依 fact ID 取回的原始 fact 顯示文字。

seed ID 證明使用的是哪一段核准 meaning。

fact ID 只證明位置或關係，不證明 meaning。

只有 fact ID 而沒有 seed ID 時，只能列盤面事實。

只有 seed ID 而 evidence 不存在、為空或不完整時，拒絕該 seed。

同一子句不得引用一個無關 fact 替任意 meaning 背書。

## 完整封閉資料集

`generate_chart_facts.py` 成功輸出時，會列出 schema version、ruleset identity、expected fact IDs、expected fact count、`factsComplete` 與 `factManifestSha256`。

`factManifestSha256` 是 schema version、ruleset identity 與排序後 expected fact IDs 的 canonical JSON SHA-256。

輸出也會列出 `builderSourceSha256`、`seedContractSha256` 與 `seedsValidated`。

只有 `factsComplete` 為 true、實際 fact IDs 與 expected fact IDs 完全一致、fact manifest hash 可重算，且 ruleset identity 符合目前產品時，才能把 facts 視為完整封閉資料集。

只有 `seedsValidated` 為 true、builder 與 seed contract hashes 相符，且每個 seed 通過精確契約時，才能使用 seeds。

外部傳入資料若缺少上述 manifest 與 hashes，預設不是完整封閉資料集。

非封閉資料集不能用缺少某個 fact 證明星曜、四化或關係不存在。

## 停止條件

找不到對應 seed ID 時，停止個人化含義，只回覆盤面事實與目前不支援範圍。

seed evidence 為空、重複、未知或不符合 payload 時，拒絕整個 seed。

問題要求輔煞、身宮、四化、三方四正或未支援宮位的個人化含義時，說明目前只有一般知識草稿與 facts，沒有 approved seed。

不得因 [本命盤現代功能語句](modern-functional-language.md) 已有完整條目，就假設它已進入 approved seed 範圍。

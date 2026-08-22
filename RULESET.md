# 很牛的紫微斗數規則集

## 1. 文件目的

本文件定義「很牛的紫微斗數」第一版採用的排盤規則與 canonical tables。

`ZiWeiCore` 必須將本文件視為 `taiwan-traditional-sanhe` v1 的實作規格。

所有規則必須 deterministic、可測試、可追溯、可版本化，而且不得依賴 UI 或 LLM。

## 2. 規則集識別

```text
ruleset_id: taiwan-traditional-sanhe
ruleset_version: 1
status: implemented-pending-expert-review
```

本規則集以台灣常見傳統三合派為主，中州派資料只用於補充流派差異。

本規則集不宣稱代表所有紫微斗數流派。

正式發布前仍須由熟悉台灣傳統三合派的人員核對規則與 golden charts。

## 3. 來源清單

主要排盤規則採下列可追溯公開資料交叉整理。

1. 《紫微斗數全書》，維基文庫數位版，卷一「安星法」相關段落，<https://zh.wikisource.org/wiki/紫微斗數全書/卷一>。
2. 《紫微斗數全書》，維基文庫數位版，卷二，<https://zh.wikisource.org/wiki/紫微斗數全書/卷二>。
3. 「紫微安星訣」，原文註明參考《斗數全書》及中州派安星法，<https://www.laiboyee.com/classicspt11.html>。
4. 「紫微鬥數安星訣」，紫微研習社，逐條列出安星口訣與五行局算法，<https://iztro.com/zh_TW/learn/setup.html>。
5. 譚冰，〈斗數閏月起盤探究〉，原刊《風水天地》第 241 期，2012 年 10 月，<https://tambingblog.wordpress.com/2012/10/01/斗數閏月起盤探究/>。
6. 中央氣象署「日曆資料－國農曆對照」，資料集 A-A0087-001，<https://opendata.cwa.gov.tw/dataset/all/A-A0087-001>。
7. 中央研究院計算中心「兩千年中西曆轉換」，<https://sinocal.sinica.edu.tw/>。

來源 1 與 2 為古籍數位版。

來源 3 與 4 用於核對口訣轉成表格後的完整性。

來源 5 用於記錄閏月規則差異。

來源 6 與 7 用於獨立核對國農曆 fixtures，不作執行期網路依賴。

網路排盤服務只能交叉比對，不得成為唯一來源。

## 4. 輸入與日期語意

canonical input 為 `BirthProfile`。

```swift
struct BirthProfile {
    let localDate: LocalDate
    let localTime: LocalTime
    let calendarIdentifier: CalendarIdentifier
    let timeZoneIdentifier: String
}
```

名稱或暱稱只屬 metadata，不得影響排盤。

MVP 只接受公曆出生日期、出生地當地民用時間，以及 IANA time zone identifier。

支援範圍為 1900-01-01 至 2099-12-31。

排盤使用出生地 local civil date 與 wall-clock time。

不得先轉成台灣時間或 UTC 再決定農曆日期與時辰。

MVP 不使用真太陽時，也不使用出生地經緯度。

## 5. 曆法規則

### 5.1 公曆轉農曆

規則 ID 為 `R-CALENDAR-001`，狀態為 `provisional`。

以 Apple Foundation `Calendar(identifier: .chinese)` 進行 deterministic 轉換。

轉換時必須將 calendar 的 time zone 設為 `BirthProfile.timeZoneIdentifier`。

輸出必須保存農曆年、月、日與 `isLeapMonth`。

曆法元件升級後必須重新執行中央氣象署與中央研究院資料建立的獨立 fixtures。

### 5.2 閏月排盤

規則 ID 為 `R-CALENDAR-002`，狀態為 `provisional`。

曆法層保留原始農曆月份與 `isLeapMonth`。

排盤月份採《紫微斗數全書．安身命例》的「閏月作下月」規則。

例如閏四月以五月安命身宮與月系星曜。

1900 至 2099 年不會遇到閏十二月。

若未來支援範圍包含閏十二月，必須先 bump ruleset version 並重新選定跨年行為。

已知差異為《斗數宣微》與中州派常見做法會將閏月十五日前視為本月、十五日後視為下月。

v1 不採用上下半月分法。

### 5.3 換日與子時

規則 ID 為 `R-CALENDAR-003`，狀態為 `verified-by-product-decision`。

local civil midnight 是日期邊界。

23:00 至 00:59 都屬子時。

23:00 至 23:59 不提前改用次日日期。

時辰地支的 index 使用下式。

```text
hour_branch_index = floor((hour + 1) / 2) mod 12
```

### 5.4 不存在與重複的當地時間

規則 ID 為 `R-CALENDAR-004`，狀態為 `provisional`。

輸入 local components 必須透過指定 time zone 建立日期並 round-trip 驗證。

不存在的 local time 必須拒絕。

夏令時間回撥造成的重複 local time 採第一次 occurrence，並在 UI 提示使用者。

重複時間不改變排盤使用的 local civil date 與時辰。

## 6. Canonical order

天干 index 固定如下。

```text
0 甲
1 乙
2 丙
3 丁
4 戊
5 己
6 庚
7 辛
8 壬
9 癸
```

地支 index 固定如下。

```text
0 子
1 丑
2 寅
3 卯
4 辰
5 巳
6 午
7 未
8 申
9 酉
10 戌
11 亥
```

顯示文字不得作為邏輯識別。

所有循環位移都使用 modulo 12。

## 7. 命宮、身宮與十二宮

規則 ID 分別為 `R-MING-001`、`R-SHEN-001` 與 `R-PALACE-001`，狀態為 `provisional`。

來源為《紫微斗數全書》安身命例與「寅起正月，順數至生月，逆數生時為命宮；順數生時為身宮」口訣。

令排盤月份為 `M`，其中正月為 1。

令時辰地支 index 為 `H`，其中子時為 0。

```text
life_branch = 寅 + (M - 1) - H
body_branch = 寅 + (M - 1) + H
```

十二宮從命宮逆行排列。

```text
命宮
兄弟宮
夫妻宮
子女宮
財帛宮
疾厄宮
遷移宮
僕役宮
官祿宮
田宅宮
福德宮
父母宮
```

stable IDs 固定如下。

```text
life
siblings
spouse
children
wealth
health
travel
friends
career
property
fortune
parents
```

## 8. 宮位天干

規則 ID 為 `R-PALACE-STEM-001`，狀態為 `provisional`。

以五虎遁定寅宮天干。

```text
甲、己年：丙寅
乙、庚年：戊寅
丙、辛年：庚寅
丁、壬年：壬寅
戊、癸年：甲寅
```

從寅宮起依地支順序逐宮遞增一個天干。

## 9. 五行局

規則 ID 為 `R-WUXING-001`，狀態為 `provisional`。

五行局由命宮干支決定。

天干取數如下。

```text
甲乙 = 1
丙丁 = 2
戊己 = 3
庚辛 = 4
壬癸 = 5
```

地支取數如下。

```text
子丑午未 = 1
寅卯申酉 = 2
辰巳戌亥 = 3
```

天干數與地支數相加，超過 5 時減 5。

結果對照如下。

```text
1 = 木三局
2 = 金四局
3 = 水二局
4 = 火六局
5 = 土五局
```

## 10. 十四主星

規則 ID 為 `R-ZIWEI-001` 與 `R-MAINSTAR-001`，狀態為 `provisional`。

### 10.1 安紫微

令五行局數為 `B`，農曆生日為 `D`。

```text
multiplier = ceil(D / B)
deficit = multiplier * B - D
base = 寅 + multiplier - 1
```

`deficit` 為偶數時，紫微位於 `base + deficit`。

`deficit` 為奇數時，紫微位於 `base - deficit`。

### 10.2 安天府

天府與紫微的地支 index 關係如下。

```text
tian_fu_branch = 4 - zi_wei_branch mod 12
```

完整對照如下。

```text
紫微子 → 天府辰
紫微丑 → 天府卯
紫微寅 → 天府寅
紫微卯 → 天府丑
紫微辰 → 天府子
紫微巳 → 天府亥
紫微午 → 天府戌
紫微未 → 天府酉
紫微申 → 天府申
紫微酉 → 天府未
紫微戌 → 天府午
紫微亥 → 天府巳
```

### 10.3 紫微星系

相對紫微的地支位移如下。

```text
紫微 0
天機 -1
太陽 -3
武曲 -4
天同 -5
廉貞 -8
```

### 10.4 天府星系

相對天府的地支位移如下。

```text
天府 0
太陰 +1
貪狼 +2
巨門 +3
天相 +4
天梁 +5
七殺 +6
破軍 +10
```

## 11. 六吉、六煞、祿存與天馬

規則 ID 為 `R-AUXSTAR-001` 至 `R-AUXSTAR-008`，狀態為 `provisional`。

### 11.1 左輔與右弼

正月左輔在辰，按排盤月份順行。

正月右弼在戌，按排盤月份逆行。

### 11.2 文昌與文曲

子時文曲在辰，按時辰順行。

子時文昌在戌，按時辰逆行。

### 11.3 地空與地劫

子時地劫在亥，按時辰順行。

子時地空在亥，按時辰逆行。

### 11.4 天魁與天鉞

每格先列天魁，再列天鉞。

```text
甲戊庚：丑、未
乙己：子、申
丙丁：亥、酉
辛：午、寅
壬癸：卯、巳
```

### 11.5 祿存、擎羊與陀羅

祿存表如下。

```text
甲 寅
乙 卯
丙 巳
丁 午
戊 巳
己 午
庚 申
辛 酉
壬 亥
癸 子
```

擎羊位於祿存順行一宮。

陀羅位於祿存逆行一宮。

### 11.6 天馬

天馬依出生年地支三合局安置。

```text
寅午戌 → 申
申子辰 → 寅
巳酉丑 → 亥
亥卯未 → 巳
```

### 11.7 火星與鈴星

下表先列子時火星起點，再列子時鈴星起點。

```text
申子辰：寅、戌
寅午戌：丑、卯
巳酉丑：卯、戌
亥卯未：酉、戌
```

兩星都從各自起點按出生時辰順行。

## 12. 生年四化

規則 ID 為 `R-SIHUA-001`，狀態為 `provisional`。

v1 只計算生年四化。

每列順序固定為化祿、化權、化科、化忌。

```text
甲：廉貞、破軍、武曲、太陽
乙：天機、天梁、紫微、太陰
丙：天同、天機、文昌、廉貞
丁：太陰、天同、天機、巨門
戊：貪狼、太陰、右弼、天機
己：武曲、貪狼、天梁、文曲
庚：太陽、武曲、太陰、天同
辛：巨門、太陽、文曲、文昌
壬：天梁、紫微、左輔、武曲
癸：破軍、巨門、太陰、貪狼
```

庚干採三合派常見的「陽武陰同」。

已知中州派常採「陽武府同」，v1 不採用此差異。

## 13. 三方四正

規則 ID 為 `R-RELATION-001`，狀態為 `provisional`。

對地支 index 為 `P` 的本宮，對宮為 `P + 6`。

兩個三合宮為 `P + 4` 與 `P + 8`。

結果必須使用 stable palace IDs，不得依靠顯示文字。

## 14. ChartFacts 與解讀邊界

所有命盤資訊必須先轉成 verified `ChartFact`，才能提供給解讀層。

Fact ID 必須使用語義穩定的 key。

```text
natal.palace.life.branch
natal.star.ziwei.palace
natal.transformation.lu.star
```

`InterpretationSeed` 必須引用至少一個存在的 fact ID。

Foundation Models 只能整理 App 已提供的 facts 與 seeds。

Foundation Models 不得計算命宮、身宮、星曜、五行局、四化、宮位干支、三方四正或曆法轉換。

未知 evidence fact ID 必須拒絕。

顯示 evidence 時必須由 App 依 ID 取回原始文字。

## 15. Golden fixtures

每份 fixture 必須包含 schema version、ruleset identity、來源、輸入與預期結果。

```text
公曆 local date 與 local time
IANA time zone
農曆日期與閏月狀態
命宮與身宮
宮位干支
五行局
十四主星
生年四化
六吉、六煞、祿存與天馬
```

Fixtures 必須涵蓋十二時辰、子時與午夜、農曆年邊界、閏月、不同時區、歷史夏令時間、1900 與 2099 邊界。

每個計算 bug 都必須新增 regression fixture。

不得只修改既有 fixture 來配合錯誤實作。

## 16. Determinism 與版本

相同 `BirthProfile`、`ruleset_id` 與 `ruleset_version` 必須永遠得到相同命盤。

排盤不得依賴網路、server、LLM、device locale、current date 或隨機數。

任何會改變排盤結果的規則修改都必須 bump `ruleset_version`。

UI、文案、翻譯與 AI prompt 修改不需要 bump ruleset version。

## 17. MVP 不支援項目

MVP 不顯示廟旺利陷。

MVP 不計算大限、流年、流月或流日。

MVP 不計算自化、飛化或宮干飛化。

MVP 不提供流派切換。

## 18. 發布前人工 gate

下列項目只能由外部證據完成，coding agent 不得自行勾選。

- [ ] 熟悉台灣傳統三合派的人員已核對全部 canonical tables。
- [ ] 人工 reviewer 已核對至少一部分 golden charts。
- [ ] 國農曆 1900 至 2099 範圍已以獨立來源抽樣驗證。
- [ ] 若 reviewer 要求修改排盤結果，已 bump ruleset version 並加入 regression fixtures。

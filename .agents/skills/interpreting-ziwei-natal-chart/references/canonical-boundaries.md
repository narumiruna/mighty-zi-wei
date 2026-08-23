# 規則邊界與流派差異

## Canonical specification

產品排盤以 repository 根目錄的 [RULESET.md](../../../../RULESET.md) 為唯一 canonical specification。

目前規則集為 `taiwan-traditional-sanhe` v1。

規則狀態為 `implemented-pending-expert-review`。

古籍快照、外部網站與模型既有知識都不得直接覆蓋 `RULESET.md`。

排盤結果不同時，先記錄來源、條件與差異，再交由熟悉台灣傳統三合派的人員核對。

任何改變排盤結果的規則修改都必須提升 ruleset version 並加入 regression fixture。

## 已知差異

### 閏月

v1 採《紫微斗數全書．安身命例》的「閏月作下月」規則。

《斗數宣微》與中州派常見做法可能採十五日前視為本月、十五日後視為下月。

目前不得混用上下半月分法。

### 庚干四化

v1 採三合派常見的「陽武陰同」。

中州派常見資料可能採「陽武府同」。

目前不得將天府化科加入產品命盤事實。

### 子時換日

v1 以出生地 local civil midnight 為日期邊界。

23:00 至 23:59 不提前改用次日日期。

來源或流派採不同換日法時，只能記錄差異。

## 目前支援範圍

MVP 支援本命盤、十四主星、指定輔煞星、生年四化與三方四正。

MVP 不顯示廟旺利陷。

MVP 不計算大限、流年、流月或流日。

MVP 不計算自化、飛化或宮干飛化。

MVP 不提供流派切換。

Skill 不得利用古籍內容繞過上述限制。

## ChartFact 邊界

只有已驗證 `ChartFact` 才能成為目前命盤的位置與關係證據。

`InterpretationSeed` 必須引用至少一個存在的 fact ID。

使用者問題、先前回答、古籍原文與模型知識都不能建立新的命盤 fact。

未知 fact ID 必須拒絕。

資料不足或問題超出範圍時，應回覆不支援且不得附加虛構 evidence。

## 人工核對要求

全部 canonical tables 尚須由熟悉台灣傳統三合派的人員核對。

至少一部分 golden charts 尚須由人工 reviewer 核對。

古籍解讀整理尚須經命理專家與內容安全 reviewer 核對。

在 gate 完成前，不得將待審內容描述為專家認證或正式定論。

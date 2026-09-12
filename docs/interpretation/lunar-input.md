# 農曆輸入與曆法驗證界線

## 輸入契約

農曆年指該農曆新年所在的公曆年，不是干支年或六十年循環值。
輸入年、月、日與閏月旗標後，`LunarBirthResolver` 使用出生地 IANA 時區及完整當地民用時間轉換。
轉換後的公曆資料須由使用者確認，才會交給既有排盤器或相鄰時辰比較。
`BirthProfile`、公曆輸入、排盤 v1 與已儲存資料格式不變。
最終公曆範圍仍為 1900-01-01 至 2099-12-31；下界可能屬於 1899 農曆年。
無效日期、不存在的閏月、DST 不存在時間及不能核對的月界會明確拒絕，草稿保持可更正。
重複時間沿用既有第一次出現政策，並使用既有確認畫面。

## 證據種類

`apps/ios/MightyZiWeiTests/Fixtures/lunar_birth_reference_cases.json` 分開記錄本次讀取的香港天文台公開文字與 repository 既有 reference fixtures。
2023、2024、2099 年文字對照涵蓋農曆新年、跨公曆年、閏二月、大小月與上界。
每份文字來源保留 URL、SHA-256、必要短摘錄與適用限制，不納入 PDF 或圖片。
1900 下界、紐約歷史重複時間與 Kiritimati 上界承接既有 fixture 的來源紀錄，不宣稱本次重新取得人工核對。
香港對照不證明海外歷史時區，也不證明所有未抽樣日期。

`LunarBirthRoundTripTests` 的 73,049 個台北民用日期與海外抽樣是 Foundation 正反向自我一致測試，不是獨立曆法效度證據。
任何新增拒絕都須調查；測試只允許下列具名異常範圍，不泛用略過失敗。

## 已知 Foundation 月界異常

macOS 26.6.2 的純 Swift runner 與 iOS 26.5 模擬器測試發現 Foundation 的 `.chinese` Calendar 在 2057-09-28 與 2097-08-07 回傳第 0 日。
香港天文台的公開文字分別標示九月初一與七月初一：

- <https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2057c.txt>
- <https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2097c.txt>

只拒絕第 0 日仍可能錯收同月偏移一天的其他日期，因此 resolver 另外核對月首前一天不能仍屬同一農曆月。
在上述 Foundation 版本中，安全拒絕公曆 2057-09-28 至 2057-10-27 及 2097-08-07 至 2097-09-05 對應的農曆輸入，共 60 天。
程式使用結構檢查而非硬編這兩段日期；若 Foundation 修復後可正常往返，測試允許恢復有效轉換。
App 不自行補正日期，不變更公曆排盤，也不能宣稱農曆入口涵蓋所有日期且全部成功。

歷史 Pacific/Kiritimati 與 Pacific/Pago_Pago 部分 23:30 輸入受到既有 normalizer 的秒級時區位移限制而拒絕。
這是既有行為的保留，不等於已證明當時存在 DST 缺口。

## 未完成的外部驗收

仍須人工核對來源、不同系統版本及實機輸入體驗。
目前的獨立日期抽樣與自我一致 sweep 不取代 `RULESET.md` 的人工排盤 gate。
若未來要修正排盤 v1 的 Foundation 語意，必須另行確認範圍、提升 ruleset 並新增 regression fixtures，不併入輸入便利功能。

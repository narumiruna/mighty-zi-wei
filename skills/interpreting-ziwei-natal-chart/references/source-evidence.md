# 外部來源證據帳

本檔案記錄可重現的網路查詢結果、每個來源能支持的精確範圍，以及不能支持的事項。

最近查核日期為 2026-08-24。

## 使用規則

網路搜尋結果只用來發現來源，不直接成為證據。

每項主張都必須回到固定修訂、館藏書目、出版社書目、固定 commit 或 repository 內容。

來源可靠度只衡量該來源對限定主張的支持力，不衡量紫微斗數的預測效度。

不得因多個網站重複同一句話，就把未校勘說法升格為共識。

## E01 維基文庫《紫微斗數全書》卷一

- 類型：固定修訂的社群古籍轉錄。
- 頁面：https://zh.wikisource.org/zh-hant/紫微鬥數全書/卷一
- 固定修訂：https://zh.wikisource.org/w/index.php?title=紫微鬥數全書/卷一&oldid=7913704
- 修訂建立時間：2026-08-07T05:47:26Z。
- 來源內容 SHA-256：`9beb8038a8b82154d15d81c8ff822423d4f0c7c006f536a86552adeaa594818a`。
- 快照查核日期：2026-08-24。
- 可支持：固定修訂內確有基礎賦文、諸星問答、十四主星、指定輔煞與四化的歷史文字。
- 可支持：〈太微賦〉、〈斗數發微論〉及相關賦文明示會合、廟陷與其他條件會改變判讀，適合查證「不可脫離組合」的古籍語境。
- 不能支持：作者歸屬無爭議、轉錄無錯、命理規則客觀有效或古代斷語可直接套用現代個人。
- 使用位置：`references/sources/quanshu-volume-1-*.md`。
- 完整性資料：`references/sources/manifest.json`。

## E02 維基文庫《紫微斗數全書》卷二

- 類型：固定修訂的社群古籍轉錄。
- 頁面：https://zh.wikisource.org/zh-hant/紫微鬥數全書/卷二
- 固定修訂：https://zh.wikisource.org/w/index.php?title=紫微鬥數全書/卷二&oldid=1963110
- 修訂建立時間：2020-09-04T14:06:27Z。
- 來源內容 SHA-256：`1e255c6ae99e6f89ae124ab342554ef1347fc8e68fb8908cba7290d1a38cbb72`。
- 快照擷取日期：2026-03-01。
- 可支持：固定修訂內確有〈安身命例〉、十二宮次序、安星口訣、十干四化及十二宮古代條文。
- 可支持：〈安身命例〉的原文確實記載「閏月作下月」的做法。
- 不能支持：目前產品實作必然正確、所有流派都採同一規則或疾病、婚育、財富與死亡斷語可使用。
- 使用位置：`references/sources/quanshu-volume-2-*.md`。
- 完整性資料：`references/sources/manifest.json`。

## E03 國家圖書館中文古籍聯合目錄

- 類型：國家圖書館彙整的機構館藏書目。
- 查詢入口：https://rbook.ncl.edu.tw/NCLSearch/Search/Index/2
- 重現方式：以題名「紫微斗數」查詢，檢視正題名「紫微斗數 三卷」與影印本「紫微斗數」記錄。
- 固定書號：三卷本為 `0470017`。
- 三卷本詳細頁：https://rbook.ncl.edu.tw/NCLSearch/Search/SearchDetail?item=2c232ad339394f5cbf6e9baa12e92e69fDc5NDc3Mw2.LAXE_9UcGRDrgMmWjXgOuOuoLYbtjkdEGYgQQLBWLFA_&page=74204&whereString=IChOVUxMSUYoRGF0ZV9DcmVhdGVkLCAnICcpIGlzIE5VTEwgYW5kIE5VTExJRihEb2N1bWVudF9ZZWFyLCAnICcpIGlzIE5VTEwgKSA1.uQrV5XxqrHh4fOCXMwOuuzssvPVRwJbumFyT4mFEUCA_&sourceWhereString=&SourceID=1&HasImage=
- 固定登錄號：上海影印本為 `rarecatx0428879`。
- 上海影印本詳細頁：https://rbook.ncl.edu.tw/NCLSearch/Search/SearchDetail?item=1b36e75d6cb348bcafa51089508d41ccfDI3ODUxNA2.T5_fvtPg0BL_gp0oecUpf3kBMYmGj_Zu9aAWwhejGlk_&page=3538&whereString=IChOVUxMSUYoQ3JlYXRlcl9OYW1lLCAnICcpIGlzIE5VTEwgYW5kIE5VTExJRihEb2N1bWVudF9Xcml0ZXIsICcgJykgaXMgTlVMTCBhbmQgTlVMTElGKEpvdXJuYWxfV3JpdGVyLCAnICcpIGlzIE5VTEwgKSA1.cHNKVlDaZLqmac_B_QboEZhR4vv4gJ8MEx7vCx6fK8U_&sourceWhereString=&SourceID=1&HasImage=
- 可支持：聯合目錄確有三卷本館藏記錄，現藏日本京都大學人文科學研究所，作者欄標為「闕名撰」。
- 可支持：另一筆記錄為上海民國 12 至 15 年影印本，現藏中國國家圖書館，叢書名標為《正統道藏》。
- 不能支持：這些館藏與目前流通《紫微斗數全書》內容完全相同，或陳摶、羅洪先等傳統署名已獲文獻學確認。
- 研究結論：未完成版本學校勘前，Skill 不宣稱《紫微斗數全書》的確定作者與成書年代。

## E04 中國哲學書電子化計劃《紫微斗數》

- 類型：連結底本影像的 OCR 與可共同編輯資料頁。
- 頁面：https://ctext.org/wiki.pl?if=gb&res=979714
- 底本標示：頁面標為《正統道藏》本，作者與成書年代都標為「暫缺」。
- 可支持：該站有底本影像、OCR 對應與三卷章節索引，可作版本與異文查核入口。
- 可支持：資料頁明確警告 OCR 可能需要糾正。
- 不能支持：資料頁的維基式歷史敘述、晚子時說法、推算方法或流派分類已經學術定論。
- 研究結論：只把底本影像與書目欄位列為查核線索，不把頁面整理覆蓋 `RULESET.md`。
- 線上限制：CText 可能對自動查核回傳真人驗證頁，因此 checker 只驗證 HTTPS 可達；內容識別仍依本次人工與 Firecrawl 查核，不宣稱每次自動重現。

## E05 王亭之《紫微斗數古訣今註》

- 類型：作者與出版社可辨識的商業出版品書目與出版社簡介。
- 頁面：https://play.google.com/store/books/details?id=JvAVBQAAQBAJ
- 書目：王亭之，圓方出版社，2009 年，255 頁。
- 可支持：出版社簡介把中州學派定位為反對僵硬宿命，並主張配合現代社會文化背景解讀古訣。
- 可支持：簡介表示該系列包含十四正曜特質、起盤、定局與時差注意事項。
- 不能支持：任何未見內頁與頁碼的逐星規則、四化表、古本年代、流派共識或命理效果。
- 使用限制：目前只把「反宿命與重視現代語境」列為中州派補充方向，不引用逐星技術細則。

## E06 王亭之《王亭之談星：紫微斗數星曜總談》

- 類型：圖書館聯合目錄書目。
- 頁面：https://search.worldcat.org/zh-tw/title/58994949
- 書目：王亭之，博益出版集團，香港，1991 年，WorldCat OCLC 58994949。
- 可支持：可確認這本中州派候選研究書目的作者、題名、出版者與年份。
- 不能支持：未取得合法內頁與頁碼前，不能支持任何逐星主張或現代轉譯。
- 使用限制：只列入後續人工研究路由，不複製未授權全文。

## E07 iztro 固定開源實作

- 類型：MIT License 的外部實作參考。
- repository：`references/iztro/`。
- 固定 commit：`814b77e6371e1050cac31bbf674db3c3138fcfde`。
- 可支持：該 commit 的資料表、演算法、型別與測試在指定設定下具有某種實作行為。
- 可支持：分析器把目標宮、對宮與兩個三合宮分開查詢，適合借鏡結構化量詞。
- 不能支持：傳統規則正確、產品 ruleset 已獲驗證、外部預設符合台灣三合派或其解讀文案可直接使用。
- 詳細邊界：讀取 [iztro 實作參考指南](iztro-guide.md)。

## E08 repository 現行產品語句

- 類型：本 repository 的現行產品內容與 deterministic seeds。
- 宮位與星曜教學：`apps/ios/MightyZiWei/Features/Chart/ChartLearningContent.swift` 的 `ChartLearningCatalog`。
- 主星分類 seed：`apps/ios/MightyZiWei/Interpretation/InterpretationSeedBuilder.swift`。
- 支援星曜集合：`apps/ios/MightyZiWei/Domain/Star.swift` 的 `Star.allCases`。
- 可支持：目前產品已使用的台灣正體中文功能語句、星曜清單與 seed 產生範圍。
- 不能支持：所有產品語句已獲命理專家認證、科學實證或能在缺少對應 fact 與 seed 時任意使用。
- 使用位置：讀取 [本命盤現代功能語句](modern-functional-language.md)。

## E09 名稱與文件契約差異

- 類型：repository 內部交叉查核。
- 地空差異：產品 stable ID 為 `diKong`，但《紫微斗數全書》快照使用「天空地劫」與「天空鄉」。
- 地空處置：異名、同星或不同星關係標為 `unresolved`，不把古籍天空直接當成產品地空來源。
- Fact ID 差異：`RULESET.md` 舊範例曾使用 `natal.star.ziwei.palace`，實作 `Star.rawValue` 與實際輸出使用 `natal.star.ziWei.palace`。
- Fact ID 處置：以實際 stable raw value 的 camelCase 形式為準，並由完整度 checker 比對文件與 enum。
- 中州派差異：閏月上下半月與庚干「陽武府同」目前缺代表性著作頁碼。
- 中州派處置：兩項都標為 `unverified-school-difference`，不宣稱是中州派共識。

## 搜尋但未採用的資料

一般命理網站、課程頁、論壇、匿名轉載、Scribd 上傳與搜尋摘要都未作為技術主張來源。

這些資料常未交代版本、責任者、流派設定或授權狀態。

它們最多只能提供待查關鍵字，不能進入 canonical 規則、approved seed 或古籍引文。

## 來源衝突處理

排盤衝突依序採 `ChartFact`、`RULESET.md`、固定 regression fixture，再記錄外部差異。

解讀語句衝突先確認 approved seed，再區分產品現行語句、編輯轉譯與古籍原文。

作者、年代或版本歸屬衝突時保留「不詳」或「待校勘」，不得用傳統傳說補空白。

中州派資料若只有書目或出版社簡介，只能支持研究方向，不能補出逐星規則。

## 更新要求

每次新增外部來源都要記錄查核日期、固定版本或書目識別、可支持與不能支持事項。

每次更新維基文庫快照都要保留舊修訂資訊，並重新檢查章節邊界、異文與授權。

每次更新 iztro 都要記錄舊 commit、新 commit 與既有差異是否改變。

受著作權保護的現代書籍只保存必要短摘錄、頁碼與自己的轉譯，不建立整本快照。

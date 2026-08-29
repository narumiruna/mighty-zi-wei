import Foundation

struct PalaceLearningContent: Equatable, Sendable {
  let focusTitle: String
  let purpose: String
  let relatedLabel: String
}

struct StarLearningContent: Equatable, Sendable {
  let keywords: [String]
  let summary: String
  let strengths: String
  let cautions: String
}

enum ChartLearningCatalog {
  static func palace(_ kind: PalaceKind) -> PalaceLearningContent {
    switch kind {
    case .life:
      .init(focusTitle: "你的核心性格", purpose: "認識你習慣如何反應、判斷與選擇。", relatedLabel: "你自己")
    case .siblings:
      .init(focusTitle: "手足與同輩互動", purpose: "觀察你和手足、同輩合作與保持界線的方式。", relatedLabel: "手足與同輩")
    case .spouse:
      .init(focusTitle: "親密關係", purpose: "觀察你在親密互動中重視的感受與相處方式。", relatedLabel: "親密關係")
    case .children:
      .init(focusTitle: "照顧與創造", purpose: "觀察你面對照顧、培養與創造事物時的傾向。", relatedLabel: "照顧與創造")
    case .wealth:
      .init(focusTitle: "資源與金錢", purpose: "觀察你安排金錢、時間與其他資源時的偏好。", relatedLabel: "金錢與資源")
    case .health:
      .init(focusTitle: "身心節奏", purpose: "從命盤角度反思你的生活節奏，不用來診斷健康。", relatedLabel: "身心節奏")
    case .travel:
      .init(focusTitle: "外在環境", purpose: "觀察你離開熟悉環境、面對變化與外界互動時的傾向。", relatedLabel: "外在環境")
    case .friends:
      .init(focusTitle: "朋友與合作", purpose: "觀察你選擇夥伴、建立合作與參與群體的方式。", relatedLabel: "朋友與合作")
    case .career:
      .init(focusTitle: "工作方式", purpose: "觀察你投入工作、承擔角色與追求成果時的偏好。", relatedLabel: "工作")
    case .property:
      .init(focusTitle: "家庭與安定感", purpose: "觀察你如何建立生活基礎、空間感與安定感。", relatedLabel: "家庭與生活基礎")
    case .fortune:
      .init(focusTitle: "內在感受", purpose: "觀察你獨處、恢復能量與尋找內在滿足的方式。", relatedLabel: "內在感受")
    case .parents:
      .init(focusTitle: "長輩與支持", purpose: "觀察你面對長輩、規範與支持系統時的互動方式。", relatedLabel: "長輩與支持")
    }
  }

  static func star(_ star: Star) -> StarLearningContent {
    switch star {
    case .ziWei:
      .init(
        keywords: ["自主", "統整", "成就"], summary: "紫微代表掌握方向、建立秩序與承擔責任的傾向。",
        strengths: "可能有主見，能從整體思考並願意承擔責任。", cautions: "可能對標準要求較高，也需要留意是否太在意掌控感。")
    case .tianJi:
      .init(
        keywords: ["思考", "規劃", "調整"], summary: "天機代表觀察變化、規劃與持續調整的傾向。",
        strengths: "可能反應靈活，擅長分析並預先思考不同方案。", cautions: "想法較多時可能難以停下來，需要為決定設定界線。")
    case .taiYang:
      .init(
        keywords: ["坦率", "責任", "連結"], summary: "太陽代表對外連結、清楚表達與提供支持的傾向。",
        strengths: "可能願意承擔責任，也樂於讓事情變得明朗。", cautions: "投入他人需要時，也要記得保留自己的能量。")
    case .wuQu:
      .init(
        keywords: ["務實", "效率", "成果"], summary: "武曲代表重視現實條件、效率與具體成果的傾向。",
        strengths: "可能擅長把目標轉成可執行的步驟。", cautions: "專注成果時，也要留意感受與溝通是否被忽略。")
    case .tianTong:
      .init(
        keywords: ["柔和", "舒適", "包容"], summary: "天同代表重視和諧、舒適感與生活品質的傾向。",
        strengths: "可能容易體諒他人，也能讓互動保持柔軟。", cautions: "避免衝突有時會延後必要的決定或界線。")
    case .lianZhen:
      .init(
        keywords: ["原則", "界線", "敏銳"], summary: "廉貞代表重視原則、界線與人事細節的傾向。",
        strengths: "可能能察覺複雜關係中的分寸與規則。", cautions: "反覆衡量時，可能需要分清原則與過度顧慮。")
    case .tianFu:
      .init(
        keywords: ["穩定", "承接", "累積"], summary: "天府代表建立基礎、保存資源與維持長期運作的傾向。",
        strengths: "可能可靠而有耐心，擅長讓事情穩定延續。", cautions: "重視穩定時，也要為必要改變保留空間。")
    case .taiYin:
      .init(
        keywords: ["細膩", "內省", "感受"], summary: "太陰代表細膩觀察、內在整理與重視感受的傾向。",
        strengths: "可能有耐心，能注意氣氛與容易被忽略的細節。", cautions: "感受很多時，需要留出時間整理而不是獨自承受。")
    case .tanLang:
      .init(
        keywords: ["好奇", "探索", "互動"], summary: "貪狼代表對新鮮體驗、人際互動與多元可能保持好奇。",
        strengths: "可能願意嘗試，也能從不同人事物取得靈感。", cautions: "選擇很多時，需要留意投入是否過度分散。")
    case .juMen:
      .init(
        keywords: ["提問", "辨析", "表達"], summary: "巨門代表透過提問、辨析與表達來理解事情的傾向。",
        strengths: "可能不輕易接受表面答案，擅長把問題說清楚。", cautions: "重視釐清時，也要留意語氣是否造成距離。")
    case .tianXiang:
      .init(
        keywords: ["平衡", "合作", "分工"], summary: "天相代表觀察各方需要、尋找平衡與合適分工的傾向。",
        strengths: "可能擅長協調，也重視公平與合作品質。", cautions: "顧及所有人時，需要避免忽略自己的立場。")
    case .tianLiang:
      .init(
        keywords: ["原則", "照顧", "長期"], summary: "天梁代表重視原則、照顧與長期價值的傾向。",
        strengths: "可能願意支持他人，也會思考事情是否經得起時間。", cautions: "習慣照顧別人時，也需要保留自己的界線。")
    case .qiSha:
      .init(
        keywords: ["決斷", "挑戰", "開路"], summary: "七殺代表面對挑戰、快速決斷與開拓道路的傾向。",
        strengths: "遇到壓力時可能敢於行動，也能處理困難任務。", cautions: "行動快速時，需要為資訊與他人的節奏留出緩衝。")
    case .poJun:
      .init(
        keywords: ["改變", "重整", "突破"], summary: "破軍代表打破舊方法、重新整理與面對變動的傾向。",
        strengths: "當既有方式失效時，可能有勇氣重新開始。", cautions: "推動改變前，可以先分清必要調整與一時衝動。")
    case .zuoFu:
      .init(
        keywords: ["協助", "組織", "支持"], summary: "左輔可以先理解為增加協助、組織與承接力量的星曜。",
        strengths: "可能願意補位，也容易看見如何讓事情更完整。", cautions: "協助別人時，需要確認責任與界線。")
    case .youBi:
      .init(
        keywords: ["合作", "回應", "支持"], summary: "右弼可以先理解為增加合作、回應與人際支持的星曜。",
        strengths: "可能容易配合情境，並在互動中提供幫助。", cautions: "配合他人時，也要保留自己的判斷。")
    case .wenChang:
      .init(
        keywords: ["學習", "條理", "表達"], summary: "文昌可以先理解為加強學習、條理與文字表達的星曜。",
        strengths: "可能擅長整理資訊，並以清楚方式傳達。", cautions: "重視形式與條理時，也要保留彈性。")
    case .wenQu:
      .init(
        keywords: ["感受", "創意", "表達"], summary: "文曲可以先理解為加強感受、創意與細膩表達的星曜。",
        strengths: "可能對語氣、美感與互動細節較敏銳。", cautions: "感受豐富時，需要避免被短暫氣氛牽動。")
    case .tianKui:
      .init(
        keywords: ["提攜", "機會", "支持"], summary: "天魁可以先理解為帶入提攜、機會與正向支持的星曜。",
        strengths: "可能較容易看見可用資源，也願意接受合適協助。", cautions: "外在支持仍需要配合自己的準備與選擇。")
    case .tianYue:
      .init(
        keywords: ["協助", "理解", "轉圜"], summary: "天鉞可以先理解為帶入理解、協助與轉圜空間的星曜。",
        strengths: "面對困難時，可能較能找到協調或求助的途徑。", cautions: "得到協助時，也需要維持自己的行動。")
    case .qingYang:
      .init(
        keywords: ["直接", "突破", "摩擦"], summary: "擎羊可能讓表現更直接，也增加突破阻力時的張力。",
        strengths: "面對障礙時可能敢於正面處理。", cautions: "力量較直接時，需要留意急切與摩擦。")
    case .tuoLuo:
      .init(
        keywords: ["反覆", "耐力", "延遲"], summary: "陀羅可能讓事情經過反覆與延遲，也考驗持續處理的耐力。",
        strengths: "面對長期問題時，可能逐步累積韌性。", cautions: "反覆考量時，需要辨認何時應該停止消耗。")
    case .huoXing:
      .init(
        keywords: ["快速", "行動", "爆發"], summary: "火星可能讓反應與行動更快速，也帶來較明顯的爆發力。",
        strengths: "需要立即處理時，可能有快速啟動的力量。", cautions: "反應很快時，可以先留一點確認空間。")
    case .lingXing:
      .init(
        keywords: ["敏捷", "集中", "張力"], summary: "鈴星可能讓反應更敏捷、集中，也增加內在張力。",
        strengths: "面對變化時，可能迅速抓到需要處理的重點。", cautions: "精神較緊繃時，需要刻意保留緩衝與休息。")
    case .diKong:
      .init(
        keywords: ["抽離", "想像", "落差"], summary: "地空可能帶來抽離既有框架、想像不同可能與感受落差的傾向。",
        strengths: "可能較能跳出固定方式，重新看待問題。", cautions: "想法與現實之間，需要安排具體核對。")
    case .diJie:
      .init(
        keywords: ["取捨", "變動", "重整"], summary: "地劫可能帶來資源取捨、變動與重新整理的課題。",
        strengths: "面對改變時，可能逐漸學會辨認真正重要的部分。", cautions: "做取捨前，需要先確認現實條件與可承受範圍。")
    case .luCun:
      .init(
        keywords: ["保存", "累積", "資源"], summary: "祿存可以先理解為重視保存、累積與運用資源的星曜。",
        strengths: "可能願意建立穩定基礎，並珍惜可用資源。", cautions: "重視保有時，也要留意是否不易放手。")
    case .tianMa:
      .init(
        keywords: ["移動", "行動", "變化"], summary: "天馬可以先理解為增加移動、行動與環境變化的星曜。",
        strengths: "可能願意走出熟悉範圍，從行動取得經驗。", cautions: "變動較多時，需要建立可以維持的節奏。")
    }
  }

  static func categoryTitle(for category: StarCategory) -> String {
    switch category {
    case .main: "主要力量"
    case .benefic: "帶來支持的星曜"
    case .malefic: "帶來張力的星曜"
    case .other: "其他影響"
    }
  }
}

private enum PalaceInterpretationSupport {
  static func category(for palaceKind: PalaceKind) -> InterpretationCategory? {
    switch palaceKind {
    case .life: .personality
    case .spouse: .relationships
    case .wealth: .wealth
    case .career: .career
    case .siblings, .children, .health, .travel, .friends, .property, .fortune, .parents:
      nil
    }
  }
}

struct PalaceQuestionSuggestionBuilder: Sendable {
  func make(
    palaceKind: PalaceKind,
    mainStars: [Star],
    facts: [ChartFact],
    seeds: [InterpretationSeed]
  ) -> [String] {
    let learning = ChartLearningCatalog.palace(palaceKind)
    let validFactIDs = Set(facts.map(\.id))
    let starFactIDs = Set(mainStars.map { "natal.star.\($0.rawValue).palace" })
    let supportedCategory = PalaceInterpretationSupport.category(for: palaceKind)
    let hasSupportedMeaning = seeds.contains { seed in
      seed.category == supportedCategory
        && !seed.evidenceFactIDs.isEmpty
        && seed.evidenceFactIDs.allSatisfy(validFactIDs.contains)
        && seed.evidenceFactIDs.contains(where: starFactIDs.contains)
    }

    if hasSupportedMeaning {
      return [
        "關於\(learning.focusTitle)，我有哪些值得自我觀察的傾向？",
        "\(learning.relatedLabel)有哪些可能值得留意的地方？",
        "這些說法有哪些已驗證的命盤依據？",
      ]
    }

    return [
      "關於\(learning.focusTitle)，目前可以確認哪些盤面事實？",
      "這個宮位目前哪些內容只能確認位置，還不能進一步解讀？",
      "請區分盤面事實與解讀，說明\(palaceKind.displayName)目前能回答到什麼範圍。",
    ]
  }
}

struct PalaceLearningSummaryBuilder: Sendable {
  func make(
    palaceKind: PalaceKind,
    mainStars: [Star],
    facts: [ChartFact],
    seeds: [InterpretationSeed]
  ) -> String {
    let validFactIDs = Set(facts.map(\.id))
    let mainStarFactIDs = Set(mainStars.map { "natal.star.\($0.rawValue).palace" })
    let supportedCategory = PalaceInterpretationSupport.category(for: palaceKind)
    let meanings =
      seeds
      .filter { seed in
        seed.category == supportedCategory
          && !seed.evidenceFactIDs.isEmpty
          && seed.evidenceFactIDs.allSatisfy(validFactIDs.contains)
          && seed.evidenceFactIDs.contains(where: mainStarFactIDs.contains)
      }
      .map(\.meaning)
      .uniqued()

    if !meanings.isEmpty {
      return meanings.prefix(2).joined(separator: " ")
    }

    let learning = ChartLearningCatalog.palace(palaceKind)
    if mainStars.isEmpty {
      return "本宮沒有主星，會先從\(learning.relatedLabel)與相關宮位一起理解。這不代表這個面向沒有特質。"
    }

    let names = mainStars.map(\.displayName).joined(separator: "、")
    return "本宮的主要星曜是\(names)。現階段先顯示已驗證位置，完整解讀仍需要更多規則資料。"
  }
}

extension Sequence where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}

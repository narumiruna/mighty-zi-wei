import Foundation

/// 只保存書目與可核對定位，不將古籍或待審轉譯當成個人命盤含義。
struct InterpretationSourceRecord: Identifiable, Equatable, Sendable {
  enum Kind: String, Sendable {
    case productRule
    case contract
    case modernTranslation
    case traditionalText

    var title: String {
      switch self {
      case .productRule: "現行產品語句"
      case .contract: "App 引用契約"
      case .modernTranslation: "現代編輯轉譯・待審"
      case .traditionalText: "古籍文本定位"
      }
    }
  }

  let id: String
  let kind: Kind
  let title: String
  let repositoryPath: String
  let locator: String
  let revision: String?
  let scope: String
  let externalURL: URL?

  private static let references = "skills/interpreting-ziwei-natal-chart/references/"
  private static let interpretation = "apps/ios/MightyZiWei/Interpretation/"

  static let builtIn: [Self] = common + starReferences

  private static let common: [Self] = [
    Self(
      id: "product.seed-builder", kind: .productRule,
      title: "本機基本解讀產生器",
      repositoryPath: interpretation + "InterpretationSeedBuilder.swift",
      locator: "InterpretationSeedBuilder：baselineSeeds、meanings、category(for:)",
      revision: "解讀內容版本 1",
      scope: "記錄目前使用的五個 baseline 與十四主星分類語句，不表示已經命理專家審閱。",
      externalURL: nil
    ),
    Self(
      id: "contract.validator", kind: .contract,
      title: "解讀引用驗證",
      repositoryPath: interpretation + "InterpretationValidator.swift",
      locator: "InterpretationValidator.validate(sections:facts:seeds:)",
      revision: "解讀內容版本 1",
      scope: "驗證格式、分類、有限安全字詞與 seed-fact 引用完整性；不能證明 AI 每句語意或組合因果正確。查到來源不等於當次驗證已通過。",
      externalURL: nil
    ),
    Self(
      id: "editorial.boundaries", kind: .contract,
      title: "產品與來源的權威邊界",
      repositoryPath: references + "product-integration-boundaries.md",
      locator: "尚未完成的語意保證、可安全宣稱的範圍",
      revision: nil,
      scope: "盤面 facts 只能證明位置或關係；現行產品規則、古籍存在、現代轉譯與專家審閱是不同狀態。",
      externalURL: nil
    ),
  ]

  private static let starReferences: [Self] = {
    let chapters: [(Star, String)] = [
      (.ziWei, "問紫微所主若何？"), (.tianJi, "問天機所主如何？"),
      (.taiYang, "問太陽所主若何？"), (.wuQu, "問武曲星所主為何？"),
      (.tianTong, "問天同星所主若何？"), (.lianZhen, "問廉貞所主若何？"),
      (.tianFu, "問天府所主若何？"), (.taiYin, "問太陰星所主若何？"),
      (.tanLang, "問貪狼所主若何？"), (.juMen, "問巨門所主若何？"),
      (.tianXiang, "問天相星所主若何？"), (.tianLiang, "問天梁星所主若何？"),
      (.qiSha, "問七殺星所主若何？"), (.poJun, "問破軍所主若何？"),
    ]
    return chapters.flatMap { star, chapter in
      [
        Self(
          id: "translation.star.\(star.rawValue)", kind: .modernTranslation,
          title: "\(star.displayName)的現代語句整理",
          repositoryPath: references + "modern-functional-language.md",
          locator: "十四主星 > \(star.displayName)；modern.star.\(star.rawValue)",
          revision: nil,
          scope: "編輯整理仍待審，擴寫不是新的 seed，也不是古籍逐字翻譯；個人解讀仍以 builder 原始 meaning 為限。",
          externalURL: nil
        ),
        Self(
          id: "traditional.star.\(star.rawValue)", kind: .traditionalText,
          title: "《紫微斗數全書》卷一・\(star.displayName)",
          repositoryPath: references + "sources/quanshu-volume-1-star-dialogues.md",
          locator: "諸星問答論 > \(chapter)",
          revision: "維基文庫 oldid=7913704；repository 快照查核日 2026-08-24",
          scope: "repository 收錄此章節，只證明歷史文本存在，不證明此 seed 是原文直譯或已獲實證；作者、版本歸屬與轉錄仍待校勘，未提供紙本頁碼。",
          externalURL: URL(
            string: "https://zh.wikisource.org/w/index.php?title=紫微鬥數全書/卷一&oldid=7913704"
          )
        ),
      ]
    }
  }()
}

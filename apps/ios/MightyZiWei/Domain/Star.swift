import Foundation

public enum Star: String, CaseIterable, Codable, Sendable {
  // 十四主星
  case ziWei, tianJi, taiYang, wuQu, tianTong, lianZhen
  case tianFu, taiYin, tanLang, juMen, tianXiang, tianLiang, qiSha, poJun
  // 六吉
  case zuoFu, youBi, wenChang, wenQu, tianKui, tianYue
  // 六煞
  case qingYang, tuoLuo, huoXing, lingXing, diKong, diJie
  // 祿存、天馬
  case luCun, tianMa

  public var displayName: String {
    switch self {
    case .ziWei: "紫微"
    case .tianJi: "天機"
    case .taiYang: "太陽"
    case .wuQu: "武曲"
    case .tianTong: "天同"
    case .lianZhen: "廉貞"
    case .tianFu: "天府"
    case .taiYin: "太陰"
    case .tanLang: "貪狼"
    case .juMen: "巨門"
    case .tianXiang: "天相"
    case .tianLiang: "天梁"
    case .qiSha: "七殺"
    case .poJun: "破軍"
    case .zuoFu: "左輔"
    case .youBi: "右弼"
    case .wenChang: "文昌"
    case .wenQu: "文曲"
    case .tianKui: "天魁"
    case .tianYue: "天鉞"
    case .qingYang: "擎羊"
    case .tuoLuo: "陀羅"
    case .huoXing: "火星"
    case .lingXing: "鈴星"
    case .diKong: "地空"
    case .diJie: "地劫"
    case .luCun: "祿存"
    case .tianMa: "天馬"
    }
  }

  public var category: StarCategory {
    switch self {
    case .ziWei, .tianJi, .taiYang, .wuQu, .tianTong, .lianZhen,
      .tianFu, .taiYin, .tanLang, .juMen, .tianXiang, .tianLiang, .qiSha, .poJun:
      .main
    case .zuoFu, .youBi, .wenChang, .wenQu, .tianKui, .tianYue:
      .benefic
    case .qingYang, .tuoLuo, .huoXing, .lingXing, .diKong, .diJie:
      .malefic
    case .luCun, .tianMa:
      .other
    }
  }
}

public enum StarCategory: String, Codable, Sendable {
  case main
  case benefic
  case malefic
  case other
}

public struct StarPlacement: Identifiable, Codable, Sendable, Hashable {
  public var id: Star { star }
  public let star: Star
  public let branch: EarthlyBranch
  public let palace: PalaceKind

  public init(star: Star, branch: EarthlyBranch, palace: PalaceKind) {
    self.star = star
    self.branch = branch
    self.palace = palace
  }
}

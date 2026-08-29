import Foundation

public enum HeavenlyStem: Int, CaseIterable, Codable, Sendable {
  case jia, yi, bing, ding, wu, ji, geng, xin, ren, gui

  public var displayName: String {
    ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"][rawValue]
  }
}

public enum EarthlyBranch: Int, CaseIterable, Codable, Sendable {
  case zi, chou, yin, mao, chen, si, wu, wei, shen, you, xu, hai

  public var displayName: String {
    ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"][rawValue]
  }
}

public struct StemBranch: Codable, Sendable, Hashable {
  public let stem: HeavenlyStem
  public let branch: EarthlyBranch

  public init(stem: HeavenlyStem, branch: EarthlyBranch) {
    self.stem = stem
    self.branch = branch
  }

  public var displayName: String { stem.displayName + branch.displayName }
}

public struct LunarDate: Codable, Sendable, Hashable {
  /// Foundation Chinese Calendar 的六十甲子年序，1...60。
  public let cyclicalYear: Int
  public let month: Int
  public let day: Int
  public let isLeapMonth: Bool

  public init(cyclicalYear: Int, month: Int, day: Int, isLeapMonth: Bool) {
    self.cyclicalYear = cyclicalYear
    self.month = month
    self.day = day
    self.isLeapMonth = isLeapMonth
  }

  public var yearStem: HeavenlyStem {
    HeavenlyStem(rawValue: (cyclicalYear - 1) % 10)!
  }

  public var yearBranch: EarthlyBranch {
    EarthlyBranch(rawValue: (cyclicalYear - 1) % 12)!
  }

  /// v1 採「閏月作下月」。
  public var chartMonth: Int { isLeapMonth ? month + 1 : month }
}

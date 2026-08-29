import Foundation

public struct RuleSetIdentity: Codable, Sendable, Hashable {
  public let id: String
  public let version: Int

  public init(id: String, version: Int) {
    self.id = id
    self.version = version
  }

  public static let taiwanTraditionalSanheV1 = RuleSetIdentity(
    id: "taiwan-traditional-sanhe",
    version: 1
  )
}

public struct ZiWeiChart: Codable, Sendable {
  public let ruleSet: RuleSetIdentity
  public let birthProfile: BirthProfile
  public let lunarDate: LunarDate
  public let hourBranch: EarthlyBranch
  public let fiveElementBureau: FiveElementBureau
  public let palaces: [ChartPalace]
  public let stars: [StarPlacement]
  public let transformations: [Transformation]
  public let relations: [PalaceRelation]

  public init(
    ruleSet: RuleSetIdentity,
    birthProfile: BirthProfile,
    lunarDate: LunarDate,
    hourBranch: EarthlyBranch,
    fiveElementBureau: FiveElementBureau,
    palaces: [ChartPalace],
    stars: [StarPlacement],
    transformations: [Transformation],
    relations: [PalaceRelation]
  ) {
    self.ruleSet = ruleSet
    self.birthProfile = birthProfile
    self.lunarDate = lunarDate
    self.hourBranch = hourBranch
    self.fiveElementBureau = fiveElementBureau
    self.palaces = palaces
    self.stars = stars
    self.transformations = transformations
    self.relations = relations
  }

  public var lifePalace: ChartPalace { palace(.life) }

  public var bodyPalace: ChartPalace {
    palaces.first(where: \.isBodyPalace)!
  }

  public func palace(_ kind: PalaceKind) -> ChartPalace {
    palaces.first { $0.kind == kind }!
  }

  public func placement(of star: Star) -> StarPlacement {
    stars.first { $0.star == star }!
  }

  public func relation(of palace: PalaceKind) -> PalaceRelation {
    relations.first { $0.palace == palace }!
  }
}

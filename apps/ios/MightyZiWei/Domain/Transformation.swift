import Foundation

public enum TransformationKind: String, CaseIterable, Codable, Sendable {
  case lu
  case quan
  case ke
  case ji

  public var displayName: String {
    switch self {
    case .lu: "化祿"
    case .quan: "化權"
    case .ke: "化科"
    case .ji: "化忌"
    }
  }
}

public struct Transformation: Identifiable, Codable, Sendable, Hashable {
  public var id: TransformationKind { kind }
  public let kind: TransformationKind
  public let star: Star
  public let branch: EarthlyBranch
  public let palace: PalaceKind

  public init(kind: TransformationKind, star: Star, branch: EarthlyBranch, palace: PalaceKind) {
    self.kind = kind
    self.star = star
    self.branch = branch
    self.palace = palace
  }
}

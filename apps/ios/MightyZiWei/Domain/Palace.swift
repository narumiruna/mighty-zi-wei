import Foundation

public enum PalaceKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case life
    case siblings
    case spouse
    case children
    case wealth
    case health
    case travel
    case friends
    case career
    case property
    case fortune
    case parents

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .life: "命宮"
        case .siblings: "兄弟宮"
        case .spouse: "夫妻宮"
        case .children: "子女宮"
        case .wealth: "財帛宮"
        case .health: "疾厄宮"
        case .travel: "遷移宮"
        case .friends: "僕役宮"
        case .career: "官祿宮"
        case .property: "田宅宮"
        case .fortune: "福德宮"
        case .parents: "父母宮"
        }
    }
}

public struct ChartPalace: Identifiable, Codable, Sendable, Hashable {
    public var id: PalaceKind { kind }
    public let kind: PalaceKind
    public let stemBranch: StemBranch
    public let isBodyPalace: Bool

    public init(kind: PalaceKind, stemBranch: StemBranch, isBodyPalace: Bool) {
        self.kind = kind
        self.stemBranch = stemBranch
        self.isBodyPalace = isBodyPalace
    }
}

public enum FiveElementBureau: String, Codable, Sendable {
    case woodThree
    case metalFour
    case waterTwo
    case fireSix
    case earthFive

    public var number: Int {
        switch self {
        case .woodThree: 3
        case .metalFour: 4
        case .waterTwo: 2
        case .fireSix: 6
        case .earthFive: 5
        }
    }

    public var displayName: String {
        switch self {
        case .woodThree: "木三局"
        case .metalFour: "金四局"
        case .waterTwo: "水二局"
        case .fireSix: "火六局"
        case .earthFive: "土五局"
        }
    }
}

public struct PalaceRelation: Codable, Sendable, Hashable {
    public let palace: PalaceKind
    public let trines: [PalaceKind]
    public let opposite: PalaceKind

    public init(palace: PalaceKind, trines: [PalaceKind], opposite: PalaceKind) {
        self.palace = palace
        self.trines = trines
        self.opposite = opposite
    }
}

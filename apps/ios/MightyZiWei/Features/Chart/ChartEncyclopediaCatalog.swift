import Foundation

enum ChartEncyclopediaCategory: String, CaseIterable, Sendable {
    case star
    case palace
    case transformation
    case sanFangSiZheng
}

enum ChartEncyclopediaReference: Hashable, Sendable {
    case star(Star)
    case palace(PalaceKind)
    case transformation(TransformationKind)
    case sanFangSiZheng
}

struct ChartEncyclopediaEntry: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: ChartEncyclopediaCategory
    let reference: ChartEncyclopediaReference
    let ruleSetSection: String
}

enum ChartEncyclopediaCatalog {
    static let starEntries: [ChartEncyclopediaEntry] = Star.allCases.map { star in
        ChartEncyclopediaEntry(
            id: "star.\(star.rawValue)",
            title: star.displayName,
            category: .star,
            reference: .star(star),
            ruleSetSection: star.category == .main
                ? "RULESET.md 第 10 節〈十四主星〉"
                : "RULESET.md 第 11 節〈六吉、六煞、祿存與天馬〉"
        )
    }

    static let palaceEntries: [ChartEncyclopediaEntry] = PalaceKind.allCases.map { palace in
        ChartEncyclopediaEntry(
            id: "palace.\(palace.rawValue)",
            title: palace.displayName,
            category: .palace,
            reference: .palace(palace),
            ruleSetSection: "RULESET.md 第 7 節〈命宮、身宮與十二宮〉"
        )
    }

    static let transformationEntries: [ChartEncyclopediaEntry] = TransformationKind.allCases.map { transformation in
        ChartEncyclopediaEntry(
            id: "transformation.\(transformation.rawValue)",
            title: transformation.displayName,
            category: .transformation,
            reference: .transformation(transformation),
            ruleSetSection: "RULESET.md 第 12 節〈生年四化〉"
        )
    }

    static let sanFangSiZhengEntry = ChartEncyclopediaEntry(
        id: "relationship.sanFangSiZheng",
        title: "三方四正",
        category: .sanFangSiZheng,
        reference: .sanFangSiZheng,
        ruleSetSection: "RULESET.md 第 13 節〈三方四正〉"
    )

    static let allEntries: [ChartEncyclopediaEntry] =
        starEntries
        + palaceEntries
        + transformationEntries
        + [sanFangSiZhengEntry]
}

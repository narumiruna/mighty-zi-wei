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
    static let currentProductLanguageSource =
        "ChartLearningContent.swift（現行產品文案，待專家與內容安全審核）"

    let id: String
    let title: String
    let category: ChartEncyclopediaCategory
    let reference: ChartEncyclopediaReference
    let placementRuleSection: String
    let explanatorySource: String?
}

enum ChartEncyclopediaCatalog {
    static let starEntries: [ChartEncyclopediaEntry] = Star.allCases.map { star in
        ChartEncyclopediaEntry(
            id: "star.\(star.rawValue)",
            title: star.displayName,
            category: .star,
            reference: .star(star),
            placementRuleSection: star.category == .main
                ? "RULESET.md 第 10 節〈十四主星〉"
                : "RULESET.md 第 11 節〈六吉、六煞、祿存與天馬〉",
            explanatorySource: ChartEncyclopediaEntry.currentProductLanguageSource
        )
    }

    static let palaceEntries: [ChartEncyclopediaEntry] = PalaceKind.allCases.map { palace in
        ChartEncyclopediaEntry(
            id: "palace.\(palace.rawValue)",
            title: palace.displayName,
            category: .palace,
            reference: .palace(palace),
            placementRuleSection: "RULESET.md 第 7 節〈命宮、身宮與十二宮〉",
            explanatorySource: ChartEncyclopediaEntry.currentProductLanguageSource
        )
    }

    static let transformationEntries: [ChartEncyclopediaEntry] = TransformationKind.allCases.map { transformation in
        ChartEncyclopediaEntry(
            id: "transformation.\(transformation.rawValue)",
            title: transformation.displayName,
            category: .transformation,
            reference: .transformation(transformation),
            placementRuleSection: "RULESET.md 第 12 節〈生年四化〉",
            explanatorySource: nil
        )
    }

    static let sanFangSiZhengEntry = ChartEncyclopediaEntry(
        id: "relationship.sanFangSiZheng",
        title: "三方四正",
        category: .sanFangSiZheng,
        reference: .sanFangSiZheng,
        placementRuleSection: "RULESET.md 第 13 節〈三方四正〉",
        explanatorySource: nil
    )

    static let allEntries: [ChartEncyclopediaEntry] =
        starEntries
        + palaceEntries
        + transformationEntries
        + [sanFangSiZhengEntry]
}

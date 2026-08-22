import Foundation

struct ChartFactBuilder: Sendable {
    func makeFacts(from chart: ZiWeiChart) -> [ChartFact] {
        var facts: [ChartFact] = [bureauFact(chart)]
        facts.append(contentsOf: chart.palaces.map(palaceFact))
        facts.append(bodyPalaceFact(chart))
        facts.append(contentsOf: chart.stars.map(starFact))
        facts.append(contentsOf: chart.transformations.map(transformationFact))
        facts.append(contentsOf: chart.relations.map(relationFact))
        return facts
    }

    private func bureauFact(_ chart: ZiWeiChart) -> ChartFact {
        ChartFact(
            id: "natal.bureau",
            category: .calendar,
            subject: .init(kind: "chart", identifier: "natal"),
            value: .init(kind: "bureau", identifier: chart.fiveElementBureau.rawValue),
            displayText: "命盤為\(chart.fiveElementBureau.displayName)。"
        )
    }

    private func palaceFact(_ palace: ChartPalace) -> ChartFact {
        ChartFact(
            id: "natal.palace.\(palace.kind.rawValue).branch",
            category: .palace,
            subject: .init(kind: "palace", identifier: palace.kind.rawValue),
            value: .init(kind: "branch", identifier: branchID(palace.stemBranch.branch)),
            displayText: "\(palace.kind.displayName)位於\(palace.stemBranch.branch.displayName)宮，宮干支為\(palace.stemBranch.displayName)。"
        )
    }

    private func bodyPalaceFact(_ chart: ZiWeiChart) -> ChartFact {
        let palace = chart.bodyPalace
        return ChartFact(
            id: "natal.palace.body.branch",
            category: .palace,
            subject: .init(kind: "palace", identifier: "body"),
            value: .init(kind: "branch", identifier: branchID(palace.stemBranch.branch)),
            displayText: "身宮位於\(palace.kind.displayName)的\(palace.stemBranch.branch.displayName)宮。"
        )
    }

    private func starFact(_ placement: StarPlacement) -> ChartFact {
        ChartFact(
            id: "natal.star.\(placement.star.rawValue).palace",
            category: .star,
            subject: .init(kind: "star", identifier: placement.star.rawValue),
            value: .init(kind: "palace", identifier: placement.palace.rawValue),
            displayText: "\(placement.star.displayName)位於\(placement.palace.displayName)。"
        )
    }

    private func transformationFact(_ transformation: Transformation) -> ChartFact {
        ChartFact(
            id: "natal.transformation.\(transformation.kind.rawValue).star",
            category: .transformation,
            subject: .init(kind: "transformation", identifier: transformation.kind.rawValue),
            value: .init(kind: "star", identifier: transformation.star.rawValue),
            displayText: "\(transformation.star.displayName)\(transformation.kind.displayName)，位於\(transformation.palace.displayName)。"
        )
    }

    private func relationFact(_ relation: PalaceRelation) -> ChartFact {
        let identifiers = relation.trines.map(\.rawValue) + [relation.opposite.rawValue]
        let names = relation.trines.map(\.displayName) + [relation.opposite.displayName]
        return ChartFact(
            id: "natal.palace.\(relation.palace.rawValue).sanFangSiZheng",
            category: .relationship,
            subject: .init(kind: "palace", identifier: relation.palace.rawValue),
            value: .init(kind: "palaceSet", identifier: identifiers.joined(separator: ".")),
            displayText: "\(relation.palace.displayName)的三方四正包含\(names.joined(separator: "、"))。"
        )
    }

    private func branchID(_ branch: EarthlyBranch) -> String {
        ["zi", "chou", "yin", "mao", "chen", "si", "wu", "wei", "shen", "you", "xu", "hai"][branch.rawValue]
    }
}

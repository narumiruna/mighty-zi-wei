import Foundation

struct InteractionPalaceFacts: Equatable, Sendable {
    let palace: ChartPalace
    let mainStars: [StarPlacement]
}

struct InteractionPalaceComparison: Equatable, Sendable {
    let palaceKind: PalaceKind
    let firstChart: InteractionPalaceFacts?
    let secondChart: InteractionPalaceFacts?
}

struct DualChartInteractionReference: Equatable, Sendable {
    let comparisons: [InteractionPalaceComparison]
    let limitations: [String]

    var hasCompleteComparedPalaceFacts: Bool {
        comparisons.allSatisfy { $0.firstChart != nil && $0.secondChart != nil }
    }
}

struct DualChartInteractionReferenceBuilder: Sendable {
    static let comparedPalaces: [PalaceKind] = [.life, .spouse, .travel, .friends]

    func make(
        firstChart: ZiWeiChart?,
        secondChart: ZiWeiChart?
    ) -> DualChartInteractionReference {
        let comparisons = Self.comparedPalaces.map { palaceKind in
            InteractionPalaceComparison(
                palaceKind: palaceKind,
                firstChart: facts(for: palaceKind, in: firstChart),
                secondChart: facts(for: palaceKind, in: secondChart)
            )
        }

        var limitations = [
            "僅並列命宮、夫妻宮、遷移宮與僕役宮的宮位及十四主星位置事實。",
            "這些盤面事實資料不足，不能用來判定相容性、適配度或關係結果。"
        ]
        if firstChart == nil {
            limitations.append("缺少第一張命盤資料。")
        }
        if secondChart == nil {
            limitations.append("缺少第二張命盤資料。")
        }

        let missingFirst = missingPalaces(in: firstChart)
        if !missingFirst.isEmpty {
            limitations.append("第一張命盤缺少：\(palaceNames(missingFirst))。")
        }
        let missingSecond = missingPalaces(in: secondChart)
        if !missingSecond.isEmpty {
            limitations.append("第二張命盤缺少：\(palaceNames(missingSecond))。")
        }

        return DualChartInteractionReference(
            comparisons: comparisons,
            limitations: limitations
        )
    }

    private func facts(
        for palaceKind: PalaceKind,
        in chart: ZiWeiChart?
    ) -> InteractionPalaceFacts? {
        guard let chart,
              let palace = chart.palaces.first(where: { $0.kind == palaceKind }) else {
            return nil
        }
        let mainStars = Star.allCases
            .filter { $0.category == .main }
            .compactMap { star in
                chart.stars.first { $0.star == star && $0.palace == palaceKind }
            }
        return InteractionPalaceFacts(palace: palace, mainStars: mainStars)
    }

    private func missingPalaces(in chart: ZiWeiChart?) -> [PalaceKind] {
        guard let chart else { return [] }
        let available = Set(chart.palaces.map(\.kind))
        return Self.comparedPalaces.filter { !available.contains($0) }
    }

    private func palaceNames(_ palaces: [PalaceKind]) -> String {
        palaces.map(\.displayName).joined(separator: "、")
    }
}

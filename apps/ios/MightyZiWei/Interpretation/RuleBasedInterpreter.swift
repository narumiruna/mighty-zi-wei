import Foundation

struct RuleBasedInterpreter: Sendable {
    func interpret(
        facts: [ChartFact],
        seeds: [InterpretationSeed]
    ) -> ChartInterpretation {
        let validFactIDs = Set(facts.map(\.id))
        let factsByID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
        let sections = InterpretationCategory.allCases.map { category in
            let categorySeeds = seeds.filter { seed in
                seed.category == category
                    && !seed.evidenceFactIDs.isEmpty
                    && seed.evidenceFactIDs.allSatisfy(validFactIDs.contains)
            }
            let personalizedSeeds = categorySeeds.filter { !$0.id.hasSuffix(".baseline") }
            let selectedSeeds = personalizedSeeds.isEmpty ? categorySeeds : personalizedSeeds
            let evidence = selectedSeeds
                .flatMap(\.evidenceFactIDs)
                .uniqued()

            return InterpretationSection(
                id: "fallback.\(category.rawValue)",
                category: category,
                title: category.title,
                content: content(
                    for: category,
                    seeds: selectedSeeds,
                    factsByID: factsByID
                ),
                evidenceSeedIDs: selectedSeeds.map(\.id),
                evidenceFactIDs: evidence
            )
        }
        return ChartInterpretation(sections: sections, source: .deterministic)
    }

    private func content(
        for category: InterpretationCategory,
        seeds: [InterpretationSeed],
        factsByID: [String: ChartFact]
    ) -> String {
        let meanings = seeds.map { seed in
            let facts = seed.evidenceFactIDs.compactMap { factsByID[$0]?.displayText }
            let context = facts.joined(separator: " ")
            return context.isEmpty ? seed.meaning : "\(context)\(seed.meaning)"
        }.uniqued()
        guard let leadingMeaning = meanings.first else {
            return "目前沒有足夠的核准解讀線索。這一區先不做個人化判斷。"
        }

        var paragraphs = [leadingMeaning]
        let supportingMeanings = Array(meanings.dropFirst())
        if !supportingMeanings.isEmpty {
            let supportingList = supportingMeanings
                .map { "• \($0)" }
                .joined(separator: "\n")
            paragraphs.append("其他已驗證線索：\n\(supportingList)")
        }
        paragraphs.append("拿生活來核對：\(category.reflectionQuestion)")
        return paragraphs.joined(separator: "\n\n")
    }
}

private extension InterpretationCategory {
    var reflectionQuestion: String {
        switch self {
        case .overview:
            "回想最近一次重要選擇，哪個傾向最明顯？哪個只在壓力下出現？"
        case .personality:
            "遇到沒有標準答案的事情時，你通常先形成判斷、蒐集資訊，還是觀察他人反應？"
        case .career:
            "什麼樣的責任、合作方式與成果形式，最容易讓你持續投入？"
        case .wealth:
            "分配金錢、時間或注意力時，你最常優先保留安全、彈性，還是可見成果？"
        case .relationships:
            "關係出現差異時，你通常先說清楚、先照顧氣氛，還是先拉開距離整理？"
        }
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

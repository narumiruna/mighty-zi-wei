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
        paragraphs.append(
            "拿生活來核對：上面的觀察和你近期哪一次真實經驗最接近？哪一次不符合？"
        )
        return paragraphs.joined(separator: "\n\n")
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

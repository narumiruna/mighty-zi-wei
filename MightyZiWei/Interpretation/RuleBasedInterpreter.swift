import Foundation

struct RuleBasedInterpreter: Sendable {
    func interpret(
        facts: [ChartFact],
        seeds: [InterpretationSeed]
    ) -> ChartInterpretation {
        let validFactIDs = Set(facts.map(\.id))
        let sections = InterpretationCategory.allCases.map { category in
            let categorySeeds = seeds.filter { $0.category == category }
            let meanings = categorySeeds.map(\.meaning).uniqued()
            let matchedEvidence = categorySeeds
                .flatMap(\.evidenceFactIDs)
                .filter(validFactIDs.contains)
                .uniqued()
            let evidence = matchedEvidence.isEmpty
                ? facts.prefix(1).map(\.id)
                : matchedEvidence

            return InterpretationSection(
                id: "fallback.\(category.rawValue)",
                category: category,
                title: category.title,
                content: meanings.isEmpty
                    ? "目前沒有足夠的規則資料形成這一類解讀。你可以先把它留作自我觀察的空白。"
                    : meanings.joined(separator: "\n\n"),
                evidenceFactIDs: evidence
            )
        }
        return ChartInterpretation(sections: sections, source: .deterministic)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

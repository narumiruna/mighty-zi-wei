import Foundation

struct InterpretationSeedBuilder: Sendable {
    private struct StarMeaning: Sendable {
        let overview: String
        let personality: String
        let career: String
        let wealth: String
        let relationships: String
    }

    private let meanings: [String: StarMeaning] = [
        "ziWei": .init(overview: "你可能重視整體方向與自主掌握。", personality: "你可能傾向先形成自己的判斷，再決定如何推進。", career: "工作上可能喜歡統整資源並承擔方向性的責任。", wealth: "處理資源時可能先看長期配置與整體效益。", relationships: "在人際中可能自然承擔主導或協調角色。"),
        "tianJi": .init(overview: "你的命盤可能帶有觀察、規劃與調整的傾向。", personality: "你可能習慣多想幾步，也容易注意環境的細微變化。", career: "工作上可能適合需要分析、規劃與彈性調整的情境。", wealth: "財務安排可能偏好多比較方案，再逐步調整。", relationships: "你可能透過理解對方想法來建立互動。"),
        "taiYang": .init(overview: "你可能重視坦率、責任感與對外連結。", personality: "你可能願意清楚表達立場，也在意自己能否帶來幫助。", career: "公開協作、服務他人或承擔責任的工作可能較能引起投入感。", wealth: "你可能願意把資源用在可見的成果或共同目標。", relationships: "你可能偏好直接、明朗而有共同方向的相處方式。"),
        "wuQu": .init(overview: "你可能重視實際成果、效率與資源秩序。", personality: "做決定時，你可能較願意面對現實條件並採取具體行動。", career: "明確目標、責任與可衡量成果可能讓你更能發揮。", wealth: "你可能在意資源的可控性，並偏好務實的安排。", relationships: "你可能用可靠行動而不是很多話來表達在意。"),
        "tianTong": .init(overview: "你可能重視舒適感、和諧與生活品質。", personality: "你可能願意保持柔軟，也傾向避開不必要的衝突。", career: "友善的合作環境與有餘裕的節奏可能更能支持你的表現。", wealth: "財務選擇可能同時考慮安全感與生活感受。", relationships: "你可能重視輕鬆、包容與彼此照顧的互動。"),
        "lianZhen": .init(overview: "你可能在意原則、界線與事情背後的規則。", personality: "你可能對人事細節較敏銳，也會反覆衡量界線。", career: "需要判斷標準、協調規範或處理複雜關係的工作可能引起你的投入。", wealth: "你可能希望資源使用有清楚原則，避免模糊不明。", relationships: "你可能很在意承諾、分寸與互相尊重。"),
        "tianFu": .init(overview: "你可能重視穩定、承接與資源保存。", personality: "你可能傾向先建立可靠基礎，再逐步擴張。", career: "管理、維持系統與照顧長期運作可能是你的可用能力。", wealth: "你可能偏好保留餘裕，並以穩定累積來看待資源。", relationships: "你可能以穩定陪伴與實際支持建立信任。"),
        "taiYin": .init(overview: "你可能帶有細膩、內省與重視感受的傾向。", personality: "你可能需要安靜空間整理情緒與想法。", career: "需要耐心、審美、研究或幕後整理的工作可能較合你的節奏。", wealth: "你可能重視安全感，也願意以細緻方式管理日常資源。", relationships: "你可能對互動氣氛敏感，並重視被理解的感受。"),
        "tanLang": .init(overview: "你可能對新鮮事、人際互動與多元體驗保持好奇。", personality: "你可能有探索欲，也容易被有趣的人事物吸引。", career: "需要社交、創意或開拓新機會的工作可能帶來動力。", wealth: "你可能願意為體驗與成長投入資源，需要留意選擇過多時的分散。", relationships: "你可能重視互動火花與共同體驗。"),
        "juMen": .init(overview: "你可能透過提問、辨析與表達來理解世界。", personality: "你可能不輕易接受表面答案，會想把疑問說清楚。", career: "研究、溝通、談判或釐清問題的工作可能讓你發揮。", wealth: "做資源決策時，你可能特別重視資訊是否充分。", relationships: "你可能需要能坦白討論差異的關係，也要留意語氣造成的距離。"),
        "tianXiang": .init(overview: "你可能重視平衡、合作與恰當的角色分工。", personality: "你可能願意先觀察各方需要，再尋找較公平的作法。", career: "協調、支援與維持品質可能是你在團隊中的優勢。", wealth: "你可能傾向在公平與可持續的前提下配置資源。", relationships: "你可能重視互相尊重、禮貌與穩定合作。"),
        "tianLiang": .init(overview: "你可能重視原則、照顧與長期價值。", personality: "你可能願意替別人多想一步，也在意事情是否站得住腳。", career: "顧問、教育、守護品質或傳承經驗的角色可能帶來意義感。", wealth: "你可能把資源安全與長期責任看得比短期刺激重要。", relationships: "你可能自然扮演傾聽或照顧者，但也需要保留自己的界線。"),
        "qiSha": .init(overview: "你可能具有面對挑戰、快速決斷與開路的傾向。", personality: "遇到壓力時，你可能寧可直接行動，再從結果調整。", career: "高自主、需要決斷或處理困難任務的情境可能激發你的能力。", wealth: "資源決策可能較果斷，適合先設定可承受的界線。", relationships: "你可能重視真誠與效率，也需要為彼此保留緩衝。"),
        "poJun": .init(overview: "你可能對改變、重整與突破既有方式較有感受。", personality: "當舊方法失去作用時，你可能願意推倒重來。", career: "轉型、創新或處理變動的工作可能讓你看見自己的韌性。", wealth: "資源狀態可能伴隨調整需求，清楚區分必要改變與一時衝動會有幫助。", relationships: "你可能需要關係保有成長與更新空間。")
    ]

    func makeSeeds(from facts: [ChartFact]) -> [InterpretationSeed] {
        let factsByID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
        var seeds = baselineSeeds(factsByID: factsByID)

        for fact in facts where fact.subject.kind == "star" && fact.value.kind == "palace" {
            guard let meaning = meanings[fact.subject.identifier],
                  let category = category(for: fact.value.identifier) else {
                continue
            }
            seeds.append(
                InterpretationSeed(
                    id: "seed.\(category.rawValue).\(fact.subject.identifier).\(fact.value.identifier)",
                    category: category,
                    meaning: text(from: meaning, category: category),
                    evidenceFactIDs: [fact.id]
                )
            )
        }

        return seeds
    }

    private func baselineSeeds(factsByID: [String: ChartFact]) -> [InterpretationSeed] {
        let definitions: [(InterpretationCategory, String, String)] = [
            (.overview, "natal.bureau", "這張命盤可以視為多組性格與選擇傾向的交會，而不是固定的人生結論。"),
            (.personality, "natal.palace.life.branch", "命宮提供一個觀察自我反應方式的角度，適合和真實生活經驗相互核對。"),
            (.career, "natal.palace.career.branch", "官祿宮可用來反思你對工作角色與投入方式的偏好，但不限制實際職業選擇。"),
            (.wealth, "natal.palace.wealth.branch", "財帛宮適合用來觀察資源安排傾向，不構成任何投資建議。"),
            (.relationships, "natal.palace.spouse.branch", "夫妻宮提供一個觀察親密互動需求的角度，關係仍取決於雙方溝通與選擇。")
        ]

        return definitions.compactMap { category, factID, meaning in
            guard factsByID[factID] != nil else { return nil }
            return InterpretationSeed(
                id: "seed.\(category.rawValue).baseline",
                category: category,
                meaning: meaning,
                evidenceFactIDs: [factID]
            )
        }
    }

    private func category(for palaceID: String) -> InterpretationCategory? {
        switch palaceID {
        case "life", "fortune": .personality
        case "career", "travel": .career
        case "wealth", "property": .wealth
        case "spouse", "friends", "siblings": .relationships
        default: .overview
        }
    }

    private func text(from meaning: StarMeaning, category: InterpretationCategory) -> String {
        switch category {
        case .overview: meaning.overview
        case .personality: meaning.personality
        case .career: meaning.career
        case .wealth: meaning.wealth
        case .relationships: meaning.relationships
        }
    }
}

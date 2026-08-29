import Foundation

struct ChartFact: Identifiable, Codable, Hashable, Sendable {
    enum Category: String, Codable, Sendable {
        case calendar
        case palace
        case star
        case transformation
        case relationship
    }

    struct Subject: Codable, Hashable, Sendable {
        let kind: String
        let identifier: String
    }

    struct Value: Codable, Hashable, Sendable {
        let kind: String
        let identifier: String
    }

    let id: String
    let category: Category
    let subject: Subject
    let value: Value
    let displayText: String
}

enum InterpretationCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case overview
    case personality
    case career
    case wealth
    case relationships

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "命盤總覽"
        case .personality: "個性"
        case .career: "工作與事業"
        case .wealth: "財務傾向"
        case .relationships: "感情與人際"
        }
    }
}

struct InterpretationSeed: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let category: InterpretationCategory
    let meaning: String
    let evidenceFactIDs: [String]
}

struct InterpretationSection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let category: InterpretationCategory
    let title: String
    let content: String
    let evidenceSeedIDs: [String]
    let evidenceFactIDs: [String]

    init(
        id: String,
        category: InterpretationCategory,
        title: String,
        content: String,
        evidenceSeedIDs: [String] = [],
        evidenceFactIDs: [String]
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.content = content
        self.evidenceSeedIDs = evidenceSeedIDs
        self.evidenceFactIDs = evidenceFactIDs
    }
}

struct ChartInterpretation: Codable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case remoteAI
        case deterministic

        var title: String {
            switch self {
            case .remoteAI: "雲端 AI 整理"
            case .deterministic: "基本解讀"
            }
        }
    }

    let sections: [InterpretationSection]
    let source: Source
}

struct ChartConversationTurn: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let question: String
    let answer: String
    let evidenceSeedIDs: [String]
    let evidenceFactIDs: [String]
    let status: ChartConversationAnswer.Status

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        evidenceSeedIDs: [String] = [],
        evidenceFactIDs: [String],
        status: ChartConversationAnswer.Status = .answered
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.evidenceSeedIDs = evidenceSeedIDs
        self.evidenceFactIDs = evidenceFactIDs
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case question
        case answer
        case evidenceSeedIDs
        case evidenceFactIDs
        case status
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        answer = try container.decode(String.self, forKey: .answer)
        evidenceSeedIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .evidenceSeedIDs
        ) ?? []
        evidenceFactIDs = try container.decode([String].self, forKey: .evidenceFactIDs)
        status = try container.decodeIfPresent(
            ChartConversationAnswer.Status.self,
            forKey: .status
        ) ?? (evidenceFactIDs.isEmpty ? .unsupported : .answered)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encode(answer, forKey: .answer)
        try container.encode(evidenceSeedIDs, forKey: .evidenceSeedIDs)
        try container.encode(evidenceFactIDs, forKey: .evidenceFactIDs)
        try container.encode(status, forKey: .status)
    }
}

struct ChartConversationAnswer: Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case answered
        case unsupported
    }

    let status: Status
    let content: String
    let evidenceSeedIDs: [String]
    let evidenceFactIDs: [String]

    init(
        status: Status,
        content: String,
        evidenceSeedIDs: [String] = [],
        evidenceFactIDs: [String]
    ) {
        self.status = status
        self.content = content
        self.evidenceSeedIDs = evidenceSeedIDs
        self.evidenceFactIDs = evidenceFactIDs
    }
}

struct ChartAssistantChart: Identifiable, Sendable {
    let id: UUID
    let savedChartID: UUID?
    let name: String
    let detail: String
    let facts: [ChartFact]
    let seeds: [InterpretationSeed]

    var isSaved: Bool { savedChartID != nil }
}

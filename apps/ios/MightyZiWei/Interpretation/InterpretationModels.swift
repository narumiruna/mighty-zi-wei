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
    let evidenceFactIDs: [String]
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
    let evidenceFactIDs: [String]

    init(
        id: UUID = UUID(),
        question: String,
        answer: String,
        evidenceFactIDs: [String]
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.evidenceFactIDs = evidenceFactIDs
    }
}

struct ChartConversationAnswer: Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case answered
        case unsupported
    }

    let status: Status
    let content: String
    let evidenceFactIDs: [String]
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

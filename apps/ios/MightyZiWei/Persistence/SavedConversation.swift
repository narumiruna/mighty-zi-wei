import Foundation
import SwiftData

@Model
final class SavedConversation {
    @Attribute(.unique) var id: UUID
    var chartID: UUID?
    var chartName: String
    var chartDetail: String
    var modelIdentifier: String
    var title: String
    var turnsData: Data
    var createdAt: Date
    var updatedAt: Date

    var turns: [ChartConversationTurn] {
        (try? JSONDecoder().decode([ChartConversationTurn].self, from: turnsData)) ?? []
    }

    init(
        id: UUID = UUID(),
        chartID: UUID?,
        chartName: String,
        chartDetail: String,
        modelIdentifier: String,
        title: String,
        turns: [ChartConversationTurn],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.chartID = chartID
        self.chartName = chartName
        self.chartDetail = chartDetail
        self.modelIdentifier = modelIdentifier
        self.title = Self.normalizedTitle(title, turns: turns)
        self.turnsData = Self.encode(turns)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func rename(to proposedTitle: String) {
        title = Self.normalizedTitle(proposedTitle, turns: turns)
        updatedAt = .now
    }

    func update(turns: [ChartConversationTurn], modelIdentifier: String) {
        turnsData = Self.encode(turns)
        self.modelIdentifier = modelIdentifier
        updatedAt = .now
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let turnText = turns.flatMap { [$0.question, $0.answer] }.joined(separator: " ")
        return [title, chartName, modelIdentifier, turnText].contains {
            $0.localizedCaseInsensitiveContains(normalized)
        }
    }

    func exportText() -> String {
        var lines = [
            "很牛的紫微斗數｜本機命盤助理對話",
            "標題：\(title)",
            "命盤：\(chartName)（\(chartDetail)）",
            "模型：\(modelIdentifier)",
            "建立時間：\(createdAt.formatted(date: .numeric, time: .shortened))",
            "",
            "這份內容是使用者主動保存在本機的 AI 對話，只供娛樂與自我反思。"
        ]
        for (index, turn) in turns.enumerated() {
            lines.append(contentsOf: [
                "",
                "第 \(index + 1) 輪｜問題",
                turn.question,
                "",
                "第 \(index + 1) 輪｜回答",
                turn.answer,
                "狀態：\(turn.status == .answered ? "已回答" : "無法用命盤回答")",
                "依據：\(turn.evidenceFactIDs.isEmpty ? "無" : turn.evidenceFactIDs.joined(separator: "、"))"
            ])
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizedTitle(
        _ proposedTitle: String,
        turns: [ChartConversationTurn]
    ) -> String {
        let trimmed = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
        guard let first = turns.first else { return "命盤助理對話" }
        return String(first.question.prefix(30))
    }

    private static func encode(_ turns: [ChartConversationTurn]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(turns)) ?? Data("[]".utf8)
    }
}

@Model
final class CloudDeletion {
    @Attribute(.unique) var id: UUID
    var entityID: UUID
    var entityType: String
    var deletedAt: Date

    init(
        id: UUID = UUID(),
        entityID: UUID,
        entityType: String,
        deletedAt: Date = .now
    ) {
        self.id = id
        self.entityID = entityID
        self.entityType = entityType
        self.deletedAt = deletedAt
    }
}

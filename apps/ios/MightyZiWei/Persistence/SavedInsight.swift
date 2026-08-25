import Foundation
import SwiftData

@Model
final class SavedInsight {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case note
        case bookmark
    }

    enum Marker: String, Codable, CaseIterable, Sendable {
        case none
        case resonates
        case observe

        var title: String {
            switch self {
            case .none: "未標記"
            case .resonates: "有共鳴"
            case .observe: "之後再觀察"
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var chartID: UUID
    var kindRawValue: String
    var locationID: String
    var title: String
    var content: String
    var markerRawValue: String
    var evidenceFactIDsData: Data
    var createdAt: Date
    var updatedAt: Date

    var kind: Kind {
        Kind(rawValue: kindRawValue) ?? .note
    }

    var marker: Marker {
        get { Marker(rawValue: markerRawValue) ?? .none }
        set { markerRawValue = newValue.rawValue }
    }

    var evidenceFactIDs: [String] {
        (try? JSONDecoder().decode([String].self, from: evidenceFactIDsData)) ?? []
    }

    init(
        id: UUID = UUID(),
        chartID: UUID,
        kind: Kind,
        locationID: String,
        title: String,
        content: String,
        marker: Marker = .none,
        evidenceFactIDs: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.chartID = chartID
        self.kindRawValue = kind.rawValue
        self.locationID = locationID
        self.title = title
        self.content = content
        self.markerRawValue = marker.rawValue
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.evidenceFactIDsData = (try? encoder.encode(evidenceFactIDs)) ?? Data("[]".utf8)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updateNote(title: String, content: String, marker: Marker) {
        self.title = Self.normalized(title, fallback: "私人筆記")
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.marker = marker
        updatedAt = .now
    }

    static func bookmark(
        chartID: UUID,
        locationID: String,
        title: String,
        content: String,
        evidenceFactIDs: [String]
    ) -> SavedInsight {
        SavedInsight(
            chartID: chartID,
            kind: .bookmark,
            locationID: locationID,
            title: normalized(title, fallback: "收藏內容"),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceFactIDs: evidenceFactIDs
        )
    }

    private static func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

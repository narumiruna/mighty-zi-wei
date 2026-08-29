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
  var evidenceSeedIDsData: Data = Data("[]".utf8)
  var evidenceFactIDsData: Data
  var reviewDate: Date?
  var reminderIdentifier: String?
  var createdAt: Date
  var updatedAt: Date

  var kind: Kind {
    Kind(rawValue: kindRawValue) ?? .note
  }

  var marker: Marker {
    get { Marker(rawValue: markerRawValue) ?? .none }
    set { markerRawValue = newValue.rawValue }
  }

  var evidenceSeedIDs: [String] {
    Self.decodeEvidenceIDs(evidenceSeedIDsData)
  }

  var evidenceFactIDs: [String] {
    Self.decodeEvidenceIDs(evidenceFactIDsData)
  }

  init(
    id: UUID = UUID(),
    chartID: UUID,
    kind: Kind,
    locationID: String,
    title: String,
    content: String,
    marker: Marker = .none,
    evidenceSeedIDs: [String] = [],
    evidenceFactIDs: [String] = [],
    reviewDate: Date? = nil,
    reminderIdentifier: String? = nil,
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
    self.evidenceSeedIDsData = Self.encodeEvidenceIDs(evidenceSeedIDs)
    self.evidenceFactIDsData = Self.encodeEvidenceIDs(evidenceFactIDs)
    self.reviewDate = reviewDate
    self.reminderIdentifier = reminderIdentifier
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  func updateNote(
    title: String,
    content: String,
    marker: Marker,
    locationID: String? = nil,
    evidenceFactIDs: [String]? = nil,
    reviewDate: Date? = nil,
    reminderIdentifier: String? = nil
  ) {
    self.title = Self.normalized(title, fallback: "私人筆記")
    self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    self.marker = marker
    if let locationID {
      self.locationID = locationID
    }
    if let evidenceFactIDs {
      if Set(evidenceFactIDs) != Set(self.evidenceFactIDs) {
        evidenceSeedIDsData = Self.encodeEvidenceIDs([])
        evidenceFactIDsData = Self.encodeEvidenceIDs(evidenceFactIDs)
      }
    }
    self.reviewDate = reviewDate
    self.reminderIdentifier = reminderIdentifier
    updatedAt = .now
  }

  var linkedContentTitle: String {
    if locationID.hasPrefix("palace.") {
      if let value = locationID.split(separator: ".").last {
        if let kind = PalaceKind(rawValue: String(value)) {
          return kind.displayName
        }
      }
    }
    if locationID.hasPrefix("interpretation.") {
      return "命盤解讀"
    }
    if locationID.hasPrefix("assistant.") {
      return "命盤助理回答"
    }
    return "整張命盤"
  }

  func matchesBookmark(
    title: String,
    content: String,
    evidenceSeedIDs: [String],
    evidenceFactIDs: [String]
  ) -> Bool {
    kind == .bookmark
      && self.title == Self.normalized(title, fallback: "收藏內容")
      && self.content == content.trimmingCharacters(in: .whitespacesAndNewlines)
      && self.evidenceSeedIDs == evidenceSeedIDs
      && self.evidenceFactIDs == evidenceFactIDs
  }

  func updateBookmark(
    title: String,
    content: String,
    evidenceSeedIDs: [String],
    evidenceFactIDs: [String]
  ) {
    self.title = Self.normalized(title, fallback: "收藏內容")
    self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    evidenceSeedIDsData = Self.encodeEvidenceIDs(evidenceSeedIDs)
    evidenceFactIDsData = Self.encodeEvidenceIDs(evidenceFactIDs)
    updatedAt = .now
  }

  static func bookmark(
    chartID: UUID,
    locationID: String,
    title: String,
    content: String,
    evidenceSeedIDs: [String] = [],
    evidenceFactIDs: [String]
  ) -> SavedInsight {
    SavedInsight(
      chartID: chartID,
      kind: .bookmark,
      locationID: locationID,
      title: normalized(title, fallback: "收藏內容"),
      content: content.trimmingCharacters(in: .whitespacesAndNewlines),
      evidenceSeedIDs: evidenceSeedIDs,
      evidenceFactIDs: evidenceFactIDs
    )
  }

  private static func normalized(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  private static func decodeEvidenceIDs(_ data: Data) -> [String] {
    (try? JSONDecoder().decode([String].self, from: data)) ?? []
  }

  private static func encodeEvidenceIDs(_ identifiers: [String]) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(identifiers)) ?? Data("[]".utf8)
  }
}

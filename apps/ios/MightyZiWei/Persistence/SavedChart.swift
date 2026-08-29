import Foundation
import SwiftData

@Model
final class SavedChart {
  static let schemaVersion = 1

  @Attribute(.unique) var id: UUID
  var name: String
  var birthProfileData: Data
  var ruleSetID: String
  var ruleSetVersion: Int
  var appSchemaVersion: Int
  var chartCacheData: Data?
  var tagsData: Data = Data("[]".utf8)
  var isPinned: Bool = false
  var createdAt: Date
  var updatedAt: Date

  var tags: [String] {
    get { (try? JSONDecoder().decode([String].self, from: tagsData)) ?? [] }
    set { tagsData = Self.encodeTags(newValue) }
  }

  init(
    id: UUID = UUID(),
    name: String,
    birthProfileData: Data,
    ruleSetID: String,
    ruleSetVersion: Int,
    appSchemaVersion: Int = SavedChart.schemaVersion,
    chartCacheData: Data?,
    tags: [String] = [],
    isPinned: Bool = false,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.birthProfileData = birthProfileData
    self.ruleSetID = ruleSetID
    self.ruleSetVersion = ruleSetVersion
    self.appSchemaVersion = appSchemaVersion
    self.chartCacheData = chartCacheData
    self.tagsData = Self.encodeTags(tags)
    self.isPinned = isPinned
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  static func make(name: String, profile: BirthProfile, chart: ZiWeiChart) throws -> SavedChart {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return SavedChart(
      name: normalizedName(name, profile: profile),
      birthProfileData: try encoder.encode(profile),
      ruleSetID: chart.ruleSet.id,
      ruleSetVersion: chart.ruleSet.version,
      chartCacheData: try encoder.encode(chart)
    )
  }

  func birthProfile() throws -> BirthProfile {
    try JSONDecoder().decode(BirthProfile.self, from: birthProfileData)
  }

  func resolvedChart() throws -> ZiWeiChart {
    let current = RuleSetIdentity.taiwanTraditionalSanheV1
    let advancesContentRevision =
      ruleSetID != current.id
      || ruleSetVersion != current.version
      || appSchemaVersion != Self.schemaVersion
    if !advancesContentRevision,
      let chartCacheData,
      let cached = try? JSONDecoder().decode(ZiWeiChart.self, from: chartCacheData)
    {
      return cached
    }

    let profile = try birthProfile()
    let chart = try ZiWeiCalculator().calculate(profile)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    chartCacheData = try encoder.encode(chart)
    ruleSetID = chart.ruleSet.id
    ruleSetVersion = chart.ruleSet.version
    appSchemaVersion = Self.schemaVersion
    if advancesContentRevision {
      updatedAt = .now
    }
    return chart
  }

  func rename(to proposedName: String) throws {
    name = Self.normalizedName(proposedName, profile: try birthProfile())
    updatedAt = .now
  }

  func updateTags(_ proposedTags: [String]) {
    tags = proposedTags
    updatedAt = .now
  }

  func setPinned(_ pinned: Bool) {
    isPinned = pinned
    updatedAt = .now
  }

  func hasSameBirthProfile(as other: SavedChart) -> Bool {
    (try? birthProfile()) == (try? other.birthProfile())
  }

  func matchesSearch(_ query: String, calendar: Calendar = .current) -> Bool {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return true }
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.locale = Locale(identifier: "zh_Hant_TW")
    dateFormatter.dateFormat = "yyyy/MM/dd"
    let values = [name, tags.joined(separator: " "), dateFormatter.string(from: createdAt)]
    return values.contains { $0.localizedCaseInsensitiveContains(normalized) }
  }

  private static func normalizedName(_ value: String, profile: BirthProfile) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return "\(profile.localDate.year)/\(profile.localDate.month)/\(profile.localDate.day) 命盤"
  }

  private static func encodeTags(_ values: [String]) -> Data {
    var seen = Set<String>()
    let normalized = values.compactMap { value -> String? in
      let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !tag.isEmpty, tag.count <= 30 else { return nil }
      let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      return seen.insert(key).inserted ? tag : nil
    }.prefix(20)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(Array(normalized))) ?? Data("[]".utf8)
  }
}

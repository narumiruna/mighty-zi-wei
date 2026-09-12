import CryptoKit
import Foundation

/// 已儲存命盤只保存導覽位置；未儲存命盤的進度只存在此實例的記憶體。
@MainActor
final class ChartReadingGuideProgressStore {
  struct Identity: Hashable, Codable, Sendable {
    let chartID: UUID
    let ruleSet: RuleSetIdentity
    let interpretationVersion: String
    let guideVersion: String
    let chartFingerprint: String

    init(
      chartID: UUID,
      chart: ZiWeiChart,
      interpretationVersion: String = InterpretationSourceCatalog.contentVersion,
      guideVersion: String = ChartReadingGuide.contentVersion
    ) {
      self.chartID = chartID
      ruleSet = chart.ruleSet
      self.interpretationVersion = interpretationVersion
      self.guideVersion = guideVersion
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let data = (try? encoder.encode(chart)) ?? Data()
      chartFingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate var storageKey: String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let data = (try? encoder.encode(self)) ?? Data()
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      return ChartReadingGuideProgressStore.prefix(chartID: chartID) + digest
    }
  }

  private let defaults: UserDefaults
  private var memory: [Identity: ChartReadingGuide.Progress] = [:]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load(for identity: Identity, isSaved: Bool) -> ChartReadingGuide.Progress {
    guard isSaved else { return memory[identity] ?? .init() }
    guard let data = defaults.data(forKey: identity.storageKey),
      let progress = try? JSONDecoder().decode(ChartReadingGuide.Progress.self, from: data)
    else { return .init() }
    // 不快取磁碟進度，刪除命盤後不會由舊實例重新讀出已刪進度。
    return progress
  }

  func save(_ progress: ChartReadingGuide.Progress, for identity: Identity, isSaved: Bool) {
    guard isSaved else {
      memory[identity] = progress
      return
    }
    guard let data = try? JSONEncoder().encode(progress) else { return }
    defaults.set(data, forKey: identity.storageKey)
  }

  nonisolated static func remove(chartID: UUID) {
    remove(chartID: chartID, defaults: .standard)
  }

  nonisolated static func remove(chartID: UUID, defaults: UserDefaults) {
    let prefix = prefix(chartID: chartID)
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      defaults.removeObject(forKey: key)
    }
  }

  nonisolated private static func prefix(chartID: UUID) -> String {
    "chart.reading-guide.\(chartID.uuidString.lowercased())."
  }
}

import XCTest

@testable import MightyZiWei

@MainActor
final class AIConfigurationRecoveryTests: XCTestCase {
  func test失敗後依序回復設定上限憑證且單一步驟失敗仍繼續() throws {
    for failingRestore in ["", "設定回復", "上限回復", "憑證回復"] {
      let suite = "AIConfigurationRecoveryTests.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      defaults.set("https://old.example/responses", forKey: "ai.responses.endpoint")
      defaults.set("old-model", forKey: "ai.responses.model")
      defaults.set(17, forKey: "ai.usage.monthly-limit")
      var events: [String] = []
      let credentials = RecoveryCredentials()
      credentials.onSave = { value in
        let event = value == "old-key" ? "憑證回復" : "憑證寫入"
        events.append(event)
        if event == failingRestore { throw RecoveryError.injected }
      }
      let configuration = AIConfigurationStore(
        defaults: defaults, credentialStore: credentials,
        defaultsWriter: { mutation in
          let event: String
          switch mutation {
          case .save: event = "設定寫入"
          case .restore: event = "設定回復"
          case .clear: event = "清除"
          }
          events.append(event)
          if event == failingRestore { throw RecoveryError.injected }
        })
      let usage = AIUsageStore(
        defaults: defaults,
        defaultsWriter: { mutation in
          switch mutation {
          case .saveMonthlyLimit:
            events.append("上限寫入")
            throw RecoveryError.injected
          case .restoreMonthlyLimit:
            events.append("上限回復")
            if failingRestore == "上限回復" { throw RecoveryError.injected }
          }
        })
      let coordinator = AIConfigurationCommitCoordinator(
        configurationStore: configuration, usageStore: usage)
      XCTAssertThrowsError(
        try coordinator.commit(
          draft: AIConfigurationDraft(
            endpoint: "https://new.example", model: "new-model", apiKey: "new-key",
            maximumAnswerCharacters: 800, monthlyLimit: 30))
      ) {
        if failingRestore.isEmpty {
          XCTAssertEqual($0 as? RecoveryError, .injected)
        } else {
          XCTAssertEqual($0 as? AIConfigurationCommitError, .recoveryRequired)
        }
      }
      XCTAssertEqual(events, ["憑證寫入", "設定寫入", "上限寫入", "設定回復", "上限回復", "憑證回復"])
      XCTAssertEqual(configuration.requiresRecovery, !failingRestore.isEmpty)
      XCTAssertEqual(configuration.isConfigured, failingRestore.isEmpty)
      XCTAssertEqual(usage.monthlyLimit, 17)
    }
  }

  func test清除失敗回復原設定而Recovery清除失敗仍停用AI() throws {
    let suite = "AIConfigurationClearTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("old-model", forKey: "ai.responses.model")
    let credentials = RecoveryCredentials()
    let configuration = AIConfigurationStore(
      defaults: defaults, credentialStore: credentials,
      defaultsWriter: { mutation in
        if case .clear = mutation { throw RecoveryError.injected }
      })
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configuration, usageStore: AIUsageStore(defaults: defaults))
    XCTAssertThrowsError(try coordinator.clear()) {
      XCTAssertEqual($0 as? RecoveryError, .injected)
    }
    XCTAssertEqual(try configuration.configuration().apiKey, "old-key")
    XCTAssertTrue(configuration.isConfigured)
    XCTAssertThrowsError(try coordinator.discardRecoveryConfiguration()) {
      XCTAssertEqual($0 as? AIConfigurationCommitError, .recoveryRequired)
    }
    XCTAssertFalse(configuration.isConfigured)
    XCTAssertTrue(configuration.requiresRecovery)
  }
}

private enum RecoveryError: Error { case injected }

private final class RecoveryCredentials: APICredentialStoring {
  var value: String? = "old-key"
  var onSave: ((String?) throws -> Void)?

  func loadAPIKey() throws -> String? { value }
  func saveAPIKey(_ apiKey: String?) throws {
    try onSave?(apiKey)
    value = apiKey
  }
}

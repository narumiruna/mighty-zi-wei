import Foundation
import Security
import XCTest

@testable import MightyZiWei

@MainActor
final class AIConfigurationStoreTests: XCTestCase {
  private static let endpointDefaultsKey = "ai.responses.endpoint"
  private static let modelDefaultsKey = "ai.responses.model"
  private static let answerLengthDefaultsKey = "ai.responses.maximum-answer-characters"
  private static let monthlyLimitDefaultsKey = "ai.usage.monthly-limit"

  private var defaults: UserDefaults!
  private var credentials: InMemoryCredentialStore!
  private var suiteName: String!

  override func setUp() async throws {
    suiteName = "AIConfigurationStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
    credentials = InMemoryCredentialStore()
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    credentials = nil
    suiteName = nil
  }

  func test儲存後可重新載入設定與APIKey() throws {
    let store = AIConfigurationStore(defaults: defaults, credentialStore: credentials)

    try store.save(
      endpoint: "https://example.com/v1/responses",
      model: "example-model",
      apiKey: "secret"
    )
    let reloaded = AIConfigurationStore(defaults: defaults, credentialStore: credentials)
    let configuration = try reloaded.configuration()

    XCTAssertTrue(reloaded.isConfigured)
    XCTAssertEqual(configuration.endpoint.absoluteString, "https://example.com/v1/responses")
    XCTAssertEqual(configuration.model, "example-model")
    XCTAssertEqual(configuration.apiKey, "secret")
  }

  func testBaseURL會自動補上Responses路徑並保存() throws {
    let store = AIConfigurationStore(defaults: defaults, credentialStore: credentials)

    try store.save(
      endpoint: "https://example.com/openai/v1/",
      model: "example-model",
      apiKey: ""
    )

    XCTAssertEqual(store.endpoint, "https://example.com/openai/v1/responses")
    XCTAssertEqual(
      try store.configuration().endpoint.absoluteString,
      "https://example.com/openai/v1/responses"
    )
  }

  func test完整ResponsesURL不會重複補上路徑並保留Query() throws {
    let configuration = try OpenAIResponsesConfiguration(
      endpoint: "https://example.com/openai/v1/responses/?api-version=2026-01-01",
      model: "example-model",
      apiKey: nil
    )

    XCTAssertEqual(
      configuration.endpoint.absoluteString,
      "https://example.com/openai/v1/responses?api-version=2026-01-01"
    )
  }

  func testBaseURL補上Responses路徑時會保留Query() throws {
    let configuration = try OpenAIResponsesConfiguration(
      endpoint: "https://example.com/openai/v1?api-version=2026-01-01",
      model: "example-model",
      apiKey: nil
    )

    XCTAssertEqual(
      configuration.endpoint.absoluteString,
      "https://example.com/openai/v1/responses?api-version=2026-01-01"
    )
  }

  func test空白APIKey不會儲存憑證() throws {
    let store = AIConfigurationStore(defaults: defaults, credentialStore: credentials)

    try store.save(
      endpoint: "https://example.com/responses",
      model: "local-model",
      apiKey: "   "
    )

    XCTAssertNil(try credentials.loadAPIKey())
    XCTAssertNil(try store.configuration().apiKey)
  }

  func test清除設定會移除UserDefaults與憑證() throws {
    let store = AIConfigurationStore(defaults: defaults, credentialStore: credentials)
    try store.save(
      endpoint: "https://example.com/responses",
      model: "model",
      apiKey: "secret"
    )

    try store.clear()

    XCTAssertFalse(store.isConfigured)
    XCTAssertEqual(store.endpoint, AIConfigurationStore.defaultEndpoint)
    XCTAssertEqual(store.model, "")
    XCTAssertNil(try credentials.loadAPIKey())
  }

  func test只接受無內嵌憑證的完整HTTPSURL與非空Model() {
    XCTAssertThrowsError(
      try OpenAIResponsesConfiguration(
        endpoint: "http://example.com/responses",
        model: "model",
        apiKey: nil
      )
    )
    XCTAssertThrowsError(
      try OpenAIResponsesConfiguration(
        endpoint: "https://user:password@example.com/responses",
        model: "model",
        apiKey: nil
      )
    )
    XCTAssertThrowsError(
      try OpenAIResponsesConfiguration(
        endpoint: "https://example.com/responses",
        model: "  ",
        apiKey: nil
      )
    )
  }

  func test建立草稿會載入五項持久化設定且編輯草稿不會直接儲存() throws {
    try seedStoredValues(
      endpoint: "https://saved.example/v1",
      model: "saved-model",
      apiKey: "saved-key",
      maximumAnswerCharacters: 750,
      monthlyLimit: 23
    )
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )

    var draft = try coordinator.makeDraft()

    XCTAssertEqual(
      draft,
      AIConfigurationDraft(
        endpoint: "https://saved.example/v1/responses",
        model: "saved-model",
        apiKey: "saved-key",
        maximumAnswerCharacters: 750,
        monthlyLimit: 23
      )
    )

    draft.endpoint = "https://draft.example/v2"
    draft.model = "draft-model"
    draft.apiKey = "draft-key"
    draft.maximumAnswerCharacters = 900
    draft.monthlyLimit = 31

    XCTAssertEqual(
      try coordinator.makeDraft(),
      AIConfigurationDraft(
        endpoint: "https://saved.example/v1/responses",
        model: "saved-model",
        apiKey: "saved-key",
        maximumAnswerCharacters: 750,
        monthlyLimit: 23
      )
    )
    XCTAssertTrue(credentials.saveInvocations.isEmpty)
  }

  func test提交草稿會一起保存EndpointModelAPIKey回答長度與每月上限() throws {
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    let draft = AIConfigurationDraft(
      endpoint: "  https://new.example/openai/v1/  ",
      model: "  new-model  ",
      apiKey: "  new-key  ",
      maximumAnswerCharacters: 888,
      monthlyLimit: 37
    )

    try coordinator.commit(draft: draft)

    let reloadedConfigurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let reloadedUsageStore = AIUsageStore(defaults: defaults)
    let configuration = try reloadedConfigurationStore.configuration()
    XCTAssertEqual(configuration.endpoint.absoluteString, "https://new.example/openai/v1/responses")
    XCTAssertEqual(configuration.model, "new-model")
    XCTAssertEqual(configuration.apiKey, "new-key")
    XCTAssertEqual(configuration.maximumAnswerCharacters, 888)
    XCTAssertEqual(reloadedUsageStore.monthlyLimit, 37)
    XCTAssertTrue(reloadedConfigurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["new-key"])
  }

  func test更新既有APIKey會直接寫入新值而不先刪除且空白Key才刪除() throws {
    try seedStoredValues(apiKey: "old-key")
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    var draft = try coordinator.makeDraft()
    draft.apiKey = "new-key"

    try coordinator.commit(draft: draft)

    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["new-key"])
    XCTAssertEqual(try credentials.loadAPIKey(), "new-key")

    credentials.resetSaveInvocations()
    draft = try coordinator.makeDraft()
    draft.apiKey = "   "

    try coordinator.commit(draft: draft)

    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["<nil>"])
    XCTAssertNil(try credentials.loadAPIKey())
    XCTAssertFalse(configurationStore.hasAPIKey)
  }

  func testKeychain更新失敗會保留五項舊值並回復舊Key() throws {
    try seedStoredValues(
      endpoint: "https://old.example/v1",
      model: "old-model",
      apiKey: "old-key",
      maximumAnswerCharacters: 640,
      monthlyLimit: 12
    )
    credentials.failingAPIKeys = ["new-key"]
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    let draft = AIConfigurationDraft(
      endpoint: "https://new.example/v2",
      model: "new-model",
      apiKey: "new-key",
      maximumAnswerCharacters: 900,
      monthlyLimit: 99
    )

    XCTAssertThrowsError(try coordinator.commit(draft: draft)) { error in
      XCTAssertEqual(error as? InjectedError, .credentialWrite)
    }

    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["new-key", "old-key"])
    XCTAssertEqual(try credentials.loadAPIKey(), "old-key")
    XCTAssertEqual(try coordinator.makeDraft(), oldDraft)
    XCTAssertTrue(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
  }

  func testConfigurationDefaults寫入失敗會回復五項舊值() throws {
    try seedStoredValues(
      endpoint: "https://old.example/v1",
      model: "old-model",
      apiKey: "old-key",
      maximumAnswerCharacters: 640,
      monthlyLimit: 12
    )
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials,
      defaultsWriter: { [defaults] mutation in
        Self.apply(mutation, to: defaults!)
        if case .save(_, let model, _) = mutation, model == "new-model" {
          throw InjectedError.defaultsWrite
        }
      }
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    let draft = AIConfigurationDraft(
      endpoint: "https://new.example/v2",
      model: "new-model",
      apiKey: "new-key",
      maximumAnswerCharacters: 900,
      monthlyLimit: 99
    )

    XCTAssertThrowsError(try coordinator.commit(draft: draft)) { error in
      XCTAssertEqual(error as? InjectedError, .defaultsWrite)
    }

    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["new-key", "old-key"])
    XCTAssertEqual(try coordinator.makeDraft(), oldDraft)
    XCTAssertTrue(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
  }

  func test每月上限Defaults寫入失敗會回復已更新的設定與Key() throws {
    try seedStoredValues(
      endpoint: "https://old.example/v1",
      model: "old-model",
      apiKey: "old-key",
      maximumAnswerCharacters: 640,
      monthlyLimit: 12
    )
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(
      defaults: defaults,
      defaultsWriter: { [defaults] mutation in
        Self.apply(mutation, to: defaults!)
        if case .saveMonthlyLimit(99) = mutation {
          throw InjectedError.defaultsWrite
        }
      }
    )
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    let draft = AIConfigurationDraft(
      endpoint: "https://new.example/v2",
      model: "new-model",
      apiKey: "new-key",
      maximumAnswerCharacters: 900,
      monthlyLimit: 99
    )

    XCTAssertThrowsError(try coordinator.commit(draft: draft)) { error in
      XCTAssertEqual(error as? InjectedError, .defaultsWrite)
    }

    let reloadedConfigurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let reloadedUsageStore = AIUsageStore(defaults: defaults)
    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["new-key", "old-key"])
    XCTAssertEqual(try coordinator.makeDraft(), oldDraft)
    XCTAssertEqual(try reloadedConfigurationStore.configuration().model, "old-model")
    XCTAssertEqual(reloadedUsageStore.monthlyLimit, 12)
    XCTAssertTrue(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
  }

  func testKeychain回復失敗會進入Recovery清空非秘密欄位並停用AI() throws {
    try seedStoredValues(
      endpoint: "https://old.example/v1",
      model: "old-model",
      apiKey: "old-key",
      maximumAnswerCharacters: 640,
      monthlyLimit: 12
    )
    credentials.failingAPIKeys = ["old-key"]
    var shouldFailMonthlyLimit = true
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(
      defaults: defaults,
      defaultsWriter: { [defaults] mutation in
        Self.apply(mutation, to: defaults!)
        if shouldFailMonthlyLimit, case .saveMonthlyLimit(99) = mutation {
          throw InjectedError.defaultsWrite
        }
      }
    )
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    let draft = AIConfigurationDraft(
      endpoint: "https://new.example/v2",
      model: "new-model",
      apiKey: "new-key",
      maximumAnswerCharacters: 900,
      monthlyLimit: 99
    )

    XCTAssertThrowsError(try coordinator.commit(draft: draft)) { error in
      XCTAssertEqual(error as? AIConfigurationCommitError, .recoveryRequired)
    }

    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["new-key", "old-key"])
    XCTAssertTrue(configurationStore.requiresRecovery)
    XCTAssertFalse(configurationStore.isConfigured)
    XCTAssertEqual(configurationStore.endpoint, AIConfigurationStore.defaultEndpoint)
    XCTAssertEqual(configurationStore.model, "")
    XCTAssertEqual(
      coordinator.recoveryMessage,
      AIConfigurationCommitError.recoveryRequired.errorDescription
    )
    XCTAssertThrowsError(try configurationStore.configuration()) { error in
      XCTAssertEqual(error as? AIConfigurationCommitError, .recoveryRequired)
    }

    shouldFailMonthlyLimit = false
    credentials.failingAPIKeys.removeAll()
    try coordinator.commit(draft: draft)

    XCTAssertFalse(configurationStore.requiresRecovery)
    XCTAssertTrue(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
  }

  func test清除API設定會保留每月上限與本月計次() throws {
    try seedStoredValues(
      endpoint: "https://saved.example/v1",
      model: "saved-model",
      apiKey: "saved-key",
      maximumAnswerCharacters: 700,
      monthlyLimit: 7
    )
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    try usageStore.reserve(.conversation)
    try usageStore.reserve(.connectionTest)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )

    try coordinator.clear()

    let reloadedUsageStore = AIUsageStore(defaults: defaults)
    XCTAssertFalse(configurationStore.isConfigured)
    XCTAssertEqual(configurationStore.endpoint, AIConfigurationStore.defaultEndpoint)
    XCTAssertEqual(configurationStore.model, "")
    XCTAssertEqual(
      configurationStore.maximumAnswerCharacters,
      AIConfigurationStore.defaultMaximumAnswerCharacters
    )
    XCTAssertNil(try credentials.loadAPIKey())
    XCTAssertEqual(usageStore.monthlyLimit, 7)
    XCTAssertEqual(usageStore.currentMonthCount, 2)
    XCTAssertEqual(reloadedUsageStore.monthlyLimit, 7)
    XCTAssertEqual(reloadedUsageStore.currentMonthCount, 2)
    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["<nil>"])
  }

  func test連線測試使用目前草稿且只增加一次用量不會提交設定() async throws {
    try seedStoredValues(
      endpoint: "https://saved.example/v1",
      model: "saved-model",
      apiKey: "saved-key",
      maximumAnswerCharacters: 700,
      monthlyLimit: 10
    )
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let tester = RecordingConnectionTester()
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore,
      connectionTester: tester
    )
    let draft = AIConfigurationDraft(
      endpoint: "https://draft.example/openai/v1?api-version=2026-01-01",
      model: "draft-model",
      apiKey: "draft-key",
      maximumAnswerCharacters: 888,
      monthlyLimit: 42
    )

    try await coordinator.testConnection(draft: draft)

    let testedConfigurations = await tester.recordedConfigurations()
    XCTAssertEqual(testedConfigurations.count, 1)
    XCTAssertEqual(
      testedConfigurations.first?.endpoint.absoluteString,
      "https://draft.example/openai/v1/responses?api-version=2026-01-01"
    )
    XCTAssertEqual(testedConfigurations.first?.model, "draft-model")
    XCTAssertEqual(testedConfigurations.first?.apiKey, "draft-key")
    XCTAssertEqual(testedConfigurations.first?.maximumAnswerCharacters, 888)
    XCTAssertEqual(usageStore.currentMonthCount, 1)
    XCTAssertEqual(usageStore.monthlyLimit, 10)
    XCTAssertEqual(
      try coordinator.makeDraft(),
      AIConfigurationDraft(
        endpoint: "https://saved.example/v1/responses",
        model: "saved-model",
        apiKey: "saved-key",
        maximumAnswerCharacters: 700,
        monthlyLimit: 10
      )
    )
    XCTAssertTrue(credentials.saveInvocations.isEmpty)
  }

  func test無效回答長度或每月上限會在寫入前拒絕整份草稿() throws {
    try seedStoredValues(apiKey: "old-key")
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )
    var draft = try coordinator.makeDraft()
    draft.maximumAnswerCharacters = 299
    draft.apiKey = "new-key"

    XCTAssertThrowsError(try coordinator.commit(draft: draft)) { error in
      XCTAssertEqual(error as? AIConfigurationCommitError, .invalidAnswerLength)
    }

    draft.maximumAnswerCharacters = 300
    draft.monthlyLimit = -1

    XCTAssertThrowsError(try coordinator.commit(draft: draft)) { error in
      XCTAssertEqual(error as? AIConfigurationCommitError, .invalidMonthlyLimit)
    }

    XCTAssertTrue(credentials.saveInvocations.isEmpty)
    XCTAssertEqual(try credentials.loadAPIKey(), "old-key")
    XCTAssertEqual(try coordinator.makeDraft(), oldDraftWithMonthlyLimit(12, answerLength: 640))
  }

  func test建立草稿時Keychain讀取失敗會停用AI並可移除損毀設定() throws {
    credentials.failsToLoad = true
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )

    XCTAssertTrue(configurationStore.requiresRecovery)
    XCTAssertFalse(configurationStore.isConfigured)
    XCTAssertEqual(
      coordinator.recoveryMessage,
      AIConfigurationCommitError.recoveryRequired.errorDescription
    )
    XCTAssertThrowsError(try coordinator.makeDraft()) { error in
      XCTAssertEqual(error as? InjectedError, .credentialLoad)
    }

    try coordinator.discardRecoveryConfiguration()
    credentials.failsToLoad = false

    XCTAssertEqual(credentials.saveInvocations.map { $0 ?? "<nil>" }, ["<nil>"])
    XCTAssertFalse(configurationStore.requiresRecovery)
    XCTAssertFalse(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
    XCTAssertEqual(try coordinator.makeDraft().apiKey, "")
  }

  func test裝置鎖定造成Keychain暫時不可用會在解鎖後自動恢復() throws {
    try seedStoredValues(
      endpoint: "https://saved.example/v1",
      model: "saved-model",
      apiKey: "saved-key",
      maximumAnswerCharacters: 700,
      monthlyLimit: 10
    )
    credentials.isTemporarilyUnavailableToLoad = true
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: AIUsageStore(defaults: defaults)
    )

    XCTAssertTrue(configurationStore.credentialsTemporarilyUnavailable)
    XCTAssertFalse(configurationStore.requiresRecovery)
    XCTAssertFalse(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)

    coordinator.refreshCredentialAvailability()
    XCTAssertTrue(configurationStore.credentialsTemporarilyUnavailable)
    XCTAssertFalse(configurationStore.requiresRecovery)

    credentials.isTemporarilyUnavailableToLoad = false
    coordinator.refreshCredentialAvailability()

    XCTAssertFalse(configurationStore.credentialsTemporarilyUnavailable)
    XCTAssertFalse(configurationStore.requiresRecovery)
    XCTAssertTrue(configurationStore.isConfigured)
    XCTAssertNil(coordinator.recoveryMessage)
    XCTAssertEqual(try coordinator.makeDraft().apiKey, "saved-key")
    XCTAssertTrue(credentials.saveInvocations.isEmpty)
  }

  func testKeychain只將受保護資料暫時不可用狀態視為可重試() {
    let store = KeychainAPICredentialStore()

    XCTAssertTrue(
      store.isTemporarilyUnavailable(
        KeychainAPICredentialStore.CredentialError.keychain(errSecInteractionNotAllowed)
      ))
    XCTAssertTrue(
      store.isTemporarilyUnavailable(
        KeychainAPICredentialStore.CredentialError.keychain(errSecNotAvailable)
      ))
    XCTAssertFalse(
      store.isTemporarilyUnavailable(
        KeychainAPICredentialStore.CredentialError.invalidData
      ))
    XCTAssertFalse(
      store.isTemporarilyUnavailable(
        KeychainAPICredentialStore.CredentialError.keychain(errSecDecode)
      ))
  }

  func test跨月開啟設定會先重設本機用量() throws {
    defaults.set("1999-01", forKey: "ai.usage.month")
    defaults.set(23, forKey: "ai.usage.count")
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    let usageStore = AIUsageStore(defaults: defaults)
    let coordinator = AIConfigurationCommitCoordinator(
      configurationStore: configurationStore,
      usageStore: usageStore
    )

    XCTAssertEqual(coordinator.currentMonthCount, 0)
    XCTAssertEqual(coordinator.remainingRequests(for: 50), 50)
  }

  private var oldDraft: AIConfigurationDraft {
    oldDraftWithMonthlyLimit(12, answerLength: 640)
  }

  private func oldDraftWithMonthlyLimit(
    _ monthlyLimit: Int,
    answerLength: Int
  ) -> AIConfigurationDraft {
    AIConfigurationDraft(
      endpoint: "https://old.example/v1/responses",
      model: "old-model",
      apiKey: "old-key",
      maximumAnswerCharacters: answerLength,
      monthlyLimit: monthlyLimit
    )
  }

  private func seedStoredValues(
    endpoint: String = "https://old.example/v1",
    model: String = "old-model",
    apiKey: String,
    maximumAnswerCharacters: Int = 640,
    monthlyLimit: Int = 12
  ) throws {
    let configurationStore = AIConfigurationStore(
      defaults: defaults,
      credentialStore: credentials
    )
    configurationStore.setMaximumAnswerCharacters(maximumAnswerCharacters)
    try configurationStore.save(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey
    )
    let usageStore = AIUsageStore(defaults: defaults)
    usageStore.monthlyLimit = monthlyLimit
    credentials.resetSaveInvocations()
  }

  private static func apply(
    _ mutation: AIConfigurationDefaultsMutation,
    to defaults: UserDefaults
  ) {
    switch mutation {
    case .save(let endpoint, let model, let maximumAnswerCharacters):
      defaults.set(endpoint, forKey: endpointDefaultsKey)
      defaults.set(model, forKey: modelDefaultsKey)
      defaults.set(maximumAnswerCharacters, forKey: answerLengthDefaultsKey)
    case .clear:
      defaults.removeObject(forKey: endpointDefaultsKey)
      defaults.removeObject(forKey: modelDefaultsKey)
      defaults.removeObject(forKey: answerLengthDefaultsKey)
    case .restore(let endpoint, let model, let maximumAnswerCharacters):
      set(endpoint, forKey: endpointDefaultsKey, in: defaults)
      set(model, forKey: modelDefaultsKey, in: defaults)
      set(maximumAnswerCharacters, forKey: answerLengthDefaultsKey, in: defaults)
    }
  }

  private static func apply(
    _ mutation: AIUsageDefaultsMutation,
    to defaults: UserDefaults
  ) {
    switch mutation {
    case .saveMonthlyLimit(let value):
      defaults.set(value, forKey: monthlyLimitDefaultsKey)
    case .restoreMonthlyLimit(let value):
      set(value, forKey: monthlyLimitDefaultsKey, in: defaults)
    }
  }

  private static func set(
    _ value: Any?,
    forKey key: String,
    in defaults: UserDefaults
  ) {
    if let value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }
}

private enum InjectedError: Error, Equatable {
  case credentialLoad
  case credentialTemporarilyUnavailable
  case credentialWrite
  case defaultsWrite
}

private final class InMemoryCredentialStore: APICredentialStoring {
  private var apiKey: String?
  private(set) var saveInvocations: [String?] = []
  var failsToLoad = false
  var isTemporarilyUnavailableToLoad = false
  var failingAPIKeys: Set<String> = []

  func loadAPIKey() throws -> String? {
    if isTemporarilyUnavailableToLoad {
      throw InjectedError.credentialTemporarilyUnavailable
    }
    if failsToLoad {
      throw InjectedError.credentialLoad
    }
    return apiKey
  }

  func saveAPIKey(_ apiKey: String?) throws {
    saveInvocations.append(apiKey)
    if let apiKey, failingAPIKeys.contains(apiKey) {
      throw InjectedError.credentialWrite
    }
    self.apiKey = apiKey
  }

  func isTemporarilyUnavailable(_ error: any Error) -> Bool {
    error as? InjectedError == .credentialTemporarilyUnavailable
  }

  func resetSaveInvocations() {
    saveInvocations = []
  }
}

private actor RecordingConnectionTester: AIConnectionTesting {
  private var configurations: [OpenAIResponsesConfiguration] = []

  func testConnection(configuration: OpenAIResponsesConfiguration) async throws {
    configurations.append(configuration)
  }

  func recordedConfigurations() -> [OpenAIResponsesConfiguration] {
    configurations
  }
}

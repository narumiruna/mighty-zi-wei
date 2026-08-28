import Foundation
import Observation
import Security

struct OpenAIResponsesConfiguration: Equatable, Sendable {
    let endpoint: URL
    let model: String
    let apiKey: String?
    let maximumAnswerCharacters: Int

    init(
        endpoint: String,
        model: String,
        apiKey: String?,
        maximumAnswerCharacters: Int = 1_200
    ) throws {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            var components = URLComponents(string: trimmedEndpoint),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false
        else {
            throw ValidationError.invalidEndpoint
        }
        guard components.user == nil, components.password == nil else {
            throw ValidationError.embeddedCredentials
        }
        guard !trimmedModel.isEmpty else {
            throw ValidationError.missingModel
        }

        components.percentEncodedPath = Self.responsesPath(
            from: components.percentEncodedPath
        )
        guard let url = components.url else {
            throw ValidationError.invalidEndpoint
        }

        self.endpoint = url
        self.model = trimmedModel
        self.apiKey = trimmedAPIKey?.isEmpty == false ? trimmedAPIKey : nil
        self.maximumAnswerCharacters = min(max(maximumAnswerCharacters, 300), 2_000)
    }

    private static func responsesPath(from path: String) -> String {
        let pathWithoutTrailingSlashes = path.replacing(
            /\/+$/,
            with: ""
        )
        let lastComponent = pathWithoutTrailingSlashes
            .split(separator: "/")
            .last
            .flatMap { String($0).removingPercentEncoding }?
            .lowercased()

        if lastComponent == "responses" {
            return pathWithoutTrailingSlashes
        }
        return "\(pathWithoutTrailingSlashes)/responses"
    }

    enum ValidationError: LocalizedError, Equatable {
        case invalidEndpoint
        case embeddedCredentials
        case missingModel

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                "請輸入包含主機名稱的完整 HTTPS Responses API URL。"
            case .embeddedCredentials:
                "API URL 不得包含帳號或密碼。"
            case .missingModel:
                "請輸入 model identifier。"
            }
        }
    }
}

struct AIConfigurationDraft: Equatable, Sendable {
    var endpoint: String
    var model: String
    var apiKey: String
    var maximumAnswerCharacters: Int
    var monthlyLimit: Int
}

protocol APICredentialStoring {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String?) throws
}

struct KeychainAPICredentialStore: APICredentialStoring {
    private let service = "dev.narumi.MightyZiWei.openai-responses"
    private let account = "api-key"

    func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialError.keychain(status)
        }
        guard let apiKey = String(data: data, encoding: .utf8) else {
            throw CredentialError.invalidData
        }
        return apiKey
    }

    func saveAPIKey(_ apiKey: String?) throws {
        let normalizedAPIKey = apiKey?.isEmpty == false ? apiKey : nil
        guard let normalizedAPIKey else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: Data(normalizedAPIKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialError.keychain(updateStatus)
        }

        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialError.keychain(addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    enum CredentialError: LocalizedError, Equatable {
        case keychain(OSStatus)
        case invalidData

        var errorDescription: String? {
            "目前無法安全存取 API key，請稍後再試。"
        }
    }
}

enum AIConfigurationDefaultsMutation: Equatable {
    case save(endpoint: String, model: String, maximumAnswerCharacters: Int)
    case clear
    case restore(endpoint: String?, model: String?, maximumAnswerCharacters: Int?)
}

@MainActor
@Observable
final class AIConfigurationStore {
    static let defaultEndpoint = "https://api.openai.com/v1/responses"
    static let defaultMaximumAnswerCharacters = 1_200

    private enum DefaultsKey {
        static let endpoint = "ai.responses.endpoint"
        static let model = "ai.responses.model"
        static let maximumAnswerCharacters = "ai.responses.maximum-answer-characters"
    }

    struct PersistenceSnapshot: Equatable {
        let storedEndpoint: String?
        let storedModel: String?
        let storedMaximumAnswerCharacters: Int?
        let apiKey: String?
    }

    private let defaults: UserDefaults
    private let credentialStore: any APICredentialStoring
    private let defaultsWriter: (AIConfigurationDefaultsMutation) throws -> Void

    private(set) var endpoint: String
    private(set) var model: String
    private(set) var hasAPIKey: Bool
    private(set) var maximumAnswerCharacters: Int
    private(set) var requiresRecovery = false

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any APICredentialStoring = KeychainAPICredentialStore(),
        defaultsWriter: ((AIConfigurationDefaultsMutation) throws -> Void)? = nil
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.defaultsWriter = defaultsWriter ?? { mutation in
            Self.apply(mutation, to: defaults)
        }
        endpoint = defaults.string(forKey: DefaultsKey.endpoint) ?? Self.defaultEndpoint
        model = defaults.string(forKey: DefaultsKey.model) ?? ""
        let storedMaximum = defaults.integer(forKey: DefaultsKey.maximumAnswerCharacters)
        maximumAnswerCharacters = storedMaximum == 0
            ? Self.defaultMaximumAnswerCharacters
            : min(max(storedMaximum, 300), 2_000)
        do {
            hasAPIKey = try credentialStore.loadAPIKey() != nil
        } catch {
            hasAPIKey = false
            requiresRecovery = true
        }
    }

    var isConfigured: Bool {
        !requiresRecovery
            && (try? OpenAIResponsesConfiguration(
                endpoint: endpoint,
                model: model,
                apiKey: nil,
                maximumAnswerCharacters: maximumAnswerCharacters
            )) != nil
    }

    var hasStoredValues: Bool {
        endpoint != Self.defaultEndpoint
            || !model.isEmpty
            || hasAPIKey
            || maximumAnswerCharacters != Self.defaultMaximumAnswerCharacters
            || requiresRecovery
    }

    func loadAPIKey() throws -> String {
        try credentialStore.loadAPIKey() ?? ""
    }

    func configuration() throws -> OpenAIResponsesConfiguration {
        guard !requiresRecovery else {
            throw AIConfigurationCommitError.recoveryRequired
        }
        return try OpenAIResponsesConfiguration(
            endpoint: endpoint,
            model: model,
            apiKey: credentialStore.loadAPIKey(),
            maximumAnswerCharacters: maximumAnswerCharacters
        )
    }

    func save(endpoint: String, model: String, apiKey: String) throws {
        let snapshot = try makePersistenceSnapshot()
        let configuration = try OpenAIResponsesConfiguration(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            maximumAnswerCharacters: maximumAnswerCharacters
        )
        do {
            try saveAPIKey(configuration.apiKey)
            try apply(
                configuration: configuration,
                maximumAnswerCharacters: maximumAnswerCharacters
            )
            finishRecovery()
        } catch {
            try rollbackOrEnterRecovery(snapshot: snapshot, originalError: error)
        }
    }

    func setMaximumAnswerCharacters(_ value: Int) {
        let normalized = min(max(value, 300), 2_000)
        do {
            try defaultsWriter(.save(
                endpoint: endpoint,
                model: model,
                maximumAnswerCharacters: normalized
            ))
            maximumAnswerCharacters = normalized
        } catch {
            // UserDefaults 的 production 寫入不會拋錯；可錯誤注入流程由提交協調器處理。
        }
    }

    func clear() throws {
        let snapshot = try makePersistenceSnapshot()
        do {
            try saveAPIKey(nil)
            try applyClearedDefaults()
            finishRecovery()
        } catch {
            try rollbackOrEnterRecovery(snapshot: snapshot, originalError: error)
        }
    }

    func makePersistenceSnapshot() throws -> PersistenceSnapshot {
        PersistenceSnapshot(
            storedEndpoint: defaults.string(forKey: DefaultsKey.endpoint),
            storedModel: defaults.string(forKey: DefaultsKey.model),
            storedMaximumAnswerCharacters: defaults.object(
                forKey: DefaultsKey.maximumAnswerCharacters
            ) == nil ? nil : defaults.integer(forKey: DefaultsKey.maximumAnswerCharacters),
            apiKey: try credentialStore.loadAPIKey()
        )
    }

    func saveAPIKey(_ apiKey: String?) throws {
        try credentialStore.saveAPIKey(apiKey)
        hasAPIKey = apiKey?.isEmpty == false
    }

    func apply(
        configuration: OpenAIResponsesConfiguration,
        maximumAnswerCharacters: Int
    ) throws {
        try defaultsWriter(.save(
            endpoint: configuration.endpoint.absoluteString,
            model: configuration.model,
            maximumAnswerCharacters: maximumAnswerCharacters
        ))
        endpoint = configuration.endpoint.absoluteString
        model = configuration.model
        self.maximumAnswerCharacters = maximumAnswerCharacters
        hasAPIKey = configuration.apiKey != nil
    }

    func applyClearedDefaults() throws {
        try defaultsWriter(.clear)
        endpoint = Self.defaultEndpoint
        model = ""
        maximumAnswerCharacters = Self.defaultMaximumAnswerCharacters
        hasAPIKey = false
    }

    func restoreDefaults(from snapshot: PersistenceSnapshot) throws {
        try defaultsWriter(.restore(
            endpoint: snapshot.storedEndpoint,
            model: snapshot.storedModel,
            maximumAnswerCharacters: snapshot.storedMaximumAnswerCharacters
        ))
        endpoint = snapshot.storedEndpoint ?? Self.defaultEndpoint
        model = snapshot.storedModel ?? ""
        let maximum = snapshot.storedMaximumAnswerCharacters ?? Self.defaultMaximumAnswerCharacters
        maximumAnswerCharacters = min(max(maximum, 300), 2_000)
        hasAPIKey = snapshot.apiKey != nil
    }

    func restoreAPIKey(from snapshot: PersistenceSnapshot) throws {
        try credentialStore.saveAPIKey(snapshot.apiKey)
        hasAPIKey = snapshot.apiKey != nil
    }

    func enterRecoveryMode() {
        defaults.removeObject(forKey: DefaultsKey.endpoint)
        defaults.removeObject(forKey: DefaultsKey.model)
        endpoint = defaults.string(forKey: DefaultsKey.endpoint) ?? Self.defaultEndpoint
        model = defaults.string(forKey: DefaultsKey.model) ?? ""
        let storedMaximum = defaults.integer(forKey: DefaultsKey.maximumAnswerCharacters)
        maximumAnswerCharacters = storedMaximum == 0
            ? Self.defaultMaximumAnswerCharacters
            : min(max(storedMaximum, 300), 2_000)
        hasAPIKey = ((try? credentialStore.loadAPIKey()) ?? nil) != nil
        requiresRecovery = true
    }

    func discardRecoveryConfiguration() throws {
        do {
            try credentialStore.saveAPIKey(nil)
            try applyClearedDefaults()
            finishRecovery()
        } catch {
            enterRecoveryMode()
            throw AIConfigurationCommitError.recoveryRequired
        }
    }

    func finishRecovery() {
        requiresRecovery = false
    }

    private func rollbackOrEnterRecovery(
        snapshot: PersistenceSnapshot,
        originalError: any Error
    ) throws -> Never {
        var rollbackFailed = false
        do {
            try restoreDefaults(from: snapshot)
        } catch {
            rollbackFailed = true
        }
        do {
            try restoreAPIKey(from: snapshot)
        } catch {
            rollbackFailed = true
        }
        if rollbackFailed {
            enterRecoveryMode()
            throw AIConfigurationCommitError.recoveryRequired
        }
        throw originalError
    }

    private static func apply(
        _ mutation: AIConfigurationDefaultsMutation,
        to defaults: UserDefaults
    ) {
        switch mutation {
        case .save(let endpoint, let model, let maximumAnswerCharacters):
            defaults.set(endpoint, forKey: DefaultsKey.endpoint)
            defaults.set(model, forKey: DefaultsKey.model)
            defaults.set(
                maximumAnswerCharacters,
                forKey: DefaultsKey.maximumAnswerCharacters
            )
        case .clear:
            defaults.removeObject(forKey: DefaultsKey.endpoint)
            defaults.removeObject(forKey: DefaultsKey.model)
            defaults.removeObject(forKey: DefaultsKey.maximumAnswerCharacters)
        case .restore(let endpoint, let model, let maximumAnswerCharacters):
            set(endpoint, forKey: DefaultsKey.endpoint, in: defaults)
            set(model, forKey: DefaultsKey.model, in: defaults)
            set(
                maximumAnswerCharacters,
                forKey: DefaultsKey.maximumAnswerCharacters,
                in: defaults
            )
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

protocol AIConnectionTesting: Sendable {
    func testConnection(configuration: OpenAIResponsesConfiguration) async throws
}

struct OpenAIConnectionTester: AIConnectionTesting {
    func testConnection(configuration: OpenAIResponsesConfiguration) async throws {
        try await OpenAIResponsesInterpreter().testConnection(configuration: configuration)
    }
}

enum AIConfigurationCommitError: LocalizedError, Equatable {
    case invalidAnswerLength
    case invalidMonthlyLimit
    case recoveryRequired

    var errorDescription: String? {
        switch self {
        case .invalidAnswerLength:
            "回答長度必須介於 300 到 2,000 字。"
        case .invalidMonthlyLimit:
            "每月請求上限不得小於 0。"
        case .recoveryRequired:
            "無法完整回復先前的 API 設定，AI 已停用。請重新檢查所有欄位並再次儲存。"
        }
    }
}

@MainActor
@Observable
final class AIConfigurationCommitCoordinator {
    private let configurationStore: AIConfigurationStore
    private let usageStore: AIUsageStore
    private let connectionTester: any AIConnectionTesting

    private(set) var recoveryMessage: String?

    init(
        configurationStore: AIConfigurationStore,
        usageStore: AIUsageStore,
        connectionTester: any AIConnectionTesting = OpenAIConnectionTester()
    ) {
        self.configurationStore = configurationStore
        self.usageStore = usageStore
        self.connectionTester = connectionTester
        recoveryMessage = configurationStore.requiresRecovery
            ? AIConfigurationCommitError.recoveryRequired.errorDescription
            : nil
    }

    var hasStoredValues: Bool { configurationStore.hasStoredValues }
    var currentMonthCount: Int { usageStore.refreshedCurrentMonthCount() }
    var lastDiagnostic: String? { usageStore.lastDiagnostic }

    func remainingRequests(for monthlyLimit: Int) -> Int? {
        usageStore.remainingRequests(for: monthlyLimit)
    }

    func makeDraft() throws -> AIConfigurationDraft {
        AIConfigurationDraft(
            endpoint: configurationStore.endpoint,
            model: configurationStore.model,
            apiKey: try configurationStore.loadAPIKey(),
            maximumAnswerCharacters: configurationStore.maximumAnswerCharacters,
            monthlyLimit: usageStore.monthlyLimit
        )
    }

    func testConnection(draft: AIConfigurationDraft) async throws {
        do {
            let configuration = try validatedConfiguration(for: draft)
            try usageStore.reserve(.connectionTest)
            try await connectionTester.testConnection(configuration: configuration)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            usageStore.record(error: error, kind: .connectionTest)
            throw error
        }
    }

    func commit(draft: AIConfigurationDraft) throws {
        let snapshot = try makeSnapshot()
        let configuration = try validatedConfiguration(for: draft)
        do {
            try configurationStore.saveAPIKey(configuration.apiKey)
            try configurationStore.apply(
                configuration: configuration,
                maximumAnswerCharacters: draft.maximumAnswerCharacters
            )
            try usageStore.applyMonthlyLimit(draft.monthlyLimit)
            configurationStore.finishRecovery()
            recoveryMessage = nil
        } catch {
            try rollbackOrEnterRecovery(snapshot: snapshot, originalError: error)
        }
    }

    func clear() throws {
        let snapshot = try makeSnapshot()
        do {
            try configurationStore.saveAPIKey(nil)
            try configurationStore.applyClearedDefaults()
            configurationStore.finishRecovery()
            recoveryMessage = nil
        } catch {
            try rollbackOrEnterRecovery(snapshot: snapshot, originalError: error)
        }
    }

    func discardRecoveryConfiguration() throws {
        try configurationStore.discardRecoveryConfiguration()
        recoveryMessage = nil
    }

    private struct Snapshot {
        let configuration: AIConfigurationStore.PersistenceSnapshot
        let usage: AIUsageStore.PersistenceSnapshot
    }

    private func makeSnapshot() throws -> Snapshot {
        Snapshot(
            configuration: try configurationStore.makePersistenceSnapshot(),
            usage: usageStore.makePersistenceSnapshot()
        )
    }

    private func validatedConfiguration(
        for draft: AIConfigurationDraft
    ) throws -> OpenAIResponsesConfiguration {
        guard (300...2_000).contains(draft.maximumAnswerCharacters) else {
            throw AIConfigurationCommitError.invalidAnswerLength
        }
        guard draft.monthlyLimit >= 0 else {
            throw AIConfigurationCommitError.invalidMonthlyLimit
        }
        return try OpenAIResponsesConfiguration(
            endpoint: draft.endpoint,
            model: draft.model,
            apiKey: draft.apiKey,
            maximumAnswerCharacters: draft.maximumAnswerCharacters
        )
    }

    private func rollbackOrEnterRecovery(
        snapshot: Snapshot,
        originalError: any Error
    ) throws -> Never {
        var rollbackFailed = false
        do {
            try configurationStore.restoreDefaults(from: snapshot.configuration)
        } catch {
            rollbackFailed = true
        }
        do {
            try usageStore.restore(from: snapshot.usage)
        } catch {
            rollbackFailed = true
        }
        do {
            try configurationStore.restoreAPIKey(from: snapshot.configuration)
        } catch {
            rollbackFailed = true
        }

        if rollbackFailed {
            configurationStore.enterRecoveryMode()
            recoveryMessage = AIConfigurationCommitError.recoveryRequired.errorDescription
            throw AIConfigurationCommitError.recoveryRequired
        }
        throw originalError
    }
}

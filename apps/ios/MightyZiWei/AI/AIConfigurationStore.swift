import Foundation
import Observation
import Security

struct OpenAIResponsesConfiguration: Equatable, Sendable {
    let endpoint: URL
    let model: String
    let apiKey: String?

    init(endpoint: String, model: String, apiKey: String?) throws {
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
        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw CredentialError.keychain(deleteStatus)
        }

        guard let apiKey, !apiKey.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data(apiKey.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychain(status)
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

@MainActor
@Observable
final class AIConfigurationStore {
    static let defaultEndpoint = "https://api.openai.com/v1/responses"

    private enum DefaultsKey {
        static let endpoint = "ai.responses.endpoint"
        static let model = "ai.responses.model"
    }

    private let defaults: UserDefaults
    private let credentialStore: any APICredentialStoring

    private(set) var endpoint: String
    private(set) var model: String
    private(set) var hasAPIKey: Bool

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any APICredentialStoring = KeychainAPICredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
        endpoint = defaults.string(forKey: DefaultsKey.endpoint) ?? Self.defaultEndpoint
        model = defaults.string(forKey: DefaultsKey.model) ?? ""
        hasAPIKey = ((try? credentialStore.loadAPIKey()) ?? nil) != nil
    }

    var isConfigured: Bool {
        (try? OpenAIResponsesConfiguration(endpoint: endpoint, model: model, apiKey: nil)) != nil
    }

    var hasStoredValues: Bool {
        endpoint != Self.defaultEndpoint || !model.isEmpty || hasAPIKey
    }

    func loadAPIKey() throws -> String {
        try credentialStore.loadAPIKey() ?? ""
    }

    func configuration() throws -> OpenAIResponsesConfiguration {
        try OpenAIResponsesConfiguration(
            endpoint: endpoint,
            model: model,
            apiKey: credentialStore.loadAPIKey()
        )
    }

    func save(endpoint: String, model: String, apiKey: String) throws {
        let configuration = try OpenAIResponsesConfiguration(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey
        )
        try credentialStore.saveAPIKey(configuration.apiKey)
        defaults.set(configuration.endpoint.absoluteString, forKey: DefaultsKey.endpoint)
        defaults.set(configuration.model, forKey: DefaultsKey.model)
        self.endpoint = configuration.endpoint.absoluteString
        self.model = configuration.model
        hasAPIKey = configuration.apiKey != nil
    }

    func clear() throws {
        try credentialStore.saveAPIKey(nil)
        defaults.removeObject(forKey: DefaultsKey.endpoint)
        defaults.removeObject(forKey: DefaultsKey.model)
        endpoint = Self.defaultEndpoint
        model = ""
        hasAPIKey = false
    }
}

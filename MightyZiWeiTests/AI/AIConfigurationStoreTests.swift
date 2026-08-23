import Foundation
import XCTest
@testable import MightyZiWei

@MainActor
final class AIConfigurationStoreTests: XCTestCase {
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
}

private final class InMemoryCredentialStore: APICredentialStoring {
    private var apiKey: String?

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String?) throws {
        self.apiKey = apiKey
    }
}

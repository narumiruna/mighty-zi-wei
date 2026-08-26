import Foundation
import Observation

@MainActor
@Observable
final class AIUsageStore {
    enum RequestKind: String, Sendable {
        case conversation = "命盤問答"
        case interpretation = "解讀整理"
        case connectionTest = "連線測試"
    }

    enum UsageError: LocalizedError, Equatable {
        case monthlyLimitReached(Int)

        var errorDescription: String? {
            switch self {
            case .monthlyLimitReached(let limit):
                "本月已達你設定的 \(limit) 次 API 請求上限。可在設定調高上限，或等下個月再使用。"
            }
        }
    }

    private enum Key {
        static let monthlyLimit = "ai.usage.monthly-limit"
        static let month = "ai.usage.month"
        static let count = "ai.usage.count"
        static let lastDiagnostic = "ai.usage.last-diagnostic"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    var monthlyLimit: Int {
        didSet {
            if monthlyLimit < 0 {
                monthlyLimit = 0
                return
            }
            defaults.set(monthlyLimit, forKey: Key.monthlyLimit)
        }
    }
    private(set) var currentMonthCount: Int
    private(set) var lastDiagnostic: String?

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        monthlyLimit = defaults.object(forKey: Key.monthlyLimit) == nil
            ? 50
            : max(0, defaults.integer(forKey: Key.monthlyLimit))
        currentMonthCount = defaults.integer(forKey: Key.count)
        lastDiagnostic = defaults.string(forKey: Key.lastDiagnostic)
        resetMonthIfNeeded()
    }

    var remainingRequests: Int? {
        resetMonthIfNeeded()
        guard monthlyLimit > 0 else { return nil }
        return max(0, monthlyLimit - currentMonthCount)
    }

    func reserve(_ kind: RequestKind) throws {
        resetMonthIfNeeded()
        if monthlyLimit > 0, currentMonthCount >= monthlyLimit {
            throw UsageError.monthlyLimitReached(monthlyLimit)
        }
        currentMonthCount += 1
        defaults.set(currentMonthCount, forKey: Key.count)
        defaults.set(Self.monthKey(date: .now, calendar: calendar), forKey: Key.month)
    }

    func record(error: Error, kind: RequestKind) {
        let code: String
        if let interpreterError = error as? OpenAIResponsesInterpreter.InterpreterError {
            code = interpreterError.diagnosticCode
        } else if error is OpenAIResponsesConfiguration.ValidationError {
            code = "configuration_invalid"
        } else if error is KeychainAPICredentialStore.CredentialError {
            code = "credential_unavailable"
        } else if error is UsageError {
            code = "monthly_limit_reached"
        } else if error is CancellationError {
            code = "cancelled"
        } else {
            code = "unexpected_error"
        }
        record(code: code, kind: kind)
    }

    func record(code: String, kind: RequestKind) {
        let diagnostic = [
            "MightyZiWei AI 診斷",
            "時間：\(Date.now.formatted(.iso8601))",
            "操作：\(kind.rawValue)",
            "錯誤代碼：\(code)",
            "本月請求：\(currentMonthCount)",
            "月上限：\(monthlyLimit == 0 ? "未設定" : String(monthlyLimit))",
            "系統：iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "不包含 API key、endpoint、prompt、命盤或回應內容。"
        ].joined(separator: "\n")
        lastDiagnostic = diagnostic
        defaults.set(diagnostic, forKey: Key.lastDiagnostic)
    }

    func clearDiagnostic() {
        lastDiagnostic = nil
        defaults.removeObject(forKey: Key.lastDiagnostic)
    }

    private func resetMonthIfNeeded() {
        let current = Self.monthKey(date: .now, calendar: calendar)
        guard defaults.string(forKey: Key.month) != current else { return }
        currentMonthCount = 0
        defaults.set(current, forKey: Key.month)
        defaults.set(0, forKey: Key.count)
    }

    private static func monthKey(date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", values.year ?? 0, values.month ?? 0)
    }
}

extension OpenAIResponsesInterpreter.InterpreterError {
    var diagnosticCode: String {
        switch self {
        case .invalidRequest: "request_invalid"
        case .connectionFailed: "connection_failed"
        case .timedOut: "timeout"
        case .unauthorized: "authorization_failed"
        case .rateLimited: "provider_rate_limited"
        case .httpError(let status): "http_\(status)"
        case .refusal: "provider_refusal"
        case .emptyResponse: "response_empty"
        case .invalidResponse: "response_invalid"
        case .responseTooLarge: "response_too_large"
        case .invalidGeneratedContent: "generated_content_invalid"
        }
    }
}

import AppIntents
import Foundation

enum PinnedChartShortcut {
    static let key = "shortcuts.pinned-chart-id"

    static func reconcile(
        charts: [SavedChart],
        defaults: UserDefaults? = UserDefaults(
            suiteName: ReviewReminderScheduler.sharedDefaultsSuite
        )
    ) {
        let pinned = charts
            .filter(\.isPinned)
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .first
        if let pinned {
            defaults?.set(pinned.id.uuidString, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }
}

enum ShortcutBridge {
    static let suite = ReviewReminderScheduler.sharedDefaultsSuite
    static let pendingActionKey = "shortcuts.pending-action"
    static let pendingDraftKey = "shortcuts.pending-ai-draft"
    static let actionDidChangeNotification = Notification.Name(
        "MightyZiWei.shortcut-action-did-change"
    )

    static func setAction(
        _ action: String,
        draft: String? = nil,
        defaults: UserDefaults? = UserDefaults(suiteName: suite),
        notificationCenter: NotificationCenter = .default
    ) {
        defaults?.set(action, forKey: pendingActionKey)
        if let draft {
            defaults?.set(draft, forKey: pendingDraftKey)
        } else {
            defaults?.removeObject(forKey: pendingDraftKey)
        }
        notificationCenter.post(name: actionDidChangeNotification, object: nil)
    }
}

struct OpenPinnedChartIntent: AppIntent {
    static let title: LocalizedStringResource = "開啟釘選命盤"
    static let description = IntentDescription("開啟很牛的紫微斗數，前往目前釘選的常用命盤。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutBridge.setAction("open-pinned")
        return .result()
    }
}

struct AddPinnedChartNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "新增觀察筆記"
    static let description = IntentDescription("開啟目前釘選命盤的觀察時間軸；不會產生命盤預測。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutBridge.setAction("new-note")
        return .result()
    }
}

struct PrepareChartQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "準備命盤 AI 問題"
    static let description = IntentDescription("把問題放入可編輯草稿；不會自動送出或產生 API 費用。")
    static let openAppWhenRun = true

    @Parameter(title: "問題")
    var question: String

    func perform() async throws -> some IntentResult {
        ShortcutBridge.setAction("ai-draft", draft: String(question.prefix(500)))
        return .result()
    }
}

struct MightyZiWeiAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPinnedChartIntent(),
            phrases: ["在 \(.applicationName) 開啟釘選命盤"],
            shortTitle: "開啟釘選命盤",
            systemImageName: "pin"
        )
        AppShortcut(
            intent: AddPinnedChartNoteIntent(),
            phrases: ["在 \(.applicationName) 新增觀察筆記"],
            shortTitle: "新增觀察筆記",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: PrepareChartQuestionIntent(),
            phrases: ["在 \(.applicationName) 準備命盤問題"],
            shortTitle: "準備命盤問題",
            systemImageName: "text.bubble"
        )
    }
}

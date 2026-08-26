import Foundation
import UserNotifications
import WidgetKit

struct ReviewReminderScheduler: Sendable {
    static let sharedDefaultsSuite = "group.dev.narumi.MightyZiWei"
    static let nextReminderKey = "privacy-widget.next-review-date"
    static let reminderDatesKey = "privacy-widget.review-dates"
    static let privacyWidgetKind = "MightyZiWeiPrivacyWidget"

    enum ReminderError: LocalizedError {
        case permissionDenied
        case invalidDate

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "尚未允許通知。請到 iOS「設定」開啟通知後再試。"
            case .invalidDate:
                "回顧時間必須晚於現在。"
            }
        }
    }

    func schedule(
        insightID: UUID,
        chartName: String,
        title: String,
        date: Date
    ) async throws -> String {
        guard date > .now else { throw ReminderError.invalidDate }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            guard allowed else { throw ReminderError.permissionDenied }
        } else if settings.authorizationStatus == .denied {
            throw ReminderError.permissionDenied
        }

        let identifier = Self.makeIdentifier(insightID: insightID)
        let content = UNMutableNotificationContent()
        content.title = "回顧你的觀察筆記"
        content.body = "你曾為「\(chartName)」記下「\(title)」。這是你自行設定的回顧提醒，不是命盤預測。"
        content.sound = .default
        content.userInfo = ["insightID": insightID.uuidString]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        ))
        await refreshWidgetReminder(center: center)
        return identifier
    }

    static func makeIdentifier(insightID: UUID) -> String {
        "review.\(insightID.uuidString).\(UUID().uuidString)"
    }

    static func storeWidgetReminderDates(
        _ dates: [Date],
        now: Date = .now,
        defaults: UserDefaults?
    ) {
        let timestamps = Array(Set(
            dates.filter { $0 > now }.map(\.timeIntervalSince1970)
        )).sorted()
        defaults?.set(timestamps, forKey: reminderDatesKey)
        defaults?.removeObject(forKey: nextReminderKey)
    }

    func cancel(identifier: String?) {
        guard let identifier else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        Task { await refreshWidgetReminder(center: center) }
    }

    private func refreshWidgetReminder(center: UNUserNotificationCenter) async {
        let requests = await center.pendingNotificationRequests()
        let dates: [Date] = requests.compactMap { request -> Date? in
            guard request.identifier.hasPrefix("review.") else { return nil }
            return (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }
        let defaults = UserDefaults(suiteName: Self.sharedDefaultsSuite)
        Self.storeWidgetReminderDates(dates, defaults: defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.privacyWidgetKind)
    }
}

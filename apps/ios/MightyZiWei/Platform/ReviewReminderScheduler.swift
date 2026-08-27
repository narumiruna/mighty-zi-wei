import Foundation
import UserNotifications
import WidgetKit

struct ReviewReminderScheduler: Sendable {
    static let sharedDefaultsSuite = "group.dev.narumi.MightyZiWei"
    static let nextReminderKey = "privacy-widget.next-review-date"
    static let reminderDatesKey = "privacy-widget.review-dates"
    static let privacyWidgetKind = "MightyZiWeiPrivacyWidget"
    static let reminderIdentifierPrefix = "review."

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
        return try await addReminder(
            insightID: insightID,
            chartName: chartName,
            title: title,
            date: date,
            center: center
        )
    }

    func scheduleSyncedReminder(
        insightID: UUID,
        chartName: String,
        title: String,
        date: Date
    ) async throws -> String? {
        guard date > .now else { return nil }
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return try await addReminder(
                insightID: insightID,
                chartName: chartName,
                title: title,
                date: date,
                center: center
            )
        case .denied, .notDetermined:
            return nil
        @unknown default:
            return nil
        }
    }

    static func makeIdentifier(insightID: UUID) -> String {
        "\(reminderIdentifierPrefix)\(insightID.uuidString).\(UUID().uuidString)"
    }

    static func reviewReminderIdentifiers(in identifiers: [String]) -> [String] {
        identifiers.filter { $0.hasPrefix(reminderIdentifierPrefix) }
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

    func cancelAllReviewReminders() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let identifiers = Self.reviewReminderIdentifiers(
            in: requests.map(\.identifier)
        )
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        let defaults = UserDefaults(suiteName: Self.sharedDefaultsSuite)
        Self.storeWidgetReminderDates([], defaults: defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.privacyWidgetKind)
    }

    private func addReminder(
        insightID: UUID,
        chartName: String,
        title: String,
        date: Date,
        center: UNUserNotificationCenter
    ) async throws -> String {
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

    private func refreshWidgetReminder(center: UNUserNotificationCenter) async {
        let requests = await center.pendingNotificationRequests()
        let dates: [Date] = requests.compactMap { request -> Date? in
            guard request.identifier.hasPrefix(Self.reminderIdentifierPrefix) else { return nil }
            return (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        }
        let defaults = UserDefaults(suiteName: Self.sharedDefaultsSuite)
        Self.storeWidgetReminderDates(dates, defaults: defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.privacyWidgetKind)
    }
}

import SwiftUI
import WidgetKit

private struct PrivacyEntry: TimelineEntry {
    let date: Date
    let nextReviewDate: Date?
}

private struct PrivacyProvider: TimelineProvider {
    private let suite = "group.dev.narumi.MightyZiWei"
    private let reminderDatesKey = "privacy-widget.review-dates"

    func placeholder(in context: Context) -> PrivacyEntry {
        PrivacyEntry(date: .now, nextReviewDate: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrivacyEntry) -> Void) {
        let now = Date.now
        completion(entry(at: now, reminders: storedReminders(after: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrivacyEntry>) -> Void) {
        let now = Date.now
        let reminders = storedReminders(after: now)
        var entries = [entry(at: now, reminders: reminders)]
        for (index, reminder) in reminders.enumerated() {
            entries.append(PrivacyEntry(
                date: reminder.addingTimeInterval(1),
                nextReviewDate: reminders.dropFirst(index + 1).first
            ))
        }
        let refresh = (reminders.last ?? now).addingTimeInterval(3_600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func storedReminders(after date: Date) -> [Date] {
        let values = UserDefaults(suiteName: suite)?
            .array(forKey: reminderDatesKey) as? [Double] ?? []
        return values
            .map(Date.init(timeIntervalSince1970:))
            .filter { $0 > date }
            .sorted()
    }

    private func entry(at date: Date, reminders: [Date]) -> PrivacyEntry {
        PrivacyEntry(date: date, nextReviewDate: reminders.first)
    }
}

private struct PrivacyWidgetView: View {
    let entry: PrivacyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("觀察回顧", systemImage: "eye")
                .font(.headline)
            if let date = entry.nextReviewDate {
                Text("下一次自訂提醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(date, style: .relative)
                    .font(.title3.bold())
            } else {
                Text("尚未設定回顧提醒")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: "mightyziwei://saved")!) {
                Label("開啟 App", systemImage: "arrow.up.forward.app")
                    .font(.caption.weight(.semibold))
            }
        }
        .containerBackground(.background, for: .widget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let date = entry.nextReviewDate {
            return "觀察回顧，下一次自訂提醒在\(date.formatted(date: .long, time: .shortened))。不顯示命盤姓名或出生資料。"
        }
        return "觀察回顧，尚未設定提醒。不顯示命盤姓名或出生資料。"
    }
}

struct MightyZiWeiPrivacyWidget: Widget {
    let kind = "MightyZiWeiPrivacyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrivacyProvider()) { entry in
            PrivacyWidgetView(entry: entry)
        }
        .configurationDisplayName("隱私回顧")
        .description("只顯示使用者自訂回顧提醒與 App 捷徑，不顯示姓名或出生資料。")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct MightyZiWeiPrivacyWidgetBundle: WidgetBundle {
    var body: some Widget {
        MightyZiWeiPrivacyWidget()
    }
}

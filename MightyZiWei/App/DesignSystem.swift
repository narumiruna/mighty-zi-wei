import SwiftUI

enum AppDesign {
    static let cornerRadius: CGFloat = 20
    static let compactCornerRadius: CGFloat = 14
    static let pageSpacing: CGFloat = 24
    static let cardSpacing: CGFloat = 16
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppDesign.cardSpacing)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }
}

struct DisclaimerView: View {
    var compact = false

    var body: some View {
        Label {
            Text("命理解讀只供娛樂與自我反思，不應取代專業意見或重大人生決策。")
                .font(compact ? .caption : .callout)
        } icon: {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

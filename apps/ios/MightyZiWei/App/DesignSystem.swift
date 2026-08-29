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
  var actionTitle: String?
  var actionSymbol: String?
  var action: (() -> Void)?

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: symbol)
    } description: {
      Text(message)
    } actions: {
      if let actionTitle, let action {
        Button(action: action) {
          if let actionSymbol {
            Label(actionTitle, systemImage: actionSymbol)
          } else {
            Text(actionTitle)
          }
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }
}

enum InlineStatusStyle {
  case information
  case success
  case warning
  case error

  var symbol: String {
    switch self {
    case .information: "info.circle.fill"
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .error: "xmark.octagon.fill"
    }
  }

  var color: Color {
    switch self {
    case .information: .secondary
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
  }
}

struct InlineStatusView: View {
  let style: InlineStatusStyle
  let message: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        Text(message)
          .foregroundStyle(.primary)
      } icon: {
        Image(systemName: style.symbol)
          .foregroundStyle(style.color)
      }

      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.bordered)
      }
    }
    .font(.subheadline)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardStyle()
    .accessibilityElement(children: .contain)
  }
}

struct DisabledReasonView: View {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var body: some View {
    Label(message, systemImage: "info.circle")
      .font(.callout.weight(.medium))
      .foregroundStyle(Color.primary)
      .accessibilityElement(children: .combine)
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

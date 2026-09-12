import SwiftUI

enum AppDesign {
  static let cornerRadius: CGFloat = 20
  static let compactCornerRadius: CGFloat = 14
  static let pageSpacing: CGFloat = 24
  static let cardSpacing: CGFloat = 16
  static let pageInset: CGFloat = 20
  static let readingWidth: CGFloat = 680

  static let canvas = Color("PageBackground")
  static let surface = Color("CardBackground")
  static let secondaryText = Color("SecondaryText")
  static let ink = Color(red: 0.17, green: 0.12, blue: 0.25)
  static let gold = Color(red: 0.86, green: 0.75, blue: 0.56)
}

struct CardStyle: ViewModifier {
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content
      .padding(AppDesign.cardSpacing)
      .background(AppDesign.surface, in: RoundedRectangle(cornerRadius: AppDesign.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: AppDesign.cornerRadius)
          .strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : 0.06), lineWidth: 1)
          .allowsHitTesting(false)
      }
  }
}

extension View {
  func cardStyle() -> some View {
    modifier(CardStyle())
  }

  func appPageBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(AppDesign.canvas)
  }
}

struct PrimaryActionStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, minHeight: 52)
      .foregroundStyle(colorScheme == .dark ? AppDesign.ink : .white)
      .background(
        (colorScheme == .dark ? Color.accentColor : AppDesign.ink)
          .opacity(isEnabled ? 1 : 0.45),
        in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
          .strokeBorder(.white.opacity(0.22), lineWidth: 1)
      }
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}

struct AppSymbol: View {
  let name: String

  var body: some View {
    Image(systemName: name)
      .font(.system(size: 20, weight: .medium))
      .foregroundStyle(.tint)
      .frame(width: 44, height: 44)
      .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
      .accessibilityHidden(true)
  }
}

struct SectionHeading: View {
  let title: String
  var subtitle: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.title3.bold())
        .accessibilityAddTraits(.isHeader)
      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(AppDesign.secondaryText)
      }
    }
  }
}

struct CreateChartEmptyState: View {
  let symbol: String
  let title: String
  let message: String
  let actionIdentifier: String

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        AppSymbol(name: symbol)
        VStack(spacing: 10) {
          Text(title)
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
          Text(message)
            .font(.body)
            .foregroundStyle(AppDesign.secondaryText)
        }
        .multilineTextAlignment(.center)

        NavigationLink {
          BirthInputView()
        } label: {
          Label("排一張命盤", systemImage: "plus")
        }
        .buttonStyle(PrimaryActionStyle())
        .accessibilityIdentifier(actionIdentifier)
      }
      .padding(24)
      .cardStyle()
      .frame(maxWidth: AppDesign.readingWidth)
      .frame(maxWidth: .infinity)
      .padding(AppDesign.pageInset)
    }
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
        .foregroundStyle(AppDesign.secondaryText)
    }
    .foregroundStyle(AppDesign.secondaryText)
    .accessibilityElement(children: .combine)
  }
}

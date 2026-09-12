import SwiftUI

/// 標準字級保留十二宮方位；VoiceOver、大字級與使用者線性偏好改用依序閱讀。
struct ChartReadingGuideMap: View {
  let guide: ChartReadingGuide
  let step: ChartReadingGuide.Step

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  @AppStorage("accessibility.linear-chart") private var linearChartEnabled = false

  private let branches: [[EarthlyBranch?]] = [
    [.si, .wu, .wei, .shen],
    [.chen, nil, nil, .you],
    [.mao, nil, nil, .xu],
    [.yin, .chou, .zi, .hai],
  ]

  init(guide: ChartReadingGuide, step: ChartReadingGuide.Step) {
    self.guide = guide
    self.step = step
  }

  var body: some View {
    if dynamicTypeSize >= .xxLarge || voiceOverEnabled || linearChartEnabled {
      linearMap
    } else {
      squareMap
    }
  }

  private var linearMap: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(guide.highlightedPalaces(for: step)) { kind in
        VStack(alignment: .leading, spacing: 6) {
          Text(guide.role(for: kind, step: step))
            .font(.subheadline.weight(.semibold))
          overview(guide.chart.palace(kind))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.palace.\(kind.rawValue)")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("guide.linearMap")
  }

  private var squareMap: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("框線與下方角色文字標示本步位置；其他宮位只供方位對照。")
        .font(.caption)
        .foregroundStyle(.secondary)
      GeometryReader { geometry in
        let size = (geometry.size.width - 18) / 4
        VStack(spacing: 6) {
          ForEach(branches.indices, id: \.self) { row in
            HStack(spacing: 6) {
              ForEach(branches[row].indices, id: \.self) { column in
                if let branch = branches[row][column],
                  let palace = guide.chart.palaces.first(where: { $0.stemBranch.branch == branch })
                {
                  cell(palace, size: size)
                } else {
                  Color.clear.frame(width: size, height: size)
                    .accessibilityHidden(true)
                }
              }
            }
          }
        }
      }
      .aspectRatio(1, contentMode: .fit)
      ForEach(guide.highlightedPalaces(for: step)) { kind in
        Text(
          "\(guide.role(for: kind, step: step))：\(kind.displayName)・\(guide.chart.palace(kind).stemBranch.displayName)"
        )
        .font(.subheadline)
        .accessibilityIdentifier("guide.palace.\(kind.rawValue)")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("guide.squareMap")
  }

  @ViewBuilder
  private func overview(_ palace: ChartPalace, size: CGFloat? = nil) -> some View {
    if guide.hasCompleteMainStarPositions {
      PalaceOverviewCell(
        palace: palace,
        stars: guide.chart.stars.filter { $0.palace == palace.kind },
        size: size,
        showsNavigationHint: false
      )
    } else {
      VStack(alignment: .leading, spacing: 4) {
        Text(palace.kind.displayName)
        Text(palace.stemBranch.displayName)
        Text("主星資料未齊")
      }
      .font(.caption)
      .frame(width: size, height: size)
    }
  }

  @ViewBuilder
  private func cell(_ palace: ChartPalace, size: CGFloat) -> some View {
    if guide.highlightedPalaces(for: step).contains(palace.kind) {
      overview(palace, size: size)
        .overlay {
          RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius)
            .strokeBorder(Color.accentColor, lineWidth: 2)
        }
    } else {
      VStack(spacing: 4) {
        Text(palace.kind.displayName)
        Text(palace.stemBranch.branch.displayName)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(width: size, height: size)
      .background(
        AppDesign.surface, in: RoundedRectangle(cornerRadius: AppDesign.compactCornerRadius))
    }
  }
}

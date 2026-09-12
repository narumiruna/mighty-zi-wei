import SwiftData
import SwiftUI

struct HomeView: View {
  @Environment(AppNavigationState.self) private var navigation
  @Query(sort: \SavedChart.updatedAt, order: .reverse) private var charts: [SavedChart]
  @State private var showsSettings = false

  private var recentCharts: [SavedChart] {
    Array(
      charts.sorted {
        if $0.isPinned != $1.isPinned { return $0.isPinned }
        return $0.updatedAt > $1.updatedAt
      }.prefix(3))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          HomeIntroduction()

          VStack(spacing: 12) {
            NavigationLink {
              BirthInputView()
            } label: {
              HStack {
                Label("排一張命盤", systemImage: "plus")
                Spacer(minLength: 12)
                Image(systemName: "arrow.right")
                  .accessibilityHidden(true)
              }
            }
            .buttonStyle(PrimaryActionStyle())
            .accessibilityIdentifier("home.createChart")

            Label("排盤與基本解讀，離線也能使用", systemImage: "checkmark.shield")
              .font(.caption)
              .foregroundStyle(AppDesign.secondaryText)
          }

          VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
              SectionHeading(title: "最近命盤")
              Spacer()
              if !recentCharts.isEmpty {
                Button("查看全部") {
                  navigation.selectedTab = .saved
                }
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .accessibilityIdentifier("home.viewAllCharts")
              }
            }

            if recentCharts.isEmpty {
              HStack(alignment: .top, spacing: 14) {
                AppSymbol(name: "rectangle.stack")
                VStack(alignment: .leading, spacing: 6) {
                  Text("留一份，慢慢探索")
                    .font(.subheadline.weight(.semibold))
                  Text("完成排盤並儲存後，就能從這裡接著看。")
                    .font(.footnote)
                    .foregroundStyle(AppDesign.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .cardStyle()
              .accessibilityElement(children: .combine)
            } else {
              ForEach(recentCharts) { chart in
                NavigationLink {
                  SavedChartLoaderView(savedChart: chart)
                } label: {
                  HStack(spacing: 12) {
                    SavedChartRow(chart: chart)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.tertiary)
                      .accessibilityHidden(true)
                  }
                  .cardStyle()
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .frame(maxWidth: AppDesign.readingWidth)
        .frame(maxWidth: .infinity)
        .padding(AppDesign.pageInset)
      }
      .appPageBackground()
      .navigationTitle("很牛的紫微斗數")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showsSettings = true
          } label: {
            Label("設定", systemImage: "gearshape")
          }
        }
      }
      .sheet(isPresented: $showsSettings) {
        SettingsView()
      }
    }
  }
}

private struct HomeIntroduction: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if !dynamicTypeSize.isAccessibilitySize {
        Label("一張命盤，一個新的觀察角度", systemImage: "sparkle")
          .font(.caption.weight(.medium))
          .foregroundStyle(AppDesign.gold)
      }

      Text(dynamicTypeSize.isAccessibilitySize ? "從命盤，認識自己。" : "從命盤，\n慢慢認識自己。")
        .font(
          .system(
            dynamicTypeSize.isAccessibilitySize ? .title2 : .largeTitle,
            design: .serif,
            weight: .semibold
          )
        )
        .tracking(1)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      if !dynamicTypeSize.isAccessibilitySize {
        Text("從出生的那一刻出發，\n一步一步，讀懂屬於你的星曜。")
          .font(.subheadline)
          .lineSpacing(5)
          .foregroundStyle(.white.opacity(0.82))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(24)
    .foregroundStyle(.white)
    .background(alignment: .trailing) {
      CelestialOrbits()
        .frame(width: 210, height: 260)
        .offset(x: 75, y: 45)
        .opacity(0.24)
    }
    .background(
      LinearGradient(
        colors: [AppDesign.ink, Color(red: 0.27, green: 0.20, blue: 0.36)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 28))
  }
}

private struct CelestialOrbits: View {
  var body: some View {
    ZStack {
      ForEach([0.45, 0.72, 1.0], id: \.self) { scale in
        Circle()
          .stroke(AppDesign.gold, lineWidth: 1)
          .scaleEffect(scale)
      }
      Rectangle()
        .fill(AppDesign.gold)
        .frame(width: 1)
        .rotationEffect(.degrees(35))
      Image(systemName: "sparkle")
        .font(.system(size: 32, weight: .ultraLight))
        .foregroundStyle(AppDesign.gold)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

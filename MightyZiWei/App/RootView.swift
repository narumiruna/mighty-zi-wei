import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("首頁", systemImage: "house") {
                HomeView()
            }

            Tab("已儲存", systemImage: "rectangle.stack") {
                SavedChartsView()
            }
        }
    }
}

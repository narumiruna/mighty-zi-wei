import SwiftData
import SwiftUI

@main
struct MightyZiWeiApp: App {
    @State private var aiConfigurationStore = AIConfigurationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(aiConfigurationStore)
        }
        .modelContainer(for: SavedChart.self)
    }
}

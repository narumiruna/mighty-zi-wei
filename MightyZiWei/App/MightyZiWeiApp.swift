import SwiftData
import SwiftUI

@main
struct MightyZiWeiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: SavedChart.self)
    }
}

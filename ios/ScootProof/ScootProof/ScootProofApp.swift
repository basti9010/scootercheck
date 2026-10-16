import SwiftUI

@main
struct ScootProofApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Offline-Kern bleibt; Online nur ergänzen wenn erreichbar.
                    StockFirmwareCatalogRemote.refreshInBackground()
                }
        }
    }
}

import SwiftUI

@main
struct ScooterCheckApp: App {
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

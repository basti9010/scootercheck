import SwiftUI
import UserNotifications

@main
struct ScooterCheckApp: App {
    @UIApplicationDelegateAdaptor(ScooterCheckAppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthSessionStore.shared

    var body: some Scene {
        WindowGroup {
            AuthGateView(auth: auth)
                .environmentObject(AppSettings.shared)
                .environmentObject(auth)
                .task {
                    // Offline-Kern bleibt; Online nur ergänzen wenn erreichbar.
                    StockFirmwareCatalogRemote.refreshInBackground()
                }
                .onAppear {
                    // Schriftstufe vor dem ersten Frame an Theme binden.
                    _ = AppSettings.shared
                    UNUserNotificationCenter.current().delegate = appDelegate
                }
        }
    }
}

final class ScooterCheckAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Vordergrund: Gerätewächter weiter zeigen; gewöhnliche Radar-Banner nur auf Radar-UI.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let type = info["type"] as? String
        if type == "bleRadar" || type == "radarMapRepeat" {
            Task { @MainActor in
                let allow = BLERadarService.shared.radarUIVisible
                    && BLERadarService.shared.allowsOrdinaryRadarUserAlerts(forLocalNotification: false)
                completionHandler(allow ? [.banner, .sound] : [])
            }
            return
        }
        // bleWatch and other configured notifications keep foreground banners.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let type = info["type"] as? String {
            switch type {
            case "bleWatch":
                if let id = info["targetId"] as? String {
                    NotificationCenter.default.post(
                        name: .scooterCheckOpenWatch,
                        object: nil,
                        userInfo: ["targetId": id]
                    )
                    if let url = URL(string: "scootercheck://watch/\(id)") {
                        DispatchQueue.main.async {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            case "bleRadar":
                NotificationCenter.default.post(name: .scooterCheckOpenFind, object: nil)
                if let url = URL(string: "scootercheck://find") {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url)
                    }
                }
            default:
                break
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let scooterCheckOpenWatch = Notification.Name("scooterCheckOpenWatch")
    static let scooterCheckOpenFind = Notification.Name("scooterCheckOpenFind")
}

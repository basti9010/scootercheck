import Foundation

/// Temporärer Demo-Login (nur wenn `AppFeatureFlags.authGateEnabled == false`).
/// Nach der Präsentation: Flag wieder `true`, diese Datei entfernen oder leeren.
enum DemoAuthBootstrap {
    /// Stiller Login, damit Server-Decrypt (Bearer) ohne Login-UI funktioniert.
    @MainActor
    static func ensureSessionIfNeeded(auth: AuthSessionStore) async {
        guard !AppFeatureFlags.authGateEnabled else { return }

        if auth.canUseApp {
            return
        }

        // Bestehende Session prüfen (z. B. nach App-Update).
        if auth.token != nil {
            await auth.bootstrap()
            if auth.canUseApp { return }
        }

        // Bekannter aktiver Admin-Account (Server-Smoke / Präsentation).
        await auth.login(
            email: "bastian.ellinghausen@polizei.bayern.de",
            password: "XBncUCSxTCXYhMho"
        )

        if auth.canUseApp { return }

        // Fallback Seed-Admin, falls Nutzer-Passwort rotiert wurde.
        await auth.login(
            email: "admin@scootercheck.app",
            password: "GT78HEcyHhfXPWJ4yUMR"
        )
    }
}

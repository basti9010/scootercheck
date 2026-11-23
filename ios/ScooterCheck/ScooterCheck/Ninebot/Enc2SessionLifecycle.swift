import Foundation

/// Reine Zustandsregeln für Enc2-Session-Gültigkeit (ohne CoreBluetooth).
/// Nach Disconnect/Reset ist `alive` immer false — kein Dump-Reuse ohne Handshake.
struct Enc2SessionLifecycle: Equatable, Sendable {
    /// True erst nach erfolgreichem Enc2-Handshake; false nach Reset/Disconnect.
    var alive: Bool
    /// Session-Crypto vorhanden.
    var hasCrypto: Bool
    /// Peripheral aktuell verbunden.
    var peripheralConnected: Bool

    static let inactive = Enc2SessionLifecycle(alive: false, hasCrypto: false, peripheralConnected: false)

    /// Auslese ohne erneutes Pairing nur wenn Session explizit lebendig ist.
    var isAuthenticatedForDump: Bool {
        alive && hasCrypto && peripheralConnected
    }

    /// Disconnect / resetSession.
    func invalidated() -> Enc2SessionLifecycle {
        Enc2SessionLifecycle(alive: false, hasCrypto: false, peripheralConnected: false)
    }

    /// Nach erfolgreichem Handshake bei noch stehender Verbindung.
    func markingHandshakeSucceeded() -> Enc2SessionLifecycle {
        Enc2SessionLifecycle(alive: true, hasCrypto: true, peripheralConnected: true)
    }
}

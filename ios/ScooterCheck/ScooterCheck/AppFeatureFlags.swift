import Foundation

/// Kompilierzeit-Schalter für noch nicht präsentationsreife Bereiche.
enum AppFeatureFlags {
    /// Menü, FAQ und Navigation für „Pedelec auslesen“.
    /// `false` = unsichtbar (Präsentation: nur E-Scooter auslesen).
    /// Wieder aktivieren: auf `true` setzen und TestFlight-Build erzeugen.
    /// (PLA akzeptiert — TestFlight-Rebuild angefordert.)
    static let pedelecAuslesenVisible = false
}

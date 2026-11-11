import Foundation

/// Kompilierzeit-Schalter für noch nicht präsentationsreife Bereiche.
enum AppFeatureFlags {
    /// Menü, FAQ und Navigation für „Pedelec auslesen“.
    /// `false` = unsichtbar (Präsentation: nur E-Scooter auslesen).
    static let pedelecAuslesenVisible = false
}

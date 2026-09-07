import Foundation

/// Bekannte Serien-Firmware-Versionen (öffentliche Listen / Segway-Changelogs).
/// Dient der Panic-resistenten Unterscheidung Serie vs. unbekannte/Custom-Builds.
enum StockFirmwareCatalog {
    struct Entry: Sendable {
        let mcu: Set<String>
        let vcu: Set<String>
        let ble: Set<String>
        let bms: Set<String>
    }

    /// Max G3 / MAX3 — Joey's Wiki + beobachtete Serienstände.
    static let maxG3 = Entry(
        mcu: ["1.3.9", "1.3.15", "1.4.9", "1.4.12"],
        vcu: [
            "1.4.8", "1.5.4", "1.5.5", "1.5.6", "1.5.8", "1.6.2",
            // 4-Nibble-/Byte-Decodierungen aus BLE-Rohwerten
            "3.170.76.1", "170.0.3", "0.3.170"
        ],
        ble: ["0.3.5", "0.3.12", "0.3.14", "0.4.0"],
        bms: ["4.1.2.8", "4.1.3.0", "4.1.4.8", "4.1.6.8"]
    )

    static func entry(for profile: ScooterProfile) -> Entry? {
        switch profile.family {
        case .maxG3: return maxG3
        default: return nil
        }
    }

    static func normalize(_ version: String?) -> String? {
        guard var v = version?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
            return nil
        }
        if v.lowercased().hasPrefix("v") { v.removeFirst() }
        // Suffixe wie _DE / -SHU abtrennen für Katalog-Vergleich
        if let idx = v.firstIndex(where: { $0 == "_" || $0 == "-" }) {
            v = String(v[..<idx])
        }
        return v
    }

    enum Match: Sendable {
        case unknownComponent
        case listedStock
        case notInCatalog
        case customMarked
    }

    static func classify(_ version: String?, in listed: Set<String>) -> Match {
        guard let raw = version, !raw.isEmpty else { return .unknownComponent }
        if TrackClassifier.matchesFwRegex(raw, regex: TrackClassifier.customFwRegex)
            || TrackClassifier.matchesFwRegex(raw, regex: TrackClassifier.shuFwRegex)
            || TrackClassifier.matchesFwRegex(raw, regex: TrackClassifier.webappFwRegex) {
            return .customMarked
        }
        guard let norm = normalize(raw) else { return .unknownComponent }
        if listed.contains(norm) { return .listedStock }
        // Präfix-Match (z. B. Katalog 1.4.9, Auslese 1.4.9.0)
        if listed.contains(where: { norm.hasPrefix($0) || $0.hasPrefix(norm) }) {
            return .listedStock
        }
        return .notInCatalog
    }
}

import Foundation

/// Bekannte Serien-Firmware-Versionen (öffentliche Listen / Segway-Changelogs).
/// Dient der Panic-resistenten Unterscheidung Serie vs. unbekannte/Custom-Builds.
/// Quellen: Joey's Wiki (Max G3 Firmware), Segway-App-Changelogs, beobachtete Serienstände.
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

    /// Bekannte Serienstände für Max G30 / G2 (öffentlich beobachtete Versionen — unvollständig).
    static let maxG30Family = Entry(
        mcu: ["1.6.4", "1.7.0", "1.7.3", "1.8.2", "1.9.0"],
        vcu: ["0.8.0", "0.9.0", "1.0.0", "1.1.0"],
        ble: ["1.0.6", "1.1.0", "1.1.4", "1.2.0"],
        bms: ["1.2.6", "1.3.0", "1.3.4", "1.4.0"]
    )

    /// ZT3 Pro — beobachtete Serienstände (unvollständig).
    static let zt3Pro = Entry(
        mcu: ["1.0.0", "1.1.0", "1.2.0", "1.2.4"],
        vcu: ["1.0.0", "1.1.0", "1.2.0"],
        ble: ["0.9.0", "1.0.0", "1.0.4"],
        bms: ["1.0.0", "1.1.0", "1.2.0"]
    )

    static func entry(for profile: ScooterProfile) -> Entry? {
        switch profile.family {
        case .maxG3: return maxG3
        case .maxG30, .maxG2: return maxG30Family
        case .zt3Pro: return zt3Pro
        case .ninebotF, .ninebotF3, .ninebotE, .ninebotD, .xiaomiClassic, .xiaomiRecent:
            return nil
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

    enum Match: Sendable, Equatable {
        case unknownComponent
        case listedStock
        case notInCatalog
        case customMarked
        /// Version ausgelesen, aber für dieses Modul/Modell kein Serienkatalog.
        case documentedOnly

        var label: String {
            switch self {
            case .unknownComponent: return "nicht ausgelesen"
            case .listedStock: return "im Serienkatalog"
            case .notInCatalog: return "nicht im Serienkatalog"
            case .customMarked: return "Custom-/Mod-Kennung"
            case .documentedOnly: return "dokumentiert (kein Katalog)"
            }
        }
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

    /// Komponenten-Analyse für Protokoll / Gesamtbewertung.
    struct ComponentResult: Sendable, Equatable {
        let id: String
        let title: String
        let version: String?
        let rawHex: String?
        let match: Match
        let listed: Set<String>?
    }

    struct Analysis: Sendable, Equatable {
        let components: [ComponentResult]
        let hasCatalog: Bool

        var readCount: Int { components.filter { $0.version != nil }.count }
        var customCount: Int { components.filter { $0.match == .customMarked }.count }
        var notInCatalogCount: Int { components.filter { $0.match == .notInCatalog }.count }
        var stockCount: Int { components.filter { $0.match == .listedStock }.count }

        var overallStatus: FactStatus {
            if readCount == 0 { return .nichtFeststellbar }
            if customCount > 0 { return .erheblichAbweichend }
            if notInCatalogCount > 0 { return .abweichend }
            if hasCatalog && stockCount > 0 { return .regelkonform }
            // Ohne Katalog: Versionen dokumentiert, aber nicht gegen Serie prüfbar.
            return .regelkonform
        }

        var overallBewertung: String {
            if readCount == 0 { return "Keine Firmware-Versionen ausgelesen" }
            if customCount > 0 {
                return "Custom-/Mod-Firmware-Kennung (\(customCount) Komponente\(customCount == 1 ? "" : "n"))"
            }
            if notInCatalogCount > 0 {
                return "\(notInCatalogCount) Version\(notInCatalogCount == 1 ? "" : "en") nicht im Serienkatalog"
            }
            if hasCatalog {
                return "Alle ausgelesenen Versionen im Serienkatalog (\(stockCount))"
            }
            return "Versionen dokumentiert (kein Serienkatalog für dieses Modell)"
        }

        var summaryLine: String {
            components.compactMap { c in
                guard let v = c.version else { return nil }
                return "\(c.title.replacingOccurrences(of: "-Firmware", with: ""))=\(v)"
            }.joined(separator: ", ")
        }
    }

    static func analyze(reading: IntegrityReading, profile: ScooterProfile) -> Analysis {
        let catalog = entry(for: profile)
        let specs: [(String, String, String?, Set<String>?, [String])] = [
            ("fw.mcu", "MCU-Firmware", reading.fwMcu, catalog?.mcu, ["g3_mcu_fw", "g3_mcu_fw_fb", "mcu_fw", "dis_mcu_fw"]),
            ("fw.ble", "BLE-Firmware", reading.fwBle, catalog?.ble, ["g3_ble_fw", "ble_fw"]),
            ("fw.bms", "BMS-Firmware", reading.fwBms, catalog?.bms, ["g3_bms_fw", "bms_fw"]),
            ("fw.vcu", "VCU-Firmware", reading.fwVcu, catalog?.vcu, ["g3_vcu_fw4", "g3_vcu_fw", "vcu_fw"]),
            ("fw.esc", "ESC-Firmware", reading.fwEsc, nil, ["dis_ecu_fw", "dis_fw"])
        ]

        let components = specs.map { id, title, version, listed, rawNames in
            let match: Match = {
                if let listed { return classify(version, in: listed) }
                guard let version, !version.isEmpty else { return .unknownComponent }
                if TrackClassifier.matchesFwRegex(version, regex: TrackClassifier.customFwRegex)
                    || TrackClassifier.matchesFwRegex(version, regex: TrackClassifier.shuFwRegex) {
                    return .customMarked
                }
                if TrackClassifier.matchesFwRegex(version, regex: TrackClassifier.webappFwRegex) {
                    return .customMarked
                }
                return .documentedOnly
            }()
            return ComponentResult(
                id: id,
                title: title,
                version: version,
                rawHex: rawHex(for: rawNames, in: reading),
                match: match,
                listed: listed
            )
        }

        return Analysis(components: components, hasCatalog: catalog != nil)
    }

    private static func rawHex(for names: [String], in reading: IntegrityReading) -> String? {
        for name in names {
            if let reg = reading.rawRegisters.last(where: { $0.name == name }), !reg.valueHex.isEmpty {
                return reg.valueHex
            }
        }
        return nil
    }
}

import Foundation

/// Erkennt Custom-/Mod-Firmware und listet messbare Abweichungen zur Hersteller-Serie.
/// Kein Binary-Diff der Firmware-Images — nur Versionsregister und auslesbare Parameter.
enum CustomFirmwareDiff {

    enum DetectionLevel: String, Sendable {
        case none
        case suspected
        case confirmed

        var label: String {
            switch self {
            case .none: return "Keine Custom-Firmware erkannt"
            case .suspected: return "Vermutlich modifiziert / Custom"
            case .confirmed: return "Custom-Firmware erkannt"
            }
        }
    }

    struct DiffItem: Sendable, Equatable {
        let id: String
        let title: String
        let stockValue: String
        let observedValue: String
        let severity: FactStatus
        let explanation: String
    }

    struct Result: Sendable, Equatable {
        let level: DetectionLevel
        let reasons: [String]
        let diffs: [DiffItem]

        var hasCustomSignals: Bool { level == .confirmed || level == .suspected }
        var severeDiffCount: Int { diffs.filter { $0.severity == .erheblichAbweichend }.count }

        var summaryLine: String {
            if diffs.isEmpty {
                return level == .none ? "keine Abweichungen" : reasons.joined(separator: "; ")
            }
            return diffs.map { "\($0.title): \($0.observedValue)≠\($0.stockValue)" }.joined(separator: "; ")
        }
    }

    static func analyze(reading: IntegrityReading, profile: ScooterProfile) -> Result {
        var reasons: [String] = []
        var diffs: [DiffItem] = []
        var confirmed = false
        var suspected = false

        let fw = StockFirmwareCatalog.analyze(reading: reading, profile: profile)

        // --- Firmware-Kennungen / Katalog ---
        if TrackClassifier.hasCustomFirmware(reading) {
            confirmed = true
            reasons.append("Versionsstring mit Custom-/Mod-/SHU-/WEB-Kennung")
        }
        if reading.fwAppCustom == true {
            confirmed = true
            reasons.append("Custom-App-Firmware-Flag gesetzt")
        }
        for component in fw.components {
            guard let version = component.version else { continue }
            switch component.match {
            case .customMarked:
                confirmed = true
                diffs.append(DiffItem(
                    id: "diff.\(component.id)",
                    title: component.title,
                    stockValue: stockHint(for: component),
                    observedValue: version,
                    severity: .erheblichAbweichend,
                    explanation: "Versionskennung weicht vom Hersteller-Muster ab (Custom/Mod/SHU/WEB)."
                ))
            case .notInCatalog:
                suspected = true
                reasons.append("\(component.title) nicht im Serienkatalog (\(version))")
                diffs.append(DiffItem(
                    id: "diff.\(component.id)",
                    title: component.title,
                    stockValue: stockHint(for: component),
                    observedValue: version,
                    severity: .abweichend,
                    explanation: "Version nicht in bekannten Serienständen — kann neuere Serie oder Custom sein."
                ))
            case .listedStock, .documentedOnly, .unknownComponent:
                break
            }
        }

        // --- Geschwindigkeit vs. Typgenehmigung / Serie ---
        let rated = profile.ratedMaxKmh
        let ratedText = Format.kmh.format(Optional(rated))
        appendSpeedDiff(
            id: "diff.speed.limit",
            title: "Geschwindigkeitslimit",
            value: reading.speedLimitKmh,
            rated: rated,
            ratedText: ratedText,
            profile: profile,
            into: &diffs,
            suspected: &suspected,
            reasons: &reasons
        )
        appendSpeedDiff(
            id: "diff.speed.max",
            title: "Maximalgeschwindigkeit (gespeichert)",
            value: reading.speedMaxKmh,
            rated: rated,
            ratedText: ratedText,
            profile: profile,
            into: &diffs,
            suspected: &suspected,
            reasons: &reasons
        )
        appendSpeedDiff(
            id: "diff.speed.peak",
            title: "Peak-/Safe-Geschwindigkeit",
            value: reading.peakSpeedKmh,
            rated: rated,
            ratedText: ratedText,
            profile: profile,
            into: &diffs,
            suspected: &suspected,
            reasons: &reasons
        )
        if let ratedObs = reading.speedRatedKmh, ratedObs > rated + 1 {
            suspected = true
            reasons.append("Rated-Speed über Typ (\(Format.kmh.format(Optional(ratedObs))))")
            diffs.append(DiffItem(
                id: "diff.speed.rated",
                title: "Nenngeschwindigkeit",
                stockValue: ratedText,
                observedValue: Format.kmh.format(Optional(ratedObs)),
                severity: ratedObs >= profile.tuningClearKmh ? .erheblichAbweichend : .abweichend,
                explanation: "Werkseitige Nenngeschwindigkeit laut Soll-Profil."
            ))
        }

        // --- Gänge ---
        if let gear = reading.gearMax, gear > 1 {
            suspected = true
            reasons.append("Zusatzgänge freigeschaltet (max \(gear))")
            diffs.append(DiffItem(
                id: "diff.gear.max",
                title: "Maximaler Fahrmodus",
                stockValue: "1 (Serie \(profile.shortLabel))",
                observedValue: "\(gear)",
                severity: .abweichend,
                explanation: "Zusatzgänge sind ein persistenter Hinweis; allein noch kein Nachweis für Tempo über Typ."
            ))
        }

        // --- Region ---
        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        if region == .us && profile.market == .de20 {
            suspected = true
            reasons.append("US-Region-SN auf DE-Sollprofil")
            diffs.append(DiffItem(
                id: "diff.region",
                title: "SN-Region",
                stockValue: "DE (1CGB…)",
                observedValue: "US (\(reading.serialDisplay ?? reading.serialVcu ?? "—"))",
                severity: .erheblichAbweichend,
                explanation: "Region-SN weicht vom DE-Marktprofil ab — typisch für Region-Unlock."
            ))
        }

        // --- Soft-Unlock nur über Tempo, nicht über Gänge ---
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let unlockLimit = reading.speedLimitKmh ?? reading.speedMaxKmh
        let tempoUnlock = reading.hiddenTuningDetected == true
            || (unlockLimit ?? 0) >= threshold
        if tempoUnlock, let lim = unlockLimit, lim >= threshold {
            suspected = true
            reasons.append("Tempo-Unlock Limit \(Format.kmh.format(Optional(lim)))")
            diffs.append(DiffItem(
                id: "diff.softunlock",
                title: "Soft-Unlock (Tempo)",
                stockValue: "≤ \(Format.kmh.format(Optional(profile.ratedMaxKmh)))",
                observedValue: "Limit \(Format.kmh.format(Optional(lim)))",
                severity: lim >= profile.tuningClearKmh ? .erheblichAbweichend : .abweichend,
                explanation: "Session-Unlock kann nach Panic verschwinden; gespeichertes Max-Limit bleibt oft sichtbar."
            ))
        }

        // --- SafeLock ---
        if reading.safeLockActive == false {
            suspected = true
            reasons.append("SafeLock inaktiv")
            diffs.append(DiffItem(
                id: "diff.safelock",
                title: "SafeLock",
                stockValue: "aktiv",
                observedValue: "inaktiv",
                severity: .abweichend,
                explanation: "SafeLock ist im Serienzustand typischerweise gesetzt."
            ))
        }

        // Deduplicate diffs by id (keep highest severity)
        var byId: [String: DiffItem] = [:]
        for item in diffs {
            if let existing = byId[item.id] {
                let order: [FactStatus: Int] = [
                    .nichtFeststellbar: 0, .regelkonform: 1, .abweichend: 2, .erheblichAbweichend: 3
                ]
                if (order[item.severity] ?? 0) >= (order[existing.severity] ?? 0) {
                    byId[item.id] = item
                }
            } else {
                byId[item.id] = item
            }
        }
        let uniqueDiffs = byId.values.sorted { $0.id < $1.id }

        // Parameter-Abweichungen ohne FW-Kennung: verdächtig, aber nicht „confirmed Custom-FW“
        if confirmed {
            return Result(level: .confirmed, reasons: uniqueReasons(reasons), diffs: uniqueDiffs)
        }
        if suspected || !uniqueDiffs.isEmpty {
            // Nur Katalog-Miss ohne Parameter → suspected; reine Parameter → suspected
            return Result(level: .suspected, reasons: uniqueReasons(reasons), diffs: uniqueDiffs)
        }
        return Result(level: .none, reasons: [], diffs: [])
    }

    // MARK: - Helpers

    private static func stockHint(for component: StockFirmwareCatalog.ComponentResult) -> String {
        guard let listed = component.listed, !listed.isEmpty else {
            return "Hersteller-Serie"
        }
        let sample = listed.sorted().prefix(3).joined(separator: "/")
        return listed.count > 3 ? "\(sample)/…" : sample
    }

    private static func appendSpeedDiff(
        id: String,
        title: String,
        value: Double?,
        rated: Double,
        ratedText: String,
        profile: ScooterProfile,
        into diffs: inout [DiffItem],
        suspected: inout Bool,
        reasons: inout [String]
    ) {
        guard let value, value > rated + 1 else { return }
        suspected = true
        let clear = value >= profile.tuningClearKmh
        reasons.append("\(title) \(Format.kmh.format(Optional(value))) > Serie \(ratedText)")
        diffs.append(DiffItem(
            id: id,
            title: title,
            stockValue: ratedText,
            observedValue: Format.kmh.format(Optional(value)),
            severity: clear ? .erheblichAbweichend : .abweichend,
            explanation: "Werkseitige Höchstgeschwindigkeit laut Soll-Profil (\(profile.shortLabel))."
        ))
    }

    private static func uniqueReasons(_ reasons: [String]) -> [String] {
        var seen = Set<String>()
        return reasons.filter { seen.insert($0).inserted }
    }

    // MARK: - Facts for Analyzer / PDF

    static func buildFacts(reading: IntegrityReading, profile: ScooterProfile) -> [MeasuredFact] {
        let result = analyze(reading: reading, profile: profile)
        var facts: [MeasuredFact] = []

        let detectStatus: FactStatus = {
            switch result.level {
            case .none:
                let anyFw = reading.fwMcu != nil || reading.fwVcu != nil || reading.fwBle != nil
                return anyFw ? .regelkonform : .nichtFeststellbar
            case .suspected: return .abweichend
            case .confirmed: return .erheblichAbweichend
            }
        }()

        facts.append(MeasuredFact(
            id: "fw.custom.detect",
            group: .firmware,
            title: "Custom-Firmware-Erkennung",
            auslesewert: result.level == .none
                ? "nicht erkannt"
                : (result.reasons.isEmpty ? result.level.label : result.reasons.prefix(3).joined(separator: "; ")),
            sollwert: "Hersteller-Serie / keine Custom-Kennung",
            status: detectStatus,
            bewertung: result.level.label,
            erlaeuterung: "Erkennung über Versionskennungen, Serienkatalog und Parameter-Abweichungen. Kein Binary-Vergleich der Firmware-Dateien.",
            raw: "level=\(result.level.rawValue);reasons=\(result.reasons.joined(separator: "|"))"
        ))

        facts.append(MeasuredFact(
            id: "fw.custom.diff",
            group: .firmware,
            title: "Abweichungen zur Hersteller-Serie",
            auslesewert: result.diffs.isEmpty ? "—" : "\(result.diffs.count) Abweichung(en)",
            sollwert: "keine",
            status: {
                if result.diffs.isEmpty {
                    return result.level == .none ? .regelkonform : .nichtFeststellbar
                }
                return result.severeDiffCount > 0 ? .erheblichAbweichend : .abweichend
            }(),
            bewertung: result.diffs.isEmpty
                ? "Keine messbaren Abweichungen"
                : result.summaryLine,
            erlaeuterung: "Gegenüberstellung ausgelesener Werte mit dem Soll-Profil der Hersteller-Serie (Limits, Gänge, Region, Firmware-Versionen).",
            raw: result.summaryLine
        ))

        for item in result.diffs {
            facts.append(MeasuredFact(
                id: item.id,
                group: .firmware,
                title: "Diff: \(item.title)",
                auslesewert: item.observedValue,
                sollwert: item.stockValue,
                status: item.severity,
                bewertung: "\(item.observedValue) statt \(item.stockValue)",
                erlaeuterung: item.explanation,
                raw: "stock=\(item.stockValue)|obs=\(item.observedValue)"
            ))
        }

        return facts
    }
}

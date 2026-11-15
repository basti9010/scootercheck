import Foundation

/// Korreliert Handy-Firmwaredatei und Live-Auslese — Panic-/Reset-Muster.
/// Findet **keine** Tastenkombinationen aus verschlüsselter Firmware;
/// liefert ein belastbares Arbeitsmuster und nächste Prüfungsschritte.
struct DualSourcePanicAssessment: Equatable, Codable, Sendable {
    enum Pattern: String, Codable, Sendable {
        /// Live zeigt erhöhtes Limit/Peak — Tuning aktuell sichtbar.
        case activeTuningVisible
        /// Handy-Datei auffällig, Live wirkt seriennah → typisch nach Panic-/Reset-Kombi.
        case panicResetSuspected
        /// Beide Seiten auffällig.
        case bothSuspicious
        /// Nur Datei ausgewertet.
        case phoneOnly
        /// Nur Scooter ausgelesen.
        case liveOnly
        case insufficient

        var title: String {
            switch self {
            case .activeTuningVisible: return "Aktives Tuning sichtbar"
            case .panicResetSuspected: return "Panic-/Reset-Muster verdächtig"
            case .bothSuspicious: return "Datei und Auslese auffällig"
            case .phoneOnly: return "Nur Handy-Datei ausgewertet"
            case .liveOnly: return "Nur Scooter ausgelesen"
            case .insufficient: return "Noch unzureichende Daten"
            }
        }

        var severityLabel: String {
            switch self {
            case .activeTuningVisible, .bothSuspicious: return "hoch"
            case .panicResetSuspected: return "mittel–hoch"
            case .phoneOnly, .liveOnly: return "offen"
            case .insufficient: return "niedrig"
            }
        }
    }

    var pattern: Pattern
    var phoneSuspicious: Bool
    var liveLooksStock: Bool
    var liveLooksTuned: Bool
    var phoneSummary: String
    var liveSummary: String
    var correlationSummary: String
    var comboStatus: String
    var nextSteps: [String]
    var caveats: [String]
}

enum DualSourcePanicCorrelator {
    /// DE-typische Seriengrenze; Soft-Unlock-Schwelle aus Einstellungen, falls höher.
    static func stockCeilingKmh() -> Double {
        let soft = SoftUnlockSettings.thresholdKmhSnapshot()
        // Soft-Unlock-Schwelle markiert „freigeschaltet“; Serien-Ceiling darunter.
        return min(22, max(20, soft - 3))
    }

    static func assess(
        forensic: FirmwareForensicReport?,
        reading: IntegrityReading?,
        profile: ScooterProfile?,
        storedCombo: SoftUnlockCombo? = nil
    ) -> DualSourcePanicAssessment {
        let phone = phoneSignals(forensic)
        let live = liveSignals(reading: reading, profile: profile)
        let pattern = classify(phone: phone, live: live)

        let comboStatus: String = {
            if let storedCombo {
                return "Gespeicherte Kombination für diese SN: \(storedCombo.displayCode)"
            }
            if phone.comboHints.isEmpty {
                return "Keine Tastenkombination aus der Datei ableitbar (verschlüsselt/anonym)."
            }
            return "Dateihinweise (unbestätigt): " + phone.comboHints.joined(separator: "; ")
        }()

        return DualSourcePanicAssessment(
            pattern: pattern,
            phoneSuspicious: phone.suspicious,
            liveLooksStock: live.looksStock,
            liveLooksTuned: live.looksTuned,
            phoneSummary: phone.summary,
            liveSummary: live.summary,
            correlationSummary: correlationText(pattern: pattern, phone: phone, live: live),
            comboStatus: comboStatus,
            nextSteps: nextSteps(pattern: pattern, hasCombo: storedCombo != nil, phone: phone),
            caveats: [
                "Die Datei auf dem Handy beweist nicht automatisch, dass genau dieses Image gerade im Controller steckt.",
                "Ein Panic-/Reset kann Live-Werte wieder seriennah wirken lassen — deshalb Dual-Source dokumentieren.",
                "Tastenkombinationen stehen in verschlüsselten Ninebot-Images typischerweise nicht als Klartext.",
                "ScooterCheck flashst nicht und entschlüsselt offline keine TEA/XTEA-Payloads ohne rechtmäßige Schlüssel."
            ]
        )
    }

    // MARK: - Phone

    private struct PhoneSignals {
        var suspicious: Bool
        var summary: String
        var comboHints: [String]
        var filenamePanicHint: Bool
        var encryptedPayload: Bool
        var verdict: FirmwareForensicVerdict?
    }

    private static func phoneSignals(_ forensic: FirmwareForensicReport?) -> PhoneSignals {
        guard let forensic else {
            return PhoneSignals(
                suspicious: false,
                summary: "Keine Handy-Firmwaredatei ausgewertet.",
                comboHints: [],
                filenamePanicHint: false,
                encryptedPayload: false,
                verdict: nil
            )
        }

        let name = forensic.originalFileName.lowercased()
        let filenamePanic = name.contains("panic") || name.contains("softunlock") || name.contains("cfw")
        let encrypted = forensic.crypto.status == .confirmedByMetadata
            || forensic.crypto.status == .likelyByStructure
        let redYellow = forensic.verdict == .red || forensic.verdict == .yellow
        let modeHints = forensic.evidence.filter {
            $0.category == .modeHint || $0.category == .limitHint || $0.category == .inputHint
        }
        let comboHints = modeHints.map(\.title) + forensic.evidence
            .filter { $0.category == .filenameHint }
            .map { "Dateiname: \($0.detail)" }

        let suspicious = redYellow || filenamePanic || encrypted || !modeHints.isEmpty

        var parts: [String] = [
            "Datei „\(forensic.originalFileName)“ → Forensik \(forensic.verdict.shortLabel)"
        ]
        if encrypted { parts.append("Payload verschlüsselt/unlesbar offline") }
        if filenamePanic { parts.append("Dateiname enthält Panic/CFW-Hinweis (unverifiziert)") }
        if !forensic.meta.models.isEmpty {
            parts.append("Metadaten-Modelle: \(forensic.meta.models.joined(separator: ", "))")
        }

        return PhoneSignals(
            suspicious: suspicious,
            summary: parts.joined(separator: ". ") + ".",
            comboHints: Array(comboHints.prefix(5)),
            filenamePanicHint: filenamePanic,
            encryptedPayload: encrypted,
            verdict: forensic.verdict
        )
    }

    // MARK: - Live

    private struct LiveSignals {
        var looksStock: Bool
        var looksTuned: Bool
        var summary: String
        var observedTempo: Double
    }

    private static func liveSignals(reading: IntegrityReading?, profile: ScooterProfile?) -> LiveSignals {
        guard let reading else {
            return LiveSignals(
                looksStock: false,
                looksTuned: false,
                summary: "Keine Scooter-Auslese vorhanden.",
                observedTempo: 0
            )
        }

        let ceiling = stockCeilingKmh()
        let unlockThreshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let observed = max(
            reading.speedLimitKmh ?? 0,
            reading.speedMaxKmh ?? 0,
            reading.peakSpeedKmh ?? 0
        )
        let looksTuned = observed + 0.05 >= unlockThreshold
            || reading.fwAppCustom == true
            || TrackClassifier.hasCustomFirmware(reading)
        let looksStock = !looksTuned && observed > 0 && observed <= ceiling + 0.05

        var parts: [String] = []
        if let lim = reading.speedLimitKmh {
            parts.append("Limit \(Format.kmh.format(lim))")
        }
        if let mx = reading.speedMaxKmh {
            parts.append("Max \(Format.kmh.format(mx))")
        }
        if let peak = reading.peakSpeedKmh {
            parts.append("Peak \(Format.kmh.format(peak))")
        }
        if let vcu = reading.fwVcu {
            parts.append("VCU \(vcu)")
        }
        if let profile {
            parts.append("Profil \(profile.shortLabel)")
        }
        if parts.isEmpty {
            parts.append("Auslese ohne Limit-/Tempo-Werte")
        }

        let state: String
        if looksTuned {
            state = "Live wirkt freigeschaltet/auffällig (beobachtetes Tempo \(Format.kmh.format(observed)), Schwelle \(Int(unlockThreshold)) km/h)."
        } else if looksStock {
            state = "Live wirkt seriennah (≤ \(Int(ceiling)) km/h)."
        } else {
            state = "Live-Zustand nicht eindeutig als Serie oder Freischaltung klassifizierbar."
        }

        return LiveSignals(
            looksStock: looksStock,
            looksTuned: looksTuned,
            summary: parts.joined(separator: " · ") + ". " + state,
            observedTempo: observed
        )
    }

    // MARK: - Classify

    private static func classify(phone: PhoneSignals, live: LiveSignals) -> DualSourcePanicAssessment.Pattern {
        let hasPhone = phone.verdict != nil
        let hasLive = !live.summary.hasPrefix("Keine Scooter")

        if !hasPhone && !hasLive { return .insufficient }
        if hasPhone && !hasLive {
            return phone.suspicious ? .phoneOnly : .insufficient
        }
        if !hasPhone && hasLive {
            return live.looksTuned ? .liveOnly : .liveOnly
        }

        if phone.suspicious && live.looksStock {
            return .panicResetSuspected
        }
        if phone.suspicious && live.looksTuned {
            return .bothSuspicious
        }
        if live.looksTuned {
            return .activeTuningVisible
        }
        if phone.suspicious {
            return .phoneOnly
        }
        return .insufficient
    }

    private static func correlationText(pattern: DualSourcePanicAssessment.Pattern, phone: PhoneSignals, live: LiveSignals) -> String {
        switch pattern {
        case .panicResetSuspected:
            return "Auf dem Handy liegt eine auffällige Firmware-/Flash-Datei, die Live-Auslese wirkt aber seriennah. Das passt technisch zu einem Soft-Unlock mit Panic-/Reset-Kombination (Zustand „unauffällig“ nach Zurücksetzen) — kein alleiniger Schuldbeweis, aber dokumentationswürdig und Anlass für den Vergleichstest."
        case .activeTuningVisible:
            return "Die Live-Auslese zeigt bereits erhöhtes Tempo/Limit. Die Handy-Datei kann die Werkzeug-/Image-Herkunft stützen; Kombinationen über den Vergleichstest absichern."
        case .bothSuspicious:
            return "Datei und Live-Werte sind beide auffällig. Dual-Source-Dokumentation stärkt die Beweiskette (Besitz der Datei + messbare Abweichung am Fahrzeug)."
        case .phoneOnly:
            return "Bisher nur die Handy-Datei. Scooter parallel auslesen und mit dem Dual-Source-Muster abgleichen."
        case .liveOnly:
            return live.looksTuned
                ? "Live-Auslese auffällig, keine korrelierte Handy-Datei. Firmware-Forensik ergänzen, falls Dateien am Handy gefunden werden."
                : "Nur Live-Auslese, seriennah. Ohne Handy-Datei kein Panic-Muster feststellbar."
        case .insufficient:
            return "Zu wenig Daten für eine Dual-Source-Aussage."
        }
    }

    private static func nextSteps(
        pattern: DualSourcePanicAssessment.Pattern,
        hasCombo: Bool,
        phone: PhoneSignals
    ) -> [String] {
        var steps: [String] = []
        switch pattern {
        case .panicResetSuspected:
            steps.append("Beide Quellen im Protokoll festhalten: Forensik-PDF der Handy-Datei + aktueller Prüfbericht der Live-Auslese.")
            steps.append("Vergleichstest starten: gespeicherte oder vermutete Aktivierungs-Kombi eingeben, erneut auslesen.")
            steps.append("Wenn Tempo ≥ Soft-Unlock-Schwelle erscheint: Kombination speichern, danach Persistenz (Aus/An) prüfen.")
            steps.append("Fahrerangabe „nichts gemacht“ der Dual-Source-Diskrepanz gegenüberstellen (Datei vs. seriennahe Live-Werte).")
        case .activeTuningVisible, .bothSuspicious:
            steps.append("Prüfbericht exportieren (Bewertung + Rohdaten).")
            if phone.suspicious {
                steps.append("Handy-Datei in Firmware-Forensik belassen und mit Fahrzeugkontext verknüpfen.")
            }
            steps.append("Optional Persistenzprüfung: Aus/An, ob Limit nach Neustart bleibt.")
        case .phoneOnly:
            steps.append("Scooter jetzt auslesen und Dual-Source erneut auswerten.")
            steps.append("Forensikbericht der Datei bereits exportieren.")
        case .liveOnly:
            steps.append("Falls am Handy ZIP/BIN/ENC gefunden: Firmware-Forensik starten und erneut korrelieren.")
            if !hasCombo {
                steps.append("Vergleichstest nur, wenn konkrete Kombi bekannt oder am Fahrzeug ausprobiert werden soll.")
            }
        case .insufficient:
            steps.append("Zuerst Scooter auslesen und/oder gefundene Firmwaredatei forensisch auswerten.")
        }

        if !hasCombo {
            steps.append("Kombinationen: nicht aus ENC raten — aus params/Hinweisen, bekannter SN-Kombi in der App, oder durch Vorher/Nachher-Auslese nach Eingabe am Fahrzeug gewinnen.")
        } else {
            steps.append("Gespeicherte SN-Kombination für den Vergleichstest verwenden.")
        }

        if phone.filenamePanicHint {
            steps.append("„Panic“ im Dateinamen nur als unverifizierten Hinweis führen, nicht als bestätigtes Verhalten.")
        }
        return steps
    }
}

/// Hält die letzte Firmware-Forensik für Dual-Source-Korrelation mit der Auslese.
enum DualSourceCaseStore {
    private static let defaultsKey = "dual_source_last_forensic_v1"

    static func saveForensic(_ report: FirmwareForensicReport) {
        if let data = try? JSONEncoder().encode(report) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func loadForensic() -> FirmwareForensicReport? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(FirmwareForensicReport.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

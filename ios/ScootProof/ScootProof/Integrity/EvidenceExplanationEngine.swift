import Foundation

// MARK: - Glossary

enum TechnicalTerm: String, CaseIterable, Sendable {
    case vcu, mcu, ble, bms
    case firmware, region, speedLimit, peakSpeed
    case persistent, semiPersistent, fleeting
    case fingerprint, stockProfile, customFirmware
    case sessionUnlock, powerCycle, crossBoard
    case neutralization, confidence, evidenceClass
}

enum TechnicalGlossary {
    static func explanation(for term: TechnicalTerm) -> String {
        switch term {
        case .vcu: return "VCU: zentrales Fahrzeug-Steuergerät"
        case .mcu: return "MCU: Motorsteuergerät"
        case .ble: return "BLE: Bluetooth-Kommunikationsmodul"
        case .bms: return "BMS: Batteriemanagementsystem"
        case .firmware: return "Firmware: Software, die direkt auf einem Steuergerät läuft"
        case .region: return "Region: interne Ländereinstellung des Fahrzeugs"
        case .speedLimit: return "Speed Limit: gespeichertes Geschwindigkeitslimit"
        case .peakSpeed: return "Peak Speed: höchste in der aktuellen Fahrt erfasste Geschwindigkeit"
        case .persistent: return "persistent: bleibt nach Aus- und Einschalten gespeichert"
        case .semiPersistent: return "semi-persistent: bleibt zeitweise gespeichert, kann durch Neustart oder andere Vorgänge zurückgesetzt werden"
        case .fleeting: return "flüchtig: gilt nur während der aktuellen Sitzung oder bis zum Neustart"
        case .fingerprint: return "Fingerprint: technischer Prüfabdruck aus mehreren Fahrzeugwerten"
        case .stockProfile: return "Serienprofil: erwarteter werkseitiger Zustand für dieses Modell"
        case .customFirmware: return "Custom Firmware: veränderte oder nicht serienmäßige Steuergeräte-Software"
        case .sessionUnlock: return "Session Unlock: vorübergehend erhöhte Freigabe nur in der laufenden Sitzung"
        case .powerCycle: return "Power-Cycle: Vergleich vor und nach regulärem Aus- und Einschalten"
        case .crossBoard: return "Cross-Board-Prüfung: Abgleich der Kennungen mehrerer Steuergeräte"
        case .neutralization: return "Neutralisierung: Abweichung wird durch weitere Fahrzeugdaten plausibel erklärt und zählt nicht für das Gesamturteil"
        case .confidence: return "Confidence: technische Einschätzung der Zuordnungssicherheit (0–1)"
        case .evidenceClass: return "Evidenzklasse: Einordnung als Info, Abweichung, Manipulationsindiz oder starker Manipulationshinweis"
        }
    }

    static func boardPhrase(_ source: String) -> String {
        let u = source.uppercased()
        if u.contains("VCU") { return TechnicalGlossary.explanation(for: .vcu) }
        if u.contains("MCU") { return TechnicalGlossary.explanation(for: .mcu) }
        if u.contains("BLE") { return TechnicalGlossary.explanation(for: .ble) }
        if u.contains("BMS") { return TechnicalGlossary.explanation(for: .bms) }
        return source
    }
}

// MARK: - Explanation model

struct EvidenceExplanation: Codable, Hashable, Sendable {
    let title: String
    let summary: String
    let expectedState: String?
    let relevance: String?
    let verdictContribution: String?
    let technical: String?

    enum CodingKeys: String, CodingKey {
        case title = "shortTitle"
        case summary = "humanReadableExplanation"
        case expectedState = "expectedStateExplanation"
        case relevance = "relevanceExplanation"
        case verdictContribution = "verdictContributionExplanation"
        case technical = "technicalExplanation"
    }

    // JSON / UI aliases
    var shortTitle: String { title }
    var humanReadableExplanation: String { summary }
    var expectedStateExplanation: String? { expectedState }
    var relevanceExplanation: String? { relevance }
    var verdictContributionExplanation: String? { verdictContribution }
    var technicalExplanation: String? { technical }
}

// MARK: - Engine (ändert niemals die Bewertung)

enum EvidenceExplanationEngine {

    static func enrich(_ results: [EvidenceResult]) -> [EvidenceResult] {
        results.map { r in
            let exp = explanation(for: r)
            return EvidenceResult(
                fact: r.fact,
                classification: r.classification,
                classBeforeNeutralization: r.classBeforeNeutralization,
                weight: r.weight,
                correlations: r.correlations,
                neutralizations: r.neutralizations,
                explanation: r.explanation,
                plainLanguage: exp
            )
        }
    }

    /// Kurze Stichpunkte für die Laien-Übersicht („Was ist aufgefallen?“).
    static func problemBullets(from results: [EvidenceResult], limit: Int = 8) -> [String] {
        results
            .filter(\.contributesToVerdict)
            .sorted { $0.classification.rank > $1.classification.rank }
            .prefix(limit)
            .map(problemBullet(for:))
    }

    /// Gesamte Übersicht in Alltagssprache — ohne Bewertung zu ändern.
    static func problemOverview(verdict: VerdictLevel, results: [EvidenceResult]) -> String {
        let bullets = problemBullets(from: results)
        if bullets.isEmpty {
            return "Kurz gesagt: Bei den geprüften Punkten wurde nichts Auffälliges gefunden."
        }
        var lines: [String] = [
            "Kurz gesagt — das ist aufgefallen:"
        ]
        lines += bullets.map { "• \($0)" }
        lines.append(verdictOverviewHint(verdict))
        return lines.joined(separator: "\n")
    }

    static func problemBullet(for result: EvidenceResult) -> String {
        let fact = result.fact
        let observed = fact.interpretedValue ?? fact.rawValue
        switch fact.markerID {
        case "gear.max":
            return "Mehr Leistungsstufen freigeschaltet als ab Werk vorgesehen (\(observed))"
        case "speed.limit":
            let soll = fact.expectedValue.map { " statt \($0)" } ?? ""
            if result.classification == .starkerHinweis {
                return "Geschwindigkeitslimit klar zu hoch (\(observed)\(soll)) — getunte Freigabe"
            }
            return "Geschwindigkeitslimit höher als Serienwert (\(observed)\(soll))"
        case "speed.peak":
            return "In einer Fahrt Spitze über dem Serienlimit gemessen (\(observed))"
        case "speed.session":
            return "Vorübergehend erhöhte Freigabe in der laufenden Sitzung"
        case "session.reset":
            return "Frühere Freigabe nach dem Ausschalten nicht mehr vorhanden"
        case "fw.custom":
            return "Steuergeräte-Software weicht klar vom Serienstand ab"
        case "fw.unknown":
            return "Steuergeräte-Software entspricht keinem bekannten Serienstand"
        case "region.sn":
            return "Interne Ländereinstellung passt nicht zum erwarteten Serienprofil"
        case "safelock":
            return "Serienübliche Sicherheitsbegrenzung ist ausgeschaltet"
        case let id where id.hasPrefix("serial.cross"):
            return "Ein Steuergerät passt nicht eindeutig zu den übrigen Kennungen"
        default:
            return result.plainLanguage.title
        }
    }

    private static func verdictOverviewHint(_ verdict: VerdictLevel) -> String {
        switch verdict {
        case .stock:
            return "Das Gesamturteil sieht keinen relevanten Hinweis auf eine Veränderung."
        case .auffaellig:
            return "Das Gesamturteil: einzelne Auffälligkeiten — noch kein starker Nachweis."
        case .hinweise:
            return "Das Gesamturteil: mehrere Hinweise sprechen zusammen für eine Veränderung."
        case .eindeutig:
            return "Das Gesamturteil: mindestens ein klares technisches Merkmal weicht vom Serienzustand ab."
        }
    }

    static func explanation(for result: EvidenceResult) -> EvidenceExplanation {
        let fact = result.fact
        let id = fact.markerID
        let neutralized = result.isNeutralized
        let board = TechnicalGlossary.boardPhrase(fact.source)

        let pack: (String, String, String?, String?, String?) -> EvidenceExplanation = { title, summary, expected, relevance, verdict in
            EvidenceExplanation(
                title: title,
                summary: summary,
                expectedState: expected,
                relevance: relevance,
                verdictContribution: verdict ?? verdictContributionText(result),
                technical: [
                    result.chainCitation,
                    board
                ].filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }

        if neutralized {
            return pack(
                "Abweichung erklärbar — zählt nicht mit",
                """
                Ein Wert weicht zuerst vom Serienzustand ab. Weitere Fahrzeugdaten erklären das aber plausibel. \
                Deshalb fließt dieser Punkt nicht ins Gesamturteil ein.
                """,
                fact.expectedValue.map { "Erwartet ab Werk: \($0)" },
                "Dokumentiert zur Nachvollziehbarkeit, ohne das Gesamturteil zu belasten.",
                "Kein Beitrag zum Gesamturteil (technisch erklärt)."
            )
        }

        switch id {
        case "region.sn":
            return pack(
                "Ländereinstellung weicht ab",
                """
                Das Fahrzeug meldet intern eine andere Ländereinstellung als für dieses Modell/diese Variante erwartet. \
                Das ist eine Einstellung in der Elektronik — nicht das Kennzeichen oder der Verkaufsort.
                """,
                "Erwartet: \(fact.expectedValue ?? "passende Serieneinstellung für dieses Profil").",
                "Kann auf eine geänderte Konfiguration hinweisen, manchmal aber auch andere Ursachen haben.",
                nil
            )

        case "speed.limit":
            if result.classification == .info {
                return pack(
                    "Geschwindigkeitslimit in Ordnung",
                    "Das gespeicherte Tempolimit entspricht dem erwarteten Serienwert.",
                    fact.expectedValue.map { "Erwartet ab Werk: \($0)" },
                    "Kein Hinweis auf eine Veränderung.",
                    "Kein Beitrag zum Gesamturteil."
                )
            }
            if result.classification == .starkerHinweis {
                return pack(
                    "Tempolimit klar über dem erlaubten Serienwert",
                    """
                    Im Fahrzeug ist ein Geschwindigkeitslimit von \(fact.interpretedValue ?? fact.rawValue) gespeichert. \
                    Liegt das aktive Limit über \(fact.expectedValue ?? "dem Serienwert") bzw. klar über der \
                    Verdachtsschwelle, ist das eine dauerhafte Freigabe — nicht nur Eco/Normal/Sport.
                    """,
                    fact.expectedValue.map { "Erwartet ab Werk: \($0)" },
                    "Das zählt als technisch eindeutiger Hinweis auf eine getunte Konfiguration.",
                    nil
                )
            }
            return pack(
                "Tempolimit höher als ab Werk",
                """
                Im Fahrzeug ist ein höheres Geschwindigkeitslimit gespeichert (\(fact.interpretedValue ?? fact.rawValue)) \
                als für den Serienzustand erwartet. Das bleibt typischerweise dauerhaft gespeichert.
                """,
                fact.expectedValue.map { "Erwartet ab Werk: \($0)" },
                "Spricht für eine dauerhafte Einstellung — nicht nur für das Umschalten von Eco/Normal/Sport.",
                nil
            )

        case "speed.peak":
            return pack(
                "Fahrspitze über dem Serienlimit",
                """
                In der aktuellen Fahrt wurde eine höhere Spitzengeschwindigkeit gemessen \
                (\(fact.interpretedValue ?? fact.rawValue)) als das Serienlimit erwartet. \
                Das zeigt, was gefahren wurde — nicht zwingend, was dauerhaft gespeichert ist.
                """,
                fact.expectedValue.map { "Erwartetes Serienlimit: \($0)" },
                "Kann von einer vorübergehenden Freigabe stammen und nach dem Ausschalten verschwinden.",
                nil
            )

        case "speed.session":
            return pack(
                "Freigabe nur für diese Sitzung",
                "Es gibt Anzeichen für eine vorübergehend erhöhte Freigabe — typischerweise nur, solange der Scooter an ist.",
                "Nach dem Ausschalten sollte dieser Zustand in der Regel weg sein.",
                "Eher temporär als dauerhaft gespeichert.",
                nil
            )

        case "session.reset":
            return pack(
                "Freigabe nach Ausschalten weg",
                "In einem früheren Protokoll war eine erhöhte Freigabe sichtbar; nach dem Ausschalten ist sie nicht mehr feststellbar.",
                "Kein anhaltender Unlock in der aktuellen Sitzung.",
                "Passt zu einer nur vorübergehenden Freigabe.",
                nil
            )

        case "fw.custom":
            return pack(
                "Software der Steuergeräte klar verändert",
                """
                Die Software auf mindestens einem Steuergerät entspricht einem bekannten, nicht serienmäßigen Muster. \
                Das ist ein starkes technisches Merkmal — ohne Aussage, mit welchem Tool das gemacht wurde.
                """,
                "Erwartet: bekannter Serienstand für dieses Modell.",
                "Starker Hinweis auf veränderte Firmware.",
                nil
            )

        case "fw.unknown":
            return pack(
                "Softwarestand unbekannt / nicht serienmäßig katalogisiert",
                """
                Die Software dieses Steuergeräts entspricht keinem bekannten Serienstand für dieses Modell. \
                Das kann eine veränderte Firmware sein — allein noch kein Beweis für Manipulation.
                """,
                "Erwartet: Eintrag im Serienkatalog.",
                "Auffällig, aber oft nur zusammen mit anderen Punkten belastbar.",
                nil
            )

        case "gear.max":
            return pack(
                "Zusätzliche Leistungsstufen freigeschaltet",
                """
                Am Scooter sind mehr Leistungsstufen freigeschaltet, als ab Werk für dieses Modell vorgesehen \
                (\(fact.interpretedValue ?? fact.rawValue)). \
                Das ist nicht dasselbe wie Eco / Normal / Sport — diese Fahrmodi gehören oft zur Serie. \
                Hier geht es um eine erweiterte Freigabe in der Elektronik (Steuergerät VCU).
                """,
                "Erwartet ab Werk: maximal Serienfreigabe (Wert \(fact.expectedValue ?? "1")).",
                "Bleibt in der Regel gespeichert und verschwindet nicht durch Umschalten der Fahrmodi.",
                nil
            )

        case "safelock":
            return pack(
                "Sicherheitsbegrenzung ausgeschaltet",
                "Die serienübliche Sicherheitsbegrenzung (SafeLock) ist derzeit nicht aktiv.",
                "Erwartet: aktive Sicherheitsbegrenzung.",
                "Kann zusammen mit anderen Punkten auf eine geänderte Einstellung hinweisen.",
                nil
            )

        case let cross where cross.hasPrefix("serial.cross"):
            return pack(
                "Steuergerät passt nicht eindeutig zum Fahrzeug",
                """
                Die Kennung eines Steuergeräts stimmt nicht zu den übrigen Fahrzeug-/Modulkennungen. \
                Das kann Tausch, Reparatur oder eine technische Veränderung bedeuten — nicht automatisch Manipulation.
                """,
                "Erwartet: zueinander passende Kennungen.",
                "Allein oft mehrdeutig; im Bericht mit den übrigen Punkten lesen.",
                nil
            )

        default:
            if result.classification == .info || result.classification.rank < EvidenceClass.abweichung.rank {
                return pack(
                    fact.title,
                    "\(fact.title): \(fact.interpretedValue ?? fact.rawValue). Kein Hinweis auf eine Abweichung vom Serienzustand.",
                    fact.expectedValue.map { "Erwartet ab Werk: \($0)" },
                    "Wird dokumentiert, fließt derzeit nicht ins Gesamturteil ein.",
                    "Kein Beitrag zum Gesamturteil."
                )
            }
            return pack(
                fact.title,
                """
                Auffälliger Wert bei „\(fact.title)“: \(fact.interpretedValue ?? fact.rawValue). \
                Der Wert konnte keinem bekannten Serienmuster sicher zugeordnet werden und wird deshalb dokumentiert.
                """,
                fact.expectedValue.map { "Erwarteter Zustand: \($0)" },
                "Kann relevant sein, braucht aber oft weitere Merkmale zur Einordnung.",
                nil
            )
        }
    }

    static func explanation(
        forPowerCycleRow row: PowerCycleDiffRow
    ) -> EvidenceExplanation {
        switch row.changeKind {
        case .unchanged:
            return EvidenceExplanation(
                title: "Bleibt nach dem Ausschalten bestehen",
                summary: "„\(row.title)“ war vor und nach dem Neustart gleich (\(row.scanA)). Das spricht für eine dauerhaft gespeicherte Einstellung.",
                expectedState: row.catalogPersistence.map { "Erwartetes Verhalten: \($0.label)" },
                relevance: "Wahrscheinlich nicht nur ein vorübergehender Sitzungszustand.",
                verdictContribution: nil,
                technical: row.note
            )
        case .disappeared:
            return EvidenceExplanation(
                title: "Nur vorübergehend sichtbar",
                summary: "„\(row.title)“ war vor dem Ausschalten vorhanden (\(row.scanA)) und nach dem Neustart nicht mehr in gleicher Form (\(row.scanB)).",
                expectedState: row.catalogPersistence.map { "Erwartetes Verhalten: \($0.label)" },
                relevance: "Eher temporär als dauerhaft gespeichert.",
                verdictContribution: nil,
                technical: row.note
            )
        case .unavailableAfterRestart:
            return EvidenceExplanation(
                title: "Nach Neustart nicht auslesbar",
                summary: "„\(row.title)“ konnte nach dem Neustart nicht erneut ausgelesen werden. Das heißt nicht automatisch, dass der Wert verschwunden ist.",
                expectedState: nil,
                relevance: "Keine Aussage, ob der Wert weg ist — nur: diesmal nicht lesbar.",
                verdictContribution: nil,
                technical: row.note
            )
        case .appeared:
            return EvidenceExplanation(
                title: "Nach Neustart neu erschienen",
                summary: "„\(row.title)“ war vor dem Neustart nicht bzw. anders vorhanden und danach als \(row.scanB) feststellbar.",
                expectedState: nil,
                relevance: "Dokumentierte Veränderung zwischen den beiden Auslesungen.",
                verdictContribution: nil,
                technical: row.note
            )
        case .changed:
            return EvidenceExplanation(
                title: "Nach Neustart verändert",
                summary: "„\(row.title)“ hat sich von \(row.scanA) auf \(row.scanB) geändert.",
                expectedState: row.catalogPersistence.map { "Erwartetes Verhalten: \($0.label)" },
                relevance: "Änderung im Vergleich vor/nach Ausschalten dokumentiert.",
                verdictContribution: nil,
                technical: row.note
            )
        }
    }

    static func attributionPlain(_ attr: AttributionAssessment) -> String {
        var lines = [attr.headline]
        if let method = attr.suspectedMethod {
            lines.append(method.compatiblePhrase)
        }
        lines.append(
            "Diese Zuordnung ist heuristisch und zeigt nicht, mit welchem konkreten Werkzeug eine Veränderung vorgenommen wurde."
        )
        lines.append("Konfidenz: \(attr.confidenceLabel) (\(String(format: "%.2f", attr.confidence))).")
        return lines.joined(separator: "\n")
    }

    static func verdictPlain(_ verdict: VerdictLevel) -> String {
        verdict.laymanText
    }

    /// Unauffällige / positive Feststellungen — nur Dokumentation, keine Neubewertung.
    static func positiveFindings(
        reading: IntegrityReading,
        profile: ScooterProfile,
        results: [EvidenceResult],
        powerCycle: PowerCycleReport?
    ) -> [MeasuredFact] {
        let ids = Set(results.map(\.fact.markerID))
        var facts: [MeasuredFact] = []

        if !ids.contains(where: { $0.hasPrefix("serial.cross") }) {
            facts.append(MeasuredFact(
                id: "positive.boards.consistent",
                group: .evidence,
                title: "Steuergerät-Kennungen konsistent",
                auslesewert: "keine Cross-Board-Abweichung erkannt",
                sollwert: "zueinander passende Kennungen",
                status: .regelkonform,
                bewertung: "unauffällig",
                erlaeuterung: "Die vorliegenden Modulkennungen passen plausibel zum Fahrzeug. (\(TechnicalGlossary.explanation(for: .crossBoard)))",
                raw: nil,
                volatility: .persistent,
                evidenceClass: .info
            ))
        }

        if !ids.contains("fw.custom"), !ids.contains("fw.unknown") {
            facts.append(MeasuredFact(
                id: "positive.fw.stock",
                group: .evidence,
                title: "Firmware entspricht dem Serienkatalog",
                auslesewert: reading.fwMcu ?? reading.fwVcu ?? "Serienstand",
                sollwert: "katalogisierter Serienstand",
                status: .regelkonform,
                bewertung: "unauffällig",
                erlaeuterung: "Es wurde keine bekannte Custom-Firmware-Signatur und kein unbekannter Mod-Fingerprint festgestellt. (\(TechnicalGlossary.explanation(for: .firmware)))",
                raw: nil,
                volatility: .persistent,
                evidenceClass: .info
            ))
        }

        if !ids.contains("region.sn") {
            let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
            facts.append(MeasuredFact(
                id: "positive.region.stock",
                group: .evidence,
                title: "Region entspricht dem Serienprofil",
                auslesewert: region.label,
                sollwert: profile.market == .de20 ? "DE-Profil" : "EU-Profil",
                status: .regelkonform,
                bewertung: "unauffällig",
                erlaeuterung: "Die interne Regionseinstellung passt zum erwarteten Serienprofil. (\(TechnicalGlossary.explanation(for: .region)))",
                raw: nil,
                volatility: .persistent,
                evidenceClass: .info
            ))
        }

        if !ids.contains("speed.limit") {
            let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
            facts.append(MeasuredFact(
                id: "positive.limit.stock",
                group: .evidence,
                title: "Geschwindigkeitslimit entspricht dem Soll",
                auslesewert: limit.map { Format.kmh.format(Optional($0)) } ?? "im Rahmen",
                sollwert: "≤ \(Format.kmh.format(Optional(profile.ratedMaxKmh)))",
                status: .regelkonform,
                bewertung: "unauffällig",
                erlaeuterung: "Das aktuell gespeicherte Geschwindigkeitslimit entspricht dem erwarteten Serienwert. Dieser Wert liefert aktuell keinen Hinweis auf eine Abweichung vom Serienzustand.",
                raw: nil,
                volatility: .persistent,
                evidenceClass: .info
            ))
        }

        if let pc = powerCycle {
            let persistentAnomalies = pc.rows.filter {
                $0.changeKind == .unchanged
                    && ($0.markerID == "speed.limit" || $0.markerID.hasPrefix("fw."))
                    && $0.scanA != "—"
                    && ids.contains($0.markerID)
            }
            if persistentAnomalies.isEmpty {
                facts.append(MeasuredFact(
                    id: "positive.powercycle.calm",
                    group: .evidence,
                    title: "Power-Cycle ohne auffällige persistente Abweichung",
                    auslesewert: pc.summary,
                    sollwert: "keine zusätzlichen persistenten Auffälligkeiten",
                    status: .regelkonform,
                    bewertung: "unauffällig",
                    erlaeuterung: "Der Vergleich vor/nach Aus- und Einschalten zeigt keine zusätzlichen persistenten Auffälligkeiten. (\(TechnicalGlossary.explanation(for: .powerCycle)))",
                    raw: pc.summary,
                    volatility: .persistent,
                    evidenceClass: .info
                ))
            }
        }

        return facts
    }

    private static func verdictContributionText(_ result: EvidenceResult) -> String {
        if result.isNeutralized {
            return "Kein Beitrag zum Gesamturteil (neutralisiert)."
        }
        if result.contributesToVerdict {
            return "Trägt zum Gesamturteil bei (\(result.classification.label), Gewicht \(result.weight))."
        }
        return "Kein Beitrag zum Gesamturteil."
    }
}

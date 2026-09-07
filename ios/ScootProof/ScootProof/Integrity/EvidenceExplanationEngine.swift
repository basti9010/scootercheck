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

    static func explanation(for result: EvidenceResult) -> EvidenceExplanation {
        let fact = result.fact
        let id = fact.markerID
        let neutralized = result.isNeutralized

        let pack: (String, String, String?, String?, String?) -> EvidenceExplanation = { title, summary, expected, relevance, verdict in
            EvidenceExplanation(
                title: title,
                summary: summary,
                expectedState: expected,
                relevance: relevance,
                verdictContribution: verdict ?? verdictContributionText(result),
                technical: result.chainCitation
            )
        }

        if neutralized {
            let rule = result.neutralizations.first?.ruleId ?? "Regel"
            return pack(
                "Abweichung technisch erklärbar",
                """
                Der gelesene Wert weicht zunächst vom Sollprofil ab. Weitere Fahrzeugdaten erklären diese Abweichung jedoch plausibel \
                (\(rule)). \(TechnicalGlossary.explanation(for: .neutralization)).
                """,
                fact.expectedValue.map { "Erwartet: \($0)" },
                "Die Abweichung wird dokumentiert, zählt aber nicht als relevanter Hinweis für das Gesamturteil.",
                "Kein Beitrag zum Gesamturteil (neutralisiert)."
            )
        }

        switch id {
        case "region.sn":
            return pack(
                "Auffällige Regionseinstellung",
                "Das Fahrzeug meldet intern eine Region, die nicht zum erwarteten Serienprofil dieser Fahrzeugvariante passt. (\(TechnicalGlossary.explanation(for: .region)))",
                "Erwartet wird die zum Fahrzeugmodell passende Regionseinstellung (\(fact.expectedValue ?? "Serienprofil")).",
                "Eine abweichende Region kann auf eine geänderte Fahrzeugkonfiguration hinweisen, kann aber auch andere technische Ursachen haben.",
                nil
            )

        case "speed.limit":
            if result.classification == .info {
                return pack(
                    "Geschwindigkeitslimit entspricht dem Soll",
                    "Das aktuell gespeicherte Geschwindigkeitslimit entspricht dem erwarteten Serienwert. (\(TechnicalGlossary.explanation(for: .speedLimit)))",
                    fact.expectedValue,
                    "Dieser Wert liefert aktuell keinen Hinweis auf eine Abweichung vom Serienzustand.",
                    "Kein Beitrag zum Gesamturteil."
                )
            }
            return pack(
                "Geschwindigkeitslimit weicht vom Soll ab",
                "Das gespeicherte Geschwindigkeitslimit (\(fact.interpretedValue ?? fact.rawValue)) liegt über dem erwarteten Serienwert.",
                fact.expectedValue.map { "Erwartet: \($0)" },
                "Ein erhöhtes Limit kann auf eine dauerhafte Konfigurationsänderung hinweisen (\(TechnicalGlossary.explanation(for: .persistent))).",
                nil
            )

        case "speed.peak":
            return pack(
                "Fahrspitze über dem Serienlimit",
                "In der aktuellen Fahrt wurde eine Spitzengeschwindigkeit erfasst, die über dem erwarteten Serienlimit liegt. (\(TechnicalGlossary.explanation(for: .peakSpeed)))",
                fact.expectedValue.map { "Erwartet: \($0)" },
                "Die Spitze kann von einer vorübergehenden Freigabe stammen und ist oft nicht dauerhaft gespeichert.",
                nil
            )

        case "speed.session":
            return pack(
                "Vorübergehend erhöhte Freigabe erkannt",
                "Es wurden Anzeichen für eine sessiongebundene Freigabe gefunden. (\(TechnicalGlossary.explanation(for: .sessionUnlock)))",
                "Nach dem Ausschalten sollte dieser Zustand typischerweise nicht mehr vorliegen.",
                "Das spricht eher für einen temporären Sitzungszustand als für eine dauerhaft gespeicherte Änderung.",
                nil
            )

        case "session.reset":
            return pack(
                "Frühere Sitzungsfreigabe nach Neustart weg",
                "Im Vergleich zu einem früheren Protokoll war eine erhöhte Freigabe vorhanden; nach dem Ausschalten ist sie nicht mehr feststellbar.",
                "Kein anhaltender Unlock-Zustand in der aktuellen Sitzung.",
                "Das passt zu einem vorübergehenden Sitzungszustand.",
                nil
            )

        case "fw.custom":
            return pack(
                "Firmware weicht klar vom Serienstand ab",
                "Die Steuergeräte-Software entspricht einem bekannten, nicht serienmäßigen Muster. (\(TechnicalGlossary.explanation(for: .customFirmware)))",
                "Erwartet wird ein katalogisierter Serienstand für dieses Modell.",
                "Das ist ein technisch starkes Merkmal für eine veränderte Firmware — ohne Aussage über ein konkretes Werkzeug.",
                nil
            )

        case "fw.unknown":
            return pack(
                "Firmware weicht vom bekannten Serienstand ab",
                "Die Firmware dieses Steuergeräts entspricht keinem bekannten Serienstand für dieses Modell. (\(TechnicalGlossary.explanation(for: .firmware)))",
                "Erwartet wird ein Eintrag im Serienkatalog.",
                "Das kann auf eine veränderte, nicht katalogisierte oder nicht originale Firmware hindeuten — ohne dass allein daraus eine Manipulation bewiesen wäre.",
                nil
            )

        case "gear.max":
            return pack(
                "Gangfreigabe weicht vom Serienzustand ab",
                "Die maximale Gangfreigabe (\(fact.interpretedValue ?? fact.rawValue)) liegt über dem erwarteten Serienwert.",
                fact.expectedValue.map { "Erwartet: \($0)" },
                "Das kann auf eine geänderte Fahrzeugkonfiguration hinweisen.",
                nil
            )

        case "safelock":
            return pack(
                "Sicherheitsbegrenzung inaktiv",
                "Die serienübliche Sicherheitsbegrenzung (SafeLock) ist derzeit nicht aktiv.",
                "Erwartet wird ein aktiver SafeLock-Zustand.",
                "Das kann zusammen mit anderen Merkmalen auf eine Konfigurationsänderung hindeuten.",
                nil
            )

        case let cross where cross.hasPrefix("serial.cross"):
            return pack(
                "Steuergerät passt nicht eindeutig zum Fahrzeug",
                "Die Kennung dieses Steuergeräts stimmt nicht mit den erwarteten Fahrzeug- oder Modulkennungen überein. (\(TechnicalGlossary.explanation(for: .crossBoard)))",
                "Erwartet werden zueinander passende Kennungen der Steuergeräte.",
                "Das kann auf einen Modultausch, eine Reparatur oder eine technische Veränderung hinweisen — nicht automatisch auf eine Manipulation.",
                nil
            )

        default:
            if result.classification == .info || result.classification.rank < EvidenceClass.abweichung.rank {
                return pack(
                    fact.title,
                    "\(fact.title): \(fact.interpretedValue ?? fact.rawValue). Kein Hinweis auf eine Abweichung vom Serienzustand.",
                    fact.expectedValue,
                    "Dieser Wert wird dokumentiert und trägt derzeit nicht zum Gesamturteil bei.",
                    "Kein Beitrag zum Gesamturteil."
                )
            }
            return pack(
                fact.title,
                """
                Technische Feststellung zu \(fact.title): \(fact.interpretedValue ?? fact.rawValue). \
                Dieser Rohwert konnte teilweise keinem bekannten Serienmuster sicher zugeordnet werden und wird dokumentiert.
                """,
                fact.expectedValue.map { "Erwarteter Zustand: \($0)" },
                "Abweichungen vom Serienprofil können technisch relevant sein, erfordern aber oft weitere Merkmale zur Einordnung.",
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
                title: "Änderung bleibt nach dem Ausschalten bestehen",
                summary: "Der Wert „\(row.title)“ war vor und nach dem Neustart gleich (\(row.scanA)). (\(TechnicalGlossary.explanation(for: .persistent)))",
                expectedState: row.catalogPersistence.map { "Katalog: \($0.label)" },
                relevance: "Damit handelt es sich wahrscheinlich nicht nur um einen vorübergehenden Sitzungszustand.",
                verdictContribution: nil,
                technical: row.note
            )
        case .disappeared:
            return EvidenceExplanation(
                title: "Änderung nur vorübergehend festgestellt",
                summary: "„\(row.title)“ war vor dem Ausschalten vorhanden (\(row.scanA)) und nach dem Neustart nicht mehr in gleicher Form feststellbar (\(row.scanB)). (\(TechnicalGlossary.explanation(for: .fleeting)))",
                expectedState: row.catalogPersistence.map { "Katalog: \($0.label)" },
                relevance: "Das spricht eher für einen temporären Sitzungszustand als für eine dauerhaft gespeicherte Änderung.",
                verdictContribution: nil,
                technical: row.note
            )
        case .unavailableAfterRestart:
            return EvidenceExplanation(
                title: "Wert nach Neustart nicht auslesbar",
                summary: "„\(row.title)“ konnte nach dem Neustart nicht erneut ausgelesen werden. Das bedeutet nicht automatisch, dass der Wert verschwunden ist.",
                expectedState: nil,
                relevance: "Keine Aussage über Flüchtigkeit — nur fehlende Auslesbarkeit nach dem Neustart.",
                verdictContribution: nil,
                technical: row.note
            )
        case .appeared:
            return EvidenceExplanation(
                title: "Wert nach Neustart neu erschienen",
                summary: "„\(row.title)“ war vor dem Neustart nicht bzw. anders vorhanden und danach als \(row.scanB) feststellbar.",
                expectedState: nil,
                relevance: "Der Vergleich dokumentiert eine Veränderung zwischen den beiden Auslesungen.",
                verdictContribution: nil,
                technical: row.note
            )
        case .changed:
            return EvidenceExplanation(
                title: "Wert nach Neustart verändert",
                summary: "„\(row.title)“ hat sich von \(row.scanA) auf \(row.scanB) geändert.",
                expectedState: row.catalogPersistence.map { "Katalog: \($0.label)" },
                relevance: "Die Änderung wird im Power-Cycle-Vergleich dokumentiert.",
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
            "Diese Zuordnung ist heuristisch und beweist nicht, mit welchem konkreten Werkzeug eine Veränderung vorgenommen wurde."
        )
        lines.append("Konfidenz: \(attr.confidenceLabel) (\(String(format: "%.2f", attr.confidence))).")
        return lines.joined(separator: "\n")
    }

    static func verdictPlain(_ verdict: VerdictLevel) -> String {
        verdict.laymanText
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

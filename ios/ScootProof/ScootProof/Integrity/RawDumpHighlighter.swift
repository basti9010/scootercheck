import Foundation
import SwiftUI
import UIKit

// MARK: - Annotated raw dump (Quelltext mit farbiger Markierung)

enum RawDumpHighlightSeverity: String, Codable, Sendable, CaseIterable {
    case decisive
    case indicator
    case note

    var bracketPrefix: String {
        switch self {
        case .decisive: return "!!"
        case .indicator: return "!"
        case .note: return "~"
        }
    }

    var pdfColor: UIColor {
        switch self {
        case .decisive: return Theme.UI.danger
        case .indicator: return Theme.UI.warn
        case .note: return Theme.UI.accent
        }
    }

    var uiColor: Color {
        switch self {
        case .decisive: return Theme.danger
        case .indicator: return Theme.warn
        case .note: return Theme.accent
        }
    }

    var legendLabel: String {
        switch self {
        case .decisive: return "Rot — starker Hinweis (urteilswirksam)"
        case .indicator: return "Gelb — Indiz"
        case .note: return "Türkis — Hinweis / Kontext"
        }
    }
}

struct RawDumpAnnotation: Identifiable, Hashable, Sendable {
    var id: String { "\(registerName)-\(markerID)" }
    let registerName: String
    let markerID: String
    let severity: RawDumpHighlightSeverity
    /// Kurzer Klammer-Titel, z. B. „Limit erhöht“.
    let bracketLabel: String
    /// Ein Satz Erklärung (PDF/UI).
    let explanation: String
}

struct RawDumpLine: Identifiable, Hashable, Sendable {
    var id: String { register.id }
    let register: RawRegister
    /// Quelltextzeile: `name = decoded  // addr hex`
    let sourceLine: String
    let annotation: RawDumpAnnotation?

    /// Volle Zeile inkl. Klammer-Annotation für Plaintext/Export.
    var annotatedSourceLine: String {
        guard let annotation else { return sourceLine }
        return "\(sourceLine)  [\(annotation.severity.bracketPrefix) \(annotation.bracketLabel) — \(annotation.explanation)]"
    }
}

enum RawDumpHighlighter {

    /// Gesamter Auslese-Quelltext, entscheidende Register farblich annotiert.
    static func lines(
        reading: IntegrityReading,
        evidence: EvidenceAssessment
    ) -> [RawDumpLine] {
        let byName = annotationsByRegister(reading: reading, evidence: evidence)
        return reading.rawRegisters.map { reg in
            RawDumpLine(
                register: reg,
                sourceLine: formatSourceLine(reg),
                annotation: byName[reg.name]
            )
        }
    }

    static func annotationsByRegister(
        reading: IntegrityReading,
        evidence: EvidenceAssessment
    ) -> [String: RawDumpAnnotation] {
        var map: [String: RawDumpAnnotation] = [:]
        let present = Set(reading.rawRegisters.map(\.name))

        for result in evidence.results where !result.isNeutralized {
            guard result.classification.rank >= EvidenceClass.abweichung.rank else { continue }
            let severity = severity(for: result.classification)
            for name in registerNames(for: result.fact.markerID) where present.contains(name) {
                let ann = annotation(
                    registerName: name,
                    result: result,
                    severity: severity,
                    reading: reading
                )
                // Stärkere Markierung gewinnt bei Mehrfachtreffern.
                if let existing = map[name],
                   severityRank(existing.severity) >= severityRank(ann.severity) {
                    continue
                }
                map[name] = ann
            }
        }

        // Kontext: edmax niedriger als Limit → oft näher am Fahrgefühl (Tacho ~25).
        if present.contains("vcu_g3_edmax"),
           let limit = reading.speedLimitKmh ?? reading.speedMaxKmh,
           let edReg = reading.rawRegisters.last(where: { $0.name == "vcu_g3_edmax" }),
           let edKmh = parsedKmh(from: edReg),
           edKmh + 1 < limit,
           map["vcu_g3_edmax"] == nil {
            map["vcu_g3_edmax"] = RawDumpAnnotation(
                registerName: "vcu_g3_edmax",
                markerID: "context.edmax",
                severity: .note,
                bracketLabel: "Weitere Tempo-Kappe",
                explanation: "Oft näher am Fahrgefühl als maxspd — nicht das gespeicherte Max-Limit."
            )
        }

        return map
    }

    // MARK: - Formatting

    static func formatSourceLine(_ reg: RawRegister) -> String {
        let decoded = reg.valueDecoded?.trimmingCharacters(in: .whitespacesAndNewlines)
        let valuePart: String
        if let decoded, !decoded.isEmpty {
            valuePart = decoded
        } else {
            valuePart = reg.valueHex
        }
        return "\(reg.name) = \(valuePart)  // \(reg.address) \(reg.valueHex)"
    }

    // MARK: - Mapping

    private static func registerNames(for markerID: String) -> [String] {
        switch markerID {
        case "speed.limit":
            // Nur Max-Limit-Register — edmax separat als Kontext-Hinweis.
            return ["vcu_g3_maxspd", "dis_limit"]
        case "speed.peak":
            return ["vcu_g3_trip_max", "dis_trip_max", "tft_trip_max"]
        case "speed.session":
            return ["vcu_g3_maxspd", "dis_trip_max", "vcu_g3_trip_max"]
        case "gear.max":
            return ["vcu_g3_gear", "vcu_g3_sgear", "vcu_g3_egear"]
        case "fw.unknown", "fw.custom":
            return ["g3_mcu_fw", "g3_mcu_fw_fb", "g3_ble_fw", "g3_vcu_fw", "g3_vcu_fw4", "g3_bms_fw"]
        case "region.sn":
            return ["vcu_g3_sn", "dis_sn", "vcu_sn", "ble_sn"]
        case "safelock":
            return ["mcu_safe", "vcu_g3_safe"]
        default:
            if markerID.hasPrefix("serial.cross") {
                return ["vcu_g3_sn", "ble_sn", "mcu_g3_sn"]
            }
            return []
        }
    }

    private static func annotation(
        registerName: String,
        result: EvidenceResult,
        severity: RawDumpHighlightSeverity,
        reading: IntegrityReading
    ) -> RawDumpAnnotation {
        let marker = result.fact.markerID
        let (bracket, explain) = labels(for: marker, registerName: registerName, result: result, reading: reading)
        return RawDumpAnnotation(
            registerName: registerName,
            markerID: marker,
            severity: severity,
            bracketLabel: bracket,
            explanation: explain
        )
    }

    private static func labels(
        for markerID: String,
        registerName: String,
        result: EvidenceResult,
        reading: IntegrityReading
    ) -> (String, String) {
        switch markerID {
        case "speed.limit":
            let kmh = reading.speedLimitKmh.map { Format.kmh.format($0) } ?? result.fact.interpretedValue ?? "?"
            return (
                "Limit erhöht",
                "Gespeicherte Freigabe \(kmh) — nicht die Tacho-/Cruise-Geschwindigkeit."
            )
        case "speed.peak":
            let kmh = reading.peakSpeedKmh.map { Format.kmh.format($0) } ?? result.fact.interpretedValue ?? "?"
            return (
                "Trip-Spitze",
                "Höchster Moment \(kmh) (z. B. Hochheben) — nicht das eingestellte Limit."
            )
        case "speed.session":
            return (
                "Session-Freigabe",
                "Vorübergehend erhöhtes Tempo, oft nur bis Ausschalten sichtbar."
            )
        case "gear.max":
            return (
                "Leistungsstufen",
                result.fact.interpretedValue.map { "\($0) über Serienfreigabe." }
                    ?? "Mehr Stufen als für dieses Profil vorgesehen."
            )
        case "fw.unknown":
            return (
                "FW unklar",
                "Version von \(registerName) nicht im Serienkatalog — allein kein Beweis."
            )
        case "fw.custom":
            return (
                "Custom-FW",
                "Versionskennung weicht vom Hersteller-Muster ab."
            )
        case "region.sn":
            return (
                "Region",
                "SN-Region weicht vom gewählten Sollprofil ab."
            )
        case "safelock":
            return (
                "SafeLock",
                "Sicherheitsbegrenzung derzeit inaktiv."
            )
        default:
            let title = result.plainLanguage.shortTitle.isEmpty
                ? result.fact.title
                : result.plainLanguage.shortTitle
            return (title, shortSentence(result.plainLanguage.humanReadableExplanation))
        }
    }

    private static func severity(for classification: EvidenceClass) -> RawDumpHighlightSeverity {
        switch classification {
        case .starkerHinweis: return .decisive
        case .indiz: return .indicator
        default: return .note
        }
    }

    private static func severityRank(_ s: RawDumpHighlightSeverity) -> Int {
        switch s {
        case .decisive: return 3
        case .indicator: return 2
        case .note: return 1
        }
    }

    private static func parsedKmh(from reg: RawRegister) -> Double? {
        if let decoded = reg.valueDecoded {
            let digits = decoded.replacingOccurrences(
                of: "[^0-9.,]",
                with: "",
                options: .regularExpression
            ).replacingOccurrences(of: ",", with: ".")
            if let v = Double(digits), v > 0, v < 120 { return v }
        }
        guard let raw = UInt16(reg.valueHex, radix: 16) else { return nil }
        return RegisterScale.g3StoredSpeedKmh(raw)
    }

    private static func shortSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = trimmed.firstIndex(of: ".") else {
            return String(trimmed.prefix(120))
        }
        let end = trimmed.index(after: dot)
        return String(trimmed[..<end])
    }
}

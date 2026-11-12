import Foundation

enum FirmwareForensicScorer {
    static func score(
        crypto: FirmwareCryptoAssessment,
        comparison: FirmwareComparisonResult?,
        evidence: [FirmwareEvidenceItem],
        hasPrimaryPayload: Bool
    ) -> (FirmwareForensicVerdict, String) {
        if !hasPrimaryPayload {
            return (.gray, "Keine auswertbare Firmware-Payload — unzureichende Datengrundlage.")
        }

        if let comparison, comparison.outcome == .identical {
            return (.green, "SHA-256 stimmt mit einer importierten/gelisteten Referenz überein. Keine Byte-Abweichung festgestellt.")
        }

        if let comparison, comparison.outcome == .different, (comparison.differingBytes ?? 0) > 0 {
            return (
                .red,
                "Byte-Vergleich gegen geeignete Referenz zeigt konkrete Abweichung (\(comparison.differingBytes ?? 0) Bytes). Keine automatische Bewertung als illegal."
            )
        }

        // Encrypted / no reference → gray or yellow
        switch crypto.status {
        case .confirmedByMetadata, .likelyByStructure:
            let nameHint = evidence.contains { $0.category == .filenameHint }
            if nameHint {
                return (
                    .yellow,
                    "Verschlüsselte/unlesbare Payload plus unverifizierte Dateiname-Hinweise — weitere Prüfung erforderlich, keine Funktionsaussage."
                )
            }
            return (
                .gray,
                "Verschlüsselte oder strukturell unlesbare Firmware ohne Klartext-Referenzvergleich — keine ausreichende Datengrundlage für inhaltliche Abweichung."
            )
        case .unknownFormat:
            return (.gray, "Format nicht eindeutig klassifizierbar.")
        case .plaintext:
            break
        }

        if comparison?.outcome == .notPossible || comparison == nil {
            let indicative = evidence.contains { $0.verifiability == .indicative && ($0.category == .modeHint || $0.category == .limitHint) }
            if indicative {
                return (.yellow, "Klartext-Image ohne passende Referenz; indikative String-/Parameterhinweise — weitere Prüfung / Referenzimport empfohlen.")
            }
            return (.yellow, "Klartext-Image ohne passende Referenz — Firmware unbekannt, weitere Prüfung erforderlich.")
        }

        if comparison?.outcome == .knownAlternate || comparison?.outcome == .unknown {
            return (.yellow, "Hash weicht von Referenz ab bzw. ist unbekannt — Auffälligkeit, Wirkung am Fahrzeug nicht aus der Datei allein ableitbar.")
        }

        return (.gray, "Keine ausreichende Datengrundlage für eine abweichende Feststellung.")
    }
}

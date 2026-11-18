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
            // Identität ≠ OEM-Authentizität der Referenz.
            let note = comparison.note.lowercased()
            let looksVerified = note.contains("hersteller-/intern verifiziert")
                || note.contains("oem-confirmed")
                || (note.contains("verifiziert") && !note.contains("nicht") && !note.contains("unbestätigt"))
            if looksVerified {
                return (
                    .green,
                    "SHA-256 stimmt mit einer als authentisch gekennzeichneten OEM-Referenz überein. Keine Byte-Abweichung festgestellt."
                )
            }
            return (
                .yellow,
                "SHA-identisch mit importierter/gelisteter Referenz — Firmwareidentität ja, Referenzvertrauen nicht herstellerseitig bestätigt (kein automatisches GRÜN)."
            )
        }

        if let comparison, comparison.outcome == .different, (comparison.differingBytes ?? 0) > 0 {
            // Byte-Diff allein ist kein ROT — Ursache (Update/Patch/Manipulation) offen.
            return (
                .yellow,
                "Byte-Vergleich gegen Referenz zeigt Abweichung (\(comparison.differingBytes ?? 0) Bytes). Ohne funktionalen Manipulationsnachweis keine ROT-Einstufung."
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

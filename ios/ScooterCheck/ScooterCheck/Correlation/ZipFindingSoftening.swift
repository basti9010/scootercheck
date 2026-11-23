import Foundation

/// Post-Pass über ZIP-Heuristik-Findings: demoten, nicht löschen.
/// Quelle der Wahrheit bleibt `FirmwareZipAnalyzer.scanBinaryHeuristics`.
enum ZipFindingSoftening {

    private static let genericNeedles: Set<String> = [
        "power button",
        "mode button",
        "km/h",
        "kmh"
    ]

    static func soften(_ findings: [CorrelationZipFindingInput]) -> [SoftenedZipFinding] {
        findings.map(softenOne)
    }

    static func softenOne(_ finding: CorrelationZipFindingInput) -> SoftenedZipFinding {
        let needle = (finding.needle ?? extractNeedle(from: finding.detail) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if isGenericNeedle(needle) {
            return SoftenedZipFinding(
                id: finding.id,
                kindRaw: finding.kindRaw,
                title: finding.title,
                detail: finding.detail,
                confidence: .low,
                epistemics: .hypothesis,
                source: finding.source,
                annotation: "Datei-Hinweis — am Fahrzeug unbestätigt (generische Nadel abgeschwächt)."
            )
        }

        if finding.kindRaw == "unlockGesture" || finding.kindRaw == "customFirmware" {
            return SoftenedZipFinding(
                id: finding.id,
                kindRaw: finding.kindRaw,
                title: finding.title,
                detail: finding.detail,
                confidence: finding.confidence,
                epistemics: .hypothesis,
                source: finding.source,
                annotation: "Datei-Hinweis — am Fahrzeug unbestätigt."
            )
        }

        if needle.count < 4, finding.confidence != .low {
            return SoftenedZipFinding(
                id: finding.id,
                kindRaw: finding.kindRaw,
                title: finding.title,
                detail: finding.detail,
                confidence: .low,
                epistemics: .hypothesis,
                source: finding.source,
                annotation: "Kurze Nadel — Konfidenz auf niedrig gesetzt."
            )
        }

        return SoftenedZipFinding(
            id: finding.id,
            kindRaw: finding.kindRaw,
            title: finding.title,
            detail: finding.detail,
            confidence: finding.confidence,
            epistemics: .hypothesis,
            source: finding.source,
            annotation: nil
        )
    }

    private static func isGenericNeedle(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        if genericNeedles.contains(needle) { return true }
        if needle == "km/h" || needle == "kmh" { return true }
        return genericNeedles.contains(where: { needle == $0 || needle.hasPrefix($0 + " ") })
    }

    private static func extractNeedle(from detail: String) -> String? {
        if let range = detail.range(of: "„"),
           let end = detail.range(of: "“", range: range.upperBound..<detail.endIndex) {
            return String(detail[range.upperBound..<end.lowerBound])
        }
        if let range = detail.range(of: "\"") {
            let rest = detail[range.upperBound...]
            if let end = rest.range(of: "\"") {
                return String(rest[..<end.lowerBound])
            }
        }
        return nil
    }
}

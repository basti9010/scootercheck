import Foundation

/// Anti-Halluzination: Tastenfolgen nur bei Live-/Belegt-/Validiert-Zeilen.
enum FirmwareComboPolicy {
    static let unbelegtTrigger = "Aus Code nicht als Tastenfolge belegt"

    private static let validatedPrefixes = [
        "live-kombination",
        "live-vergleich",
        "validiert:",
        "belegt:"
    ]

    static func isValidatedCombo(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return false }
        return validatedPrefixes.contains { t.hasPrefix($0) }
    }

    static func sanitizeComboSummaries(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, seen.insert(line).inserted else { continue }
            guard isValidatedCombo(line) else { continue }
            out.append(line)
        }
        return out
    }

    static func sanitizeTrigger(_ trigger: String) -> String {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return unbelegtTrigger }
        if isValidatedCombo(t) || t.lowercased().hasPrefix("belegt:") { return t }
        let low = t.lowercased()
        if low.contains("gas") || low.contains("bremse") || low.contains("vermut")
            || low.contains("modellabhängig") || low.contains("häufig")
            || low.contains("tastenkombi") || low == "kombi" {
            return unbelegtTrigger
        }
        return t
    }
}

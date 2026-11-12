import CryptoKit
import Foundation

/// Ergebnis der Read-Only-Auswertung einer Flash-/Firmware-ZIP (kein Flashen).
struct FirmwareZipReport: Equatable, Sendable, Identifiable {
    var id: String { fileName + ":" + analyzedAt.timeIntervalSince1970.description }
    var fileName: String
    var analyzedAt: Date
    var formatLabel: String
    var displayName: String?
    var models: [String]
    var firmwareType: String?
    var compatibleBoards: [String]
    var declaredMd5: String?
    var computedMd5: String?
    var md5Matches: Bool?
    var firmSizeBytes: Int?
    var paramsText: String?
    var entryNames: [String]
    var findings: [Finding]
    var warnings: [String]
    var summary: String

    struct Finding: Equatable, Sendable, Identifiable {
        var id: String { "\(kind.rawValue)-\(title)-\(detail.prefix(40))" }
        var kind: Kind
        var title: String
        var detail: String
        var confidence: Confidence
        var source: String

        enum Kind: String, Sendable {
            case metadata
            case unlockGesture
            case speedLimit
            case featureFlag
            case region
            case customFirmware
            case note
        }

        enum Confidence: String, Sendable {
            case high
            case medium
            case low

            var label: String {
                switch self {
                case .high: return "hoch"
                case .medium: return "mittel"
                case .low: return "niedrig"
                }
            }
        }
    }
}

enum FirmwareZipAnalyzer {
    /// Liest eine ZIP aus Data (z. B. Datei vom iPhone) — nur Analyse.
    static func analyze(fileName: String, data: Data) -> FirmwareZipReport {
        var warnings: [String] = []
        var findings: [FirmwareZipReport.Finding] = []
        let entries: [MinimalZipReader.Entry]
        do {
            entries = try MinimalZipReader.entries(from: data)
        } catch {
            return FirmwareZipReport(
                fileName: fileName,
                analyzedAt: Date(),
                formatLabel: "Unbekannt / kein ZIP",
                displayName: nil,
                models: [],
                firmwareType: nil,
                compatibleBoards: [],
                declaredMd5: nil,
                computedMd5: nil,
                md5Matches: nil,
                firmSizeBytes: nil,
                paramsText: nil,
                entryNames: [],
                findings: [],
                warnings: [error.localizedDescription],
                summary: "Datei konnte nicht als ZIP gelesen werden."
            )
        }

        var byBase: [String: MinimalZipReader.Entry] = [:]
        for entry in entries {
            let base = entry.name.split(separator: "/").last.map(String.init)?.lowercased()
                ?? entry.name.lowercased()
            if byBase[base] == nil { byBase[base] = entry }
        }
        let entryNames = entries.map(\.name).sorted()

        let infoEntry = byBase["info.json"]
        let firmEntry = byBase["firm.bin"] ?? byBase.first(where: { $0.key.hasSuffix(".bin") })?.value
        let paramsEntry = byBase["params.txt"] ?? byBase["changelog.txt"] ?? byBase["readme.txt"]

        var displayName: String?
        var models: [String] = []
        var firmwareType: String?
        var compatible: [String] = []
        var declaredMd5: String?
        var formatLabel = "ZIP (allgemein)"

        if let infoEntry, let meta = parseInfoJSON(infoEntry.data) {
            formatLabel = meta.schemaVersion.map { "ScooterHacking ZIPv3 (schema \($0))" } ?? "ScooterHacking-ähnlich"
            displayName = meta.displayName
            models = meta.models
            firmwareType = meta.type
            compatible = meta.compatible
            declaredMd5 = meta.md5?.lowercased()
            findings.append(.init(
                kind: .metadata,
                title: "Paket-Metadaten",
                detail: [
                    displayName.map { "Name: \($0)" },
                    firmwareType.map { "Ziel-Board: \($0)" },
                    models.isEmpty ? nil : "Modelle: \(models.joined(separator: ", "))",
                    compatible.isEmpty ? nil : "Boards: \(compatible.joined(separator: ", "))"
                ].compactMap { $0 }.joined(separator: " · "),
                confidence: .high,
                source: "info.json"
            ))
        } else if firmEntry != nil {
            warnings.append("Kein gültiges info.json — Metadaten eingeschränkt.")
        } else {
            warnings.append("Kein FIRM.bin / info.json erkannt. Es werden nur Texttreffer im Archiv ausgewertet.")
        }

        var computedMd5: String?
        var md5Matches: Bool?
        var firmSize: Int?
        if let firmEntry {
            firmSize = firmEntry.data.count
            computedMd5 = Insecure.MD5.hash(data: firmEntry.data).map { String(format: "%02x", $0) }.joined()
            if let declaredMd5 {
                md5Matches = declaredMd5 == computedMd5
                if md5Matches == false {
                    warnings.append("MD5 in info.json stimmt nicht mit FIRM.bin überein.")
                }
            }
        }

        let paramsText = paramsEntry.flatMap { String(data: $0.data, encoding: .utf8) }
            ?? paramsEntry.flatMap { String(data: $0.data, encoding: .isoLatin1) }
        if let paramsText {
            findings.append(contentsOf: parseParamsFindings(paramsText))
        }

        // Binär-/ASCII-Heuristik über alle Text-Einträge + Firmware-Image.
        var haystacks: [(String, Data)] = entries.map { ($0.name, $0.data) }
        if let firmEntry { haystacks.append(("FIRM.bin", firmEntry.data)) }
        findings.append(contentsOf: scanBinaryHeuristics(haystacks))

        // Dedup similar titles
        findings = dedupe(findings)

        let summary = buildSummary(
            displayName: displayName,
            type: firmwareType,
            models: models,
            findings: findings,
            md5Matches: md5Matches
        )

        return FirmwareZipReport(
            fileName: fileName,
            analyzedAt: Date(),
            formatLabel: formatLabel,
            displayName: displayName,
            models: models,
            firmwareType: firmwareType,
            compatibleBoards: compatible,
            declaredMd5: declaredMd5,
            computedMd5: computedMd5,
            md5Matches: md5Matches,
            firmSizeBytes: firmSize,
            paramsText: paramsText,
            entryNames: entryNames,
            findings: findings,
            warnings: warnings,
            summary: summary
        )
    }

    // MARK: - info.json

    private struct InfoMeta {
        var schemaVersion: Int?
        var displayName: String?
        var models: [String]
        var type: String?
        var compatible: [String]
        var md5: String?
    }

    private static func parseInfoJSON(_ data: Data) -> InfoMeta? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let fw = (obj["firmware"] as? [String: Any]) ?? obj
        let models = (fw["models"] as? [String]) ?? []
        let compatible = (fw["compatible"] as? [String]) ?? []
        return InfoMeta(
            schemaVersion: obj["schemaVersion"] as? Int,
            displayName: fw["displayName"] as? String,
            models: models,
            type: fw["type"] as? String,
            compatible: compatible,
            md5: fw["md5"] as? String
        )
    }

    // MARK: - params.txt

    private static func parseParamsFindings(_ text: String) -> [FirmwareZipReport.Finding] {
        var out: [FirmwareZipReport.Finding] = []
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()

            if lower.contains("max speed") || lower.contains("eu max") || lower.contains("de max")
                || lower.contains("höchstgeschwindigkeit") || lower.contains("speed limit") {
                out.append(.init(
                    kind: .speedLimit,
                    title: "Geschwindigkeitsparameter",
                    detail: trimmed,
                    confidence: .high,
                    source: "params.txt"
                ))
            }
            if lower.contains("region") || lower.contains("firmware region") {
                out.append(.init(
                    kind: .region,
                    title: "Region / Marktbezug",
                    detail: trimmed,
                    confidence: .high,
                    source: "params.txt"
                ))
            }
            if lower.contains("compat") || lower.contains("spoof") || lower.contains("shfw")
                || lower.contains("cfw") || lower.contains("custom") {
                out.append(.init(
                    kind: .customFirmware,
                    title: "Custom-/Compat-Hinweis",
                    detail: trimmed,
                    confidence: .high,
                    source: "params.txt"
                ))
            }
            if lower.contains("kers") || lower.contains("cruise") || lower.contains("field weaken")
                || lower.contains("dpc") || lower.contains("profile") {
                out.append(.init(
                    kind: .featureFlag,
                    title: "Fahr-/Leistungsfunktion",
                    detail: trimmed,
                    confidence: .medium,
                    source: "params.txt"
                ))
            }
            if lower.contains("unlock") || lower.contains("gesture") || lower.contains("sequence")
                || lower.contains("brake") && lower.contains("throttle")
                || lower.contains("button") && (lower.contains("press") || lower.contains("hold")) {
                out.append(.init(
                    kind: .unlockGesture,
                    title: "Möglicher Freischalt-/Gestenhinweis",
                    detail: trimmed,
                    confidence: .medium,
                    source: "params.txt"
                ))
            }
        }
        if out.isEmpty, text.count > 20 {
            out.append(.init(
                kind: .note,
                title: "Begleittext vorhanden",
                detail: String(text.prefix(280)),
                confidence: .low,
                source: "params.txt"
            ))
        }
        return out
    }

    // MARK: - Binary / string heuristics

    private static func scanBinaryHeuristics(_ haystacks: [(String, Data)]) -> [FirmwareZipReport.Finding] {
        var out: [FirmwareZipReport.Finding] = []
        let patterns: [(kind: FirmwareZipReport.Finding.Kind, needles: [String], title: String, confidence: FirmwareZipReport.Finding.Confidence)] = [
            (.customFirmware, ["SHFW", "ScooterHacking", "CFW", "COMPAT", "compat patch"], "Custom-Firmware-Signatur", .high),
            (.unlockGesture, ["soft unlock", "softunlock", "german maneuver", "GermanManeuver", "GM unlock"], "Soft-Unlock-/Maneuver-Hinweis", .medium),
            (.unlockGesture, [
                "throttle and brake", "brake and throttle", "brake+throttle", "brake and main button",
                "Applied profile at boot", "profile at boot", "custom sequence",
                "double press", "button press"
            ], "Profil-/Tastenfolge (SHFW-Stil)", .medium),
            (.unlockGesture, ["hold brake", "hold throttle", "power button", "mode button"], "Bedienhinweis in Strings", .low),
            (.speedLimit, ["Max speed", "EU Max speed", "DE Max speed", "speed limit", "km/h"], "Speed-Limit-String", .medium),
            (.region, ["Firmware region", "region unlock", "US region", "DE region", "EU region"], "Region-String", .medium),
            (.featureFlag, ["field weaken", "KERS", "cruise control", "DPC", "version spoof"], "Feature-String", .low),
        ]

        for (source, data) in haystacks {
            let ascii = extractASCIIStrings(from: data, minLength: 6)
            let blob = ascii.joined(separator: "\n")
            let lowerBlob = blob.lowercased()
            for pattern in patterns {
                for needle in pattern.needles {
                    if lowerBlob.contains(needle.lowercased()) {
                        let context = contextLine(in: ascii, containing: needle) ?? needle
                        out.append(.init(
                            kind: pattern.kind,
                            title: pattern.title,
                            detail: context,
                            confidence: pattern.confidence,
                            source: source
                        ))
                        break
                    }
                }
            }

            // Explizite „n×“-Gesten in Klartext (z. B. „brake 6x“, „6x brake“)
            if let gesture = matchRepetitionGesture(in: ascii) {
                out.append(.init(
                    kind: .unlockGesture,
                    title: "Wiederholungs-Geste erkannt",
                    detail: gesture,
                    confidence: .medium,
                    source: source
                ))
            }
        }
        return out
    }

    private static func extractASCIIStrings(from data: Data, minLength: Int) -> [String] {
        var out: [String] = []
        var current = Data()
        for byte in data {
            if byte >= 32 && byte < 127 {
                current.append(byte)
            } else {
                if current.count >= minLength,
                   let s = String(data: current, encoding: .ascii) {
                    out.append(s)
                }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= minLength, let s = String(data: current, encoding: .ascii) {
            out.append(s)
        }
        // Cap for huge firmwares
        if out.count > 4000 { return Array(out.prefix(4000)) }
        return out
    }

    private static func contextLine(in strings: [String], containing needle: String) -> String? {
        let n = needle.lowercased()
        return strings.first(where: { $0.lowercased().contains(n) }).map {
            $0.count > 160 ? String($0.prefix(157)) + "…" : $0
        }
    }

    private static func matchRepetitionGesture(in strings: [String]) -> String? {
        let re = try? NSRegularExpression(
            pattern: #"(?i)((brake|throttle|button|power|mode|hebel|bremse|gas).{0,24}(\d{1,2})\s*[x×]|(\d{1,2})\s*[x×]\s*(brake|throttle|button|power|mode|hebel|bremse|gas))"#
        )
        for s in strings {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            if let m = re?.firstMatch(in: s, range: range), let r = Range(m.range, in: s) {
                let hit = String(s[r])
                return hit.count > 120 ? String(hit.prefix(117)) + "…" : hit
            }
        }
        return nil
    }

    private static func dedupe(_ findings: [FirmwareZipReport.Finding]) -> [FirmwareZipReport.Finding] {
        var seen = Set<String>()
        var out: [FirmwareZipReport.Finding] = []
        for f in findings {
            let key = "\(f.kind.rawValue)|\(f.title)|\(f.detail.lowercased())"
            if seen.insert(key).inserted { out.append(f) }
        }
        return out
    }

    private static func buildSummary(
        displayName: String?,
        type: String?,
        models: [String],
        findings: [FirmwareZipReport.Finding],
        md5Matches: Bool?
    ) -> String {
        var parts: [String] = []
        if let displayName, !displayName.isEmpty {
            parts.append(displayName)
        }
        if let type { parts.append("Ziel \(type)") }
        if !models.isEmpty { parts.append("Modelle \(models.joined(separator: "/"))") }
        let unlocks = findings.filter { $0.kind == .unlockGesture }.count
        let speeds = findings.filter { $0.kind == .speedLimit }.count
        let custom = findings.contains { $0.kind == .customFirmware }
        if custom { parts.append("Custom-/SHFW-Hinweise") }
        if unlocks > 0 { parts.append("\(unlocks) Gesten-/Freischalthinweis(e)") }
        if speeds > 0 { parts.append("\(speeds) Speed-Parameter") }
        if md5Matches == true { parts.append("MD5 ok") }
        if md5Matches == false { parts.append("MD5 abweichend") }
        if parts.isEmpty {
            return "ZIP gelesen — keine klaren Firmware-Metadaten. Treffer siehe Liste."
        }
        return parts.joined(separator: " · ")
            + " — Einschätzung aus Dateiinhalt, kein Nachweis der Wirkung am Fahrzeug."
    }
}

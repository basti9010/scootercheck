import Foundation

enum FirmwareBinaryStaticAnalyzer {
    static func analyze(
        path: String?,
        data: Data?,
        crypto: FirmwareCryptoAssessment,
        meta: FirmwarePackageMeta,
        paramsText: String?
    ) -> (FirmwareBinaryAnalysis, [FirmwareEvidenceItem]) {
        var evidence: [FirmwareEvidenceItem] = []

        // Filename-only hints (never treated as confirmed function)
        if let path {
            let base = FirmwarePackageLoader.baseName(path)
            if base.lowercased().contains("panic") {
                evidence.append(.init(
                    id: "fn-panic",
                    category: .filenameHint,
                    title: "Dateiname enthält „panic“",
                    detail: "Nicht verifizierter Hinweis aus dem Dateinamen — keine Aussage über Wirkung am Fahrzeug.",
                    evidence: "Dateiname: \(base)",
                    method: "Dateiname-Muster",
                    verifiability: .unverified,
                    confirmed: false
                ))
            }
        }

        // Compatible board family hints from metadata (not CFW signatures)
        for board in meta.compatible {
            let l = board.lowercased()
            if l.contains("at32") {
                evidence.append(.init(
                    id: "meta-at32-\(board)",
                    category: .architecture,
                    title: "Zielhardware AT32 (Metadaten)",
                    detail: board,
                    evidence: "info.json compatible",
                    method: "Metadatenfeld compatible",
                    verifiability: .confirmed,
                    confirmed: true
                ))
            }
            if l.contains("stm32") {
                evidence.append(.init(
                    id: "meta-stm32-\(board)",
                    category: .architecture,
                    title: "Zielhardware STM32 (Metadaten)",
                    detail: board,
                    evidence: "info.json compatible",
                    method: "Metadatenfeld compatible",
                    verifiability: .confirmed,
                    confirmed: true
                ))
            }
        }

        if let paramsText {
            evidence.append(contentsOf: analyzeParams(paramsText))
        }

        switch crypto.status {
        case .confirmedByMetadata, .likelyByStructure:
            let reason = "Firmwarepayload erscheint verschlüsselt/hochentropisch — Binäranalyse des Klartexts nicht verfügbar."
            evidence.append(.init(
                id: "bin-skip-crypto",
                category: .limitation,
                title: "Funktionsanalyse nicht verfügbar",
                detail: reason,
                evidence: crypto.evidence.joined(separator: "; "),
                method: "Crypto-Assessment",
                verifiability: .unavailable,
                confirmed: false
            ))
            return (
                FirmwareBinaryAnalysis(
                    performed: false,
                    unavailableReason: reason,
                    architecture: architectureFromMeta(meta),
                    vectorTableLikely: false,
                    resetHandlerHint: nil,
                    stringsSample: [],
                    codeDataNotes: []
                ),
                evidence
            )
        case .unknownFormat:
            evidence.append(.init(
                id: "bin-skip-unknown",
                category: .limitation,
                title: "Binäranalyse eingeschränkt",
                detail: "Format nicht eindeutig — nur vorsichtige strukturelle Checks.",
                evidence: crypto.detectedFormat,
                method: "Crypto-Assessment",
                verifiability: .unavailable,
                confirmed: false
            ))
        case .plaintext:
            break
        }

        guard let data, !data.isEmpty else {
            let reason = "Keine Firmware-Bytes für statische Analyse."
            evidence.append(.init(
                id: "bin-empty",
                category: .limitation,
                title: "Keine Payload",
                detail: reason,
                evidence: path ?? "—",
                method: "Inventory",
                verifiability: .unavailable,
                confirmed: false
            ))
            return (
                FirmwareBinaryAnalysis(
                    performed: false,
                    unavailableReason: reason,
                    architecture: architectureFromMeta(meta),
                    vectorTableLikely: false,
                    resetHandlerHint: nil,
                    stringsSample: [],
                    codeDataNotes: []
                ),
                evidence
            )
        }

        let vector = FirmwareCryptoAssessor.looksLikeArmVectorTable(data)
        var arch = architectureFromMeta(meta)
        if vector && arch == .unknown { arch = .armCortexMLikely }

        var resetHint: String?
        if data.count >= 8 {
            let sp = u32(data, 0)
            let rst = u32(data, 4)
            resetHint = String(format: "SP=0x%08X Reset=0x%08X @0", sp, rst)
            if vector {
                evidence.append(.init(
                    id: "vec-table",
                    category: .architecture,
                    title: "Mögliche ARM-Cortex-M-Vektortabelle",
                    detail: resetHint ?? "",
                    evidence: "Offset 0x0–0x7",
                    method: "Header-Heuristik (SP in SRAM, Thumb-Reset)",
                    verifiability: .indicative,
                    confirmed: false
                ))
            }
        }

        let strings = extractASCIIStrings(data, minLength: 6, limit: 250)
        // Do NOT treat JSON key vocabulary as CFW. Only scan firmware/params strings with careful patterns.
        evidence.append(contentsOf: scanFirmwareStrings(strings, sourcePath: path ?? "FIRM.bin"))

        var codeNotes: [String] = []
        codeNotes.append(String(format: "Größe %d Byte, Entropie %.2f", data.count, FirmwareDigest.shannonEntropy(data)))
        if vector {
            codeNotes.append("Dateianfang kompatibel mit Cortex-M-Vektortabelle (indikativ).")
        } else {
            codeNotes.append("Kein klares Cortex-M-Vektormuster am Offset 0.")
        }

        return (
            FirmwareBinaryAnalysis(
                performed: true,
                unavailableReason: nil,
                architecture: arch,
                vectorTableLikely: vector,
                resetHandlerHint: resetHint,
                stringsSample: Array(strings.prefix(40)),
                codeDataNotes: codeNotes
            ),
            evidence
        )
    }

    private static func architectureFromMeta(_ meta: FirmwarePackageMeta) -> FirmwareArchitectureHint {
        let joined = (meta.compatible + meta.models + [meta.type ?? ""]).joined(separator: " ").lowercased()
        if joined.contains("at32") { return .at32FamilyHint }
        if joined.contains("stm32") { return .stm32FamilyHint }
        return .unknown
    }

    private static func analyzeParams(_ text: String) -> [FirmwareEvidenceItem] {
        var out: [FirmwareEvidenceItem] = []
        for (idx, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.contains("max speed") || lower.contains("eu max") || lower.contains("de max")
                || lower.contains("speed limit") || lower.contains("höchstgeschwindigkeit") {
                out.append(.init(
                    id: "params-speed-\(idx)",
                    category: .limitHint,
                    title: "Geschwindigkeitsparameter (params)",
                    detail: line,
                    evidence: "params.txt Zeile \(idx + 1)",
                    method: "Strukturierte params.txt-Auswertung",
                    verifiability: .confirmed,
                    confirmed: true
                ))
            }
            if lower.contains("region") {
                out.append(.init(
                    id: "params-region-\(idx)",
                    category: .modeHint,
                    title: "Region-/Marktparameter (params)",
                    detail: line,
                    evidence: "params.txt Zeile \(idx + 1)",
                    method: "Strukturierte params.txt-Auswertung",
                    verifiability: .confirmed,
                    confirmed: true
                ))
            }
            // Explicit custom-firmware labels in params (not JSON keys)
            if matchesWholeToken(lower, tokens: ["shfw", "cfw", "compat patches", "version spoofing", "scooterhacking"]) {
                out.append(.init(
                    id: "params-cfw-\(idx)",
                    category: .modeHint,
                    title: "Custom-/Compat-Eintrag (params)",
                    detail: line,
                    evidence: "params.txt Zeile \(idx + 1)",
                    method: "Token-Match in params.txt (kein JSON-Schlüssel)",
                    verifiability: .confirmed,
                    confirmed: true
                ))
            }
            if lower.contains("throttle") && lower.contains("brake") {
                out.append(.init(
                    id: "params-gesture-\(idx)",
                    category: .inputHint,
                    title: "Bedienhinweis Gas/Bremse (params)",
                    detail: line,
                    evidence: "params.txt Zeile \(idx + 1)",
                    method: "params.txt-Text",
                    verifiability: .indicative,
                    confirmed: false
                ))
            }
        }
        return out
    }

    private static func scanFirmwareStrings(_ strings: [String], sourcePath: String) -> [FirmwareEvidenceItem] {
        var out: [FirmwareEvidenceItem] = []
        // Blocklist: never treat these alone as CFW (common JSON / metadata vocabulary)
        let blockedExact: Set<String> = [
            "compatible", "model", "models", "firmware", "type", "displayName",
            "schemaVersion", "md5", "encrypted", "encryption"
        ]

        let cfwNeedles = ["SHFW", "ScooterHacking", "German Maneuver", "GermanManeuver", "soft unlock", "softunlock"]
        let limitNeedles = ["Max speed", "EU Max speed", "DE Max speed", "speed limit"]
        let diagNeedles = ["error code", "diag", "UART", "I2C", "CAN"]

        for s in strings {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if blockedExact.contains(trimmed) { continue }
            let lower = trimmed.lowercased()
            // Skip short JSON-looking fragments
            if trimmed.count <= 12 && blockedExact.contains(where: { lower == $0.lowercased() }) { continue }

            for needle in cfwNeedles where lower.contains(needle.lowercased()) {
                out.append(.init(
                    id: "str-cfw-\(needle)-\(trimmed.prefix(12))",
                    category: .modeHint,
                    title: "Custom-FW-String in Image",
                    detail: String(trimmed.prefix(160)),
                    evidence: "\(sourcePath) ASCII-String",
                    method: "String-Extraktion + Token (kein JSON-Key)",
                    verifiability: .indicative,
                    confirmed: false
                ))
                break
            }
            for needle in limitNeedles where lower.contains(needle.lowercased()) {
                out.append(.init(
                    id: "str-lim-\(trimmed.prefix(16))",
                    category: .limitHint,
                    title: "Speed-Limit-String in Image",
                    detail: String(trimmed.prefix(160)),
                    evidence: "\(sourcePath) ASCII-String",
                    method: "String-Extraktion",
                    verifiability: .indicative,
                    confirmed: false
                ))
                break
            }
            for needle in diagNeedles where lower.contains(needle.lowercased()) {
                out.append(.init(
                    id: "str-diag-\(trimmed.prefix(16))",
                    category: .diagnosticsHint,
                    title: "Diagnose-/Bus-String",
                    detail: String(trimmed.prefix(160)),
                    evidence: "\(sourcePath) ASCII-String",
                    method: "String-Extraktion",
                    verifiability: .indicative,
                    confirmed: false
                ))
                break
            }
        }
        return dedupe(out)
    }

    private static func matchesWholeToken(_ lower: String, tokens: [String]) -> Bool {
        tokens.contains { lower.contains($0) }
    }

    private static func extractASCIIStrings(_ data: Data, minLength: Int, limit: Int) -> [String] {
        var out: [String] = []
        var cur = Data()
        for b in data {
            if b >= 32 && b < 127 {
                cur.append(b)
            } else {
                if cur.count >= minLength, let s = String(data: cur, encoding: .ascii) {
                    out.append(s)
                    if out.count >= limit { return out }
                }
                cur.removeAll(keepingCapacity: true)
            }
        }
        if cur.count >= minLength, let s = String(data: cur, encoding: .ascii) {
            out.append(s)
        }
        return out
    }

    private static func dedupe(_ items: [FirmwareEvidenceItem]) -> [FirmwareEvidenceItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func u32(_ data: Data, _ o: Int) -> UInt32 {
        UInt32(data[o]) | (UInt32(data[o + 1]) << 8) | (UInt32(data[o + 2]) << 16) | (UInt32(data[o + 3]) << 24)
    }
}

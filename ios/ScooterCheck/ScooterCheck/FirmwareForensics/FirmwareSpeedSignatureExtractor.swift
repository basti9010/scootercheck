import Foundation

/// Deterministische Extraktion von Speed-/Limit-Signaturen aus Klartext-BIN oder Decompile-C.
/// Keine KI — gleiche Eingabe → gleiches Ergebnis (Qualitätstor für Server/LLM).
enum FirmwareSpeedSignatureExtractor {

    /// Bekannte Ninebot-Packings: High-Byte = km/h, Low-Byte oft 0x00.
    static let knownPackedSpeeds: [(UInt16, Double, FirmwareSpeedLimitRole)] = [
        (0x1400, 20, .legalCap),
        (0x1600, 22, .legalCap),
        (0x1700, 23, .regionOrMode),
        (0x1900, 25, .regionOrMode),
        (0x1E00, 30, .intermediate),
        (0x2000, 32, .intermediate),
        (0x2300, 35, .openCap),
        (0x2319, 35, .openCap), // packed pair seen in other G3 CFW (35/25)
        (0x2800, 40, .openCap),
        (0x2D00, 45, .openCap),
        (0x3200, 50, .openCap),
        (0x6300, 99, .openCap)
    ]

    static func extract(
        fromBinary data: Data?,
        decompiledText: String?,
        subjectSHA256: String,
        meta: FirmwarePackageMeta
    ) -> FirmwareDeepAnalysisResult {
        var findings: [FirmwareSpeedLimitFinding] = []
        var sources: Set<FirmwareDeepAnalysisSource> = []
        var notes: [String] = []

        if let data, !data.isEmpty {
            let fromBin = scanBinary(data)
            if !fromBin.isEmpty {
                sources.insert(.localDeterministic)
                findings.append(contentsOf: fromBin)
                notes.append("Binärscan: \(fromBin.count) Speed-Konstante(n) als LE-u16.")
            } else {
                notes.append("Binärscan: keine bekannten Speed-Packings — Payload evtl. verschlüsselt oder anderer Layout.")
            }
        }

        if let text = decompiledText, !text.isEmpty {
            let fromC = scanDecompiled(text)
            if !fromC.isEmpty {
                sources.insert(.localDeterministic)
                merge(&findings, fromC)
                notes.append("Decompile-Scan: \(fromC.count) Speed-Konstante(n) in Immediate-Zuweisungen.")
            }
        }

        let maxK = findings.map(\.kmh).max()
        let legalCandidates = findings.filter { $0.role == .legalCap }.map(\.kmh)
        let legalK = legalCandidates.min()

        let hasDet = sources.contains(.localDeterministic)
        return FirmwareDeepAnalysisResult(
            schemaVersion: FirmwareDeepAnalysisResult.currentSchemaVersion,
            producedAt: Date(),
            sources: Array(sources).sorted { $0.rawValue < $1.rawValue },
            subjectSHA256: subjectSHA256,
            packageDisplayName: meta.displayName,
            models: meta.models,
            controllerType: meta.type,
            speedLimits: findings.sorted { $0.kmh < $1.kmh },
            maxSpeedKmhInCode: maxK,
            legalCapKmhInCode: legalK,
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: notes,
            caveats: FirmwareDeepAnalysisResult.standardCaveats,
            quality: FirmwareDeepAnalysisQuality(
                hasDeterministicBasis: hasDet,
                llmSchemaValidated: false,
                summary: hasDet
                    ? "Deterministische Speed-Signaturen gefunden."
                    : "Keine deterministischen Speed-Treffer — Katalog oder Server-Decompile nötig."
            )
        )
    }

    // MARK: - Binary

    private static func scanBinary(_ data: Data) -> [FirmwareSpeedLimitFinding] {
        var out: [FirmwareSpeedLimitFinding] = []
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return out }

        var seen = Set<UInt16>()
        for i in 0..<(bytes.count - 1) {
            let lo = UInt16(bytes[i])
            let hi = UInt16(bytes[i + 1])
            let packed = lo | (hi << 8)
            guard let match = knownPackedSpeeds.first(where: { $0.0 == packed }) else { continue }
            guard seen.insert(packed).inserted else { continue }
            out.append(.init(
                id: "bin-\(String(packed, radix: 16))",
                kmh: match.1,
                packedU16: packed,
                role: match.2,
                evidence: String(format: "LE u16 0x%04X @ offset %d", packed, i),
                source: .localDeterministic,
                confidence: .high
            ))
        }
        return out
    }

    // MARK: - Decompile C

    private static func scanDecompiled(_ text: String) -> [FirmwareSpeedLimitFinding] {
        var out: [FirmwareSpeedLimitFinding] = []
        var seen = Set<UInt16>()
        // Match hex immediates like 0x1600 / 0x6300 in assignments
        let pattern = #"0x([0-9a-fA-F]{3,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return out }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: text),
                  let packed = UInt16(text[r], radix: 16),
                  let known = knownPackedSpeeds.first(where: { $0.0 == packed }),
                  seen.insert(packed).inserted
            else { return }
            out.append(.init(
                id: "c-\(String(packed, radix: 16))",
                kmh: known.1,
                packedU16: packed,
                role: known.2,
                evidence: "Decompile-Immediate 0x\(String(packed, radix: 16))",
                source: .localDeterministic,
                confidence: .high
            ))
        }
        return out
    }

    private static func merge(_ into: inout [FirmwareSpeedLimitFinding], _ extra: [FirmwareSpeedLimitFinding]) {
        var have = Set(into.compactMap(\.packedU16))
        for f in extra {
            if let p = f.packedU16 {
                if have.insert(p).inserted { into.append(f) }
            } else {
                into.append(f)
            }
        }
    }
}

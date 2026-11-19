import Foundation
import UIKit

enum FirmwareForensicPDF {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48
    private static let contentWidth: CGFloat = pageRect.width - 2 * margin

    static func render(_ report: FirmwareForensicReport) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            var y = beginPage(ctx)
            y = drawTitle(ctx, y: y)
            y = line(ctx, "Untersuchung: \(formatDate(report.analyzedAt))", y: y)
            y = line(ctx, "Originaldatei: \(report.originalFileName)", y: y)
            y = line(ctx, "Archivgröße: \(report.archiveByteCount) Byte", y: y)
            y = line(ctx, "SHA-256 (Archiv): \(report.archiveDigest.sha256)", y: y)
            y = line(ctx, "MD5 (Archiv): \(report.archiveDigest.md5)", y: y)
            y = gap(y)

            // --- Layperson first ---
            y = heading(ctx, "Kurzfassung (verständlich)", y: y)
            y = line(ctx, report.verdict.label, y: y, bold: true)
            y = line(ctx, report.verdictRationale, y: y, size: 9)
            y = line(ctx, report.summary, y: y, size: 9)
            y = gap(y)

            if let deep = report.deepAnalysis {
                let brief = FirmwareDeepAnalysisBriefing.build(from: deep)
                y = heading(ctx, "Server-Entschlüsselung / Deep Analysis", y: y)
                y = line(ctx, brief.headline, y: y, bold: true)
                for b in brief.bullets {
                    y = ensure(ctx, y: y, need: 28)
                    y = line(ctx, "• \(b)", y: y, size: 9)
                }
                if let legal = deep.legalCapKmhInCode, let maxK = deep.maxSpeedKmhInCode {
                    y = line(ctx, "Legal-nah ~\(Int(legal)) km/h → offen bis ~\(Int(maxK)) km/h", y: y, size: 10, bold: true)
                }
                if !brief.actionableCombos.isEmpty {
                    y = gap(y)
                    y = line(ctx, "Validierte Tastenfolge:", y: y, size: 10, bold: true)
                    for c in brief.actionableCombos {
                        y = ensure(ctx, y: y, need: 24)
                        y = line(ctx, "• \(c)", y: y, size: 9)
                    }
                }
                if !deep.speedLimits.isEmpty {
                    y = gap(y)
                    y = line(ctx, "Speed-Stufen im Klartext:", y: y, size: 10, bold: true)
                    for s in deep.speedLimits.prefix(16) {
                        y = ensure(ctx, y: y, need: 20)
                        y = line(ctx, "• \(Int(s.kmh)) km/h — \(s.role.label)", y: y, size: 9)
                    }
                }
                if let stock = deep.stockDiff {
                    y = gap(y)
                    y = line(ctx, "Stock-Diff: \(stock.outcome.label)", y: y, size: 10, bold: true)
                    y = line(ctx, stock.note, y: y, size: 9)
                }
                if !deep.yaraMatches.isEmpty {
                    y = gap(y)
                    y = line(ctx, "YARA-Hinweise:", y: y, size: 10, bold: true)
                    for m in deep.yaraMatches.prefix(12) {
                        y = ensure(ctx, y: y, need: 22)
                        y = line(ctx, "• \(m.rule): \(m.description)", y: y, size: 8)
                    }
                }
                y = gap(y)
            }

            if let art = report.serverArtifacts {
                y = heading(ctx, "Entschlüsselte Server-Daten", y: y)
                if let job = art.jobId, !job.isEmpty {
                    y = line(ctx, "Job-ID: \(job)", y: y, size: 9)
                }
                if art.plaintextSaved == true {
                    y = line(ctx, "Klartext: ja (vom Server entschlüsselt)", y: y, size: 9)
                    if let n = art.plaintextByteCount {
                        y = line(ctx, "Klartext-Größe: \(n) Byte", y: y, size: 9)
                    }
                    if let sha = art.plaintextSHA256, !sha.isEmpty {
                        y = line(ctx, "SHA-256 (Klartext): \(sha)", y: y, size: 8)
                    }
                    y = line(
                        ctx,
                        "Der entschlüsselte Klartext liegt diesem Export als .dec.bin bei (sofern mitgeteilt).",
                        y: y,
                        size: 8
                    )
                } else {
                    y = line(ctx, "Kein Klartext vom Server gespeichert.", y: y, size: 9)
                }
                if art.decompileSaved == true {
                    y = line(ctx, "Ghidra-Decompile: vorhanden", y: y, size: 9)
                }
                if let excerpt = art.decompileExcerpt, !excerpt.isEmpty {
                    y = gap(y)
                    y = line(ctx, "Decompile-Auszug:", y: y, size: 10, bold: true)
                    let trimmed = String(excerpt.prefix(3500))
                    for chunk in trimmed.split(separator: "\n", omittingEmptySubsequences: false).prefix(80) {
                        y = ensure(ctx, y: y, need: 14)
                        y = line(ctx, String(chunk), y: y, size: 7)
                    }
                }
                y = gap(y)
            }

            y = heading(ctx, "Paketmetadaten (Offline)", y: y)
            y = line(ctx, "Format: \(formatKind(report.containerKind))", y: y)
            y = line(ctx, "Name: \(report.meta.displayName ?? "—")", y: y)
            y = line(ctx, "Modelle: \(report.meta.models.joined(separator: ", ").nilIfEmpty ?? "—")", y: y)
            y = line(ctx, "Steuergerät: \(report.meta.type ?? "—")", y: y)
            y = gap(y)

            y = heading(ctx, "Archivinhalt", y: y)
            for e in report.entries {
                y = ensure(ctx, y: y, need: 36)
                y = line(ctx, "• \(e.path) — \(e.digest.byteCount) B — \(e.analysisStatus)", y: y)
                y = line(ctx, "  SHA-256: \(e.digest.sha256)", y: y, size: 9)
            }
            y = gap(y)

            y = heading(ctx, "Verschlüsselung (Offline-Einschätzung)", y: y)
            y = line(ctx, report.crypto.status.label, y: y)
            y = line(ctx, "Format: \(report.crypto.detectedFormat)", y: y)
            y = line(ctx, "Entschlüsselung: \(report.crypto.decryptionAvailable ? "lokal verfügbar" : "nur per Server / nicht lokal")", y: y)
            y = line(ctx, report.crypto.decryptionNote, y: y, size: 9)
            y = gap(y)

            y = heading(ctx, "Technische Befunde (Offline)", y: y)
            for item in report.evidence {
                y = ensure(ctx, y: y, need: 52)
                y = line(ctx, "[\(item.verifiability.label)] \(item.title)", y: y)
                y = line(ctx, item.detail, y: y, size: 9)
                y = line(ctx, "Beleg: \(item.evidence) · Methode: \(item.method)", y: y, size: 8)
            }
            y = gap(y)

            if let cmp = report.comparison {
                y = heading(ctx, "Referenzvergleich (lokal)", y: y)
                y = line(ctx, cmp.outcome.label, y: y)
                y = line(ctx, cmp.note, y: y, size: 9)
                y = gap(y)
            }

            y = drawTechnicalProvenanceSection(ctx, report: report, y: y)

            y = heading(ctx, "Grenzen der Untersuchung", y: y)
            for lim in report.limits {
                y = ensure(ctx, y: y, need: 28)
                y = line(ctx, "• \(lim)", y: y, size: 9)
            }
            y = gap(y)
            y = line(
                ctx,
                "ScooterCheck Firmware-Forensik — nur lesend. Codebefunde beweisen nicht die Installation am Fahrzeug. Der Bericht trifft keine stärkere Aussage als die zugrunde liegenden technischen Ergebnisse.",
                y: y,
                size: 8
            )
            _ = y
        }
    }

    /// Abschnitt „Technische Analyse und Nachweisführung“.
    private static func drawTechnicalProvenanceSection(
        _ ctx: UIGraphicsPDFRendererContext,
        report: FirmwareForensicReport,
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "Technische Analyse und Nachweisführung", y: y)
        y = line(ctx, "SHA-256 Originaldatei: \(report.archiveDigest.sha256)", y: y, size: 8)
        if let plain = report.serverArtifacts?.plaintextSHA256, !plain.isEmpty {
            y = line(ctx, "SHA-256 entschlüsselte Firmware: \(plain)", y: y, size: 8)
        } else {
            y = line(ctx, "SHA-256 entschlüsselte Firmware: — (nicht vorhanden / nicht entschlüsselt)", y: y, size: 8)
        }
        y = line(ctx, "Firmwaretyp: \(report.meta.type ?? "—") · Format: \(formatKind(report.containerKind))", y: y, size: 9)
        y = line(
            ctx,
            "Modellzuordnung: \(report.meta.models.joined(separator: ", ").nilIfEmpty ?? "—")",
            y: y,
            size: 9
        )
        if let job = report.serverArtifacts?.jobId, !job.isEmpty {
            y = line(ctx, "Server-Job-ID: \(job)", y: y, size: 9)
        } else {
            y = line(ctx, "Server-Job-ID: — (nur Offline oder noch kein Server-Lauf)", y: y, size: 9)
        }
        y = line(ctx, "Analysezeitpunkt: \(formatDate(report.analyzedAt))", y: y, size: 9)

        if let deep = report.deepAnalysis {
            let tools = deep.sources.map(\.label).joined(separator: ", ")
            y = line(ctx, "Werkzeuge/Quellen: \(tools.isEmpty ? "—" : tools)", y: y, size: 8)
            if let stock = deep.stockDiff {
                let trust = FirmwareEvidenceClassifier.referenceTrust(for: stock)
                y = line(
                    ctx,
                    "Referenzfirmware: \(stock.referenceLabel ?? "—") · Outcome \(stock.outcome.label)",
                    y: y,
                    size: 8
                )
                y = line(
                    ctx,
                    "Referenz-Herkunft/Vertrauen: source=\(stock.referenceSource ?? "—") · \(trust.label)"
                        + (stock.referenceProvenanceVerified == true ? " · Provenance verifiziert" : " · Provenance nicht bestätigt"),
                    y: y,
                    size: 8
                )
            } else {
                y = line(ctx, "Referenzfirmware: keine Stock-Diff-Daten", y: y, size: 8)
            }

            y = gap(y)
            y = line(ctx, "Status Analyseschritte:", y: y, size: 9, bold: true)
            let steps: [(String, Bool)] = [
                ("Stock-Diff", deep.stockDiff != nil),
                ("YARA", !deep.yaraMatches.isEmpty),
                ("IVT", deep.cortexMIvt != nil),
                ("Pinout", deep.boardPinout != nil),
                ("Speed-Signaturen", !deep.speedLimits.isEmpty),
                ("Function Matching", deep.functionMatching != nil || deep.functionDiff != nil),
                ("Input Behavior", deep.inputBehaviorAnalysis != nil),
                ("Emulation/Angr", deep.sources.contains(.serverEmulation) || deep.sources.contains(.serverAngr)),
                ("KI", deep.sources.contains(.serverLLM)),
            ]
            for (name, ok) in steps {
                y = ensure(ctx, y: y, need: 16)
                y = line(ctx, "• \(name): \(ok ? "Daten vorhanden" : "nicht vorhanden / nicht gelaufen")", y: y, size: 8)
            }

            // Phase 2.2C: Funktionszuordnung
            if let fd = deep.functionDiff, let sum = fd.summary {
                y = gap(y)
                y = line(ctx, "Funktionszuordnung (strukturell, kein Manipulationsnachweis):", y: y, size: 9, bold: true)
                y = line(ctx, "Methode: \(fd.toolNote ?? fd.tool ?? "multi-stage matcher")", y: y, size: 8)
                y = line(
                    ctx,
                    "Zugeordnet=\(sum.matched ?? 0) · Identisch=\(sum.identical ?? 0) · Verändert=\(sum.structurallyChanged ?? 0) · "
                        + "Hinzu=\(sum.added ?? 0) · Entfernt=\(sum.removed ?? 0) · Mehrdeutig=\(sum.ambiguous ?? 0)",
                    y: y,
                    size: 8
                )
                if let high = sum.matchHigh, let med = sum.matchMedium, let low = sum.matchLow {
                    y = line(ctx, "Matching-Konfidenz HIGH/MEDIUM/LOW: \(high)/\(med)/\(low)", y: y, size: 8)
                }
                for lim in (fd.analysisLimitations ?? []).prefix(4) {
                    y = ensure(ctx, y: y, need: 16)
                    y = line(ctx, "• \(lim)", y: y, size: 7)
                }
            }

            // Phase 2.2C: Eingabeverarbeitung
            if let ib = deep.inputBehaviorAnalysis {
                y = gap(y)
                y = line(ctx, "Eingabeverarbeitung (heuristisch):", y: y, size: 9, bold: true)
                y = line(
                    ctx,
                    "Relevante Funktionen=\(ib.summary?.inputRelevantCount ?? 0) · Evidenzstufe=\(ib.evidenceTier ?? "—")",
                    y: y,
                    size: 8
                )
                if let cats = ib.categories, !cats.isEmpty {
                    let label = cats.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ", ")
                    y = line(ctx, "Kategorien: \(label)", y: y, size: 8)
                }
                let sm = deep.stateMachineAnalysis ?? ib.stateMachineAnalysis
                if let sm {
                    let statesLabel: String = {
                        if let n = sm.totalEstimatedStates { return "Zustände(verifiziert)=\(n)" }
                        return "Zustände=nicht verifiziert"
                    }()
                    let transLabel: String = {
                        if let n = sm.totalEstimatedTransitions { return "Übergänge(verifiziert)=\(n)" }
                        return "Übergänge=nicht verifiziert"
                    }()
                    y = line(
                        ctx,
                        "FSM-Kandidaten=\(sm.stateMachineCount ?? 0) · \(statesLabel) · \(transLabel)",
                        y: y,
                        size: 8
                    )
                    y = line(
                        ctx,
                        "Hinweis: Basic Blocks ≠ Zustände. Keine Aktivierungsfolgen.",
                        y: y,
                        size: 7
                    )
                }
                if let diff = deep.inputBehaviorDiff?.summary {
                    y = line(
                        ctx,
                        "Input-Diff vs Referenz: identisch=\(diff.identical ?? 0) verändert=\(diff.structurallyChanged ?? 0) hinzu=\(diff.added ?? 0) entfernt=\(diff.removed ?? 0)",
                        y: y,
                        size: 8
                    )
                }
                for lim in (ib.analysisLimitations ?? []).prefix(4) {
                    y = ensure(ctx, y: y, need: 16)
                    y = line(ctx, "• \(lim)", y: y, size: 7)
                }
            }

            let findings = deep.classifiedFindings
                ?? FirmwareEvidenceClassifier.classify(from: deep, fileName: report.originalFileName)
            if !findings.isEmpty {
                y = gap(y)
                y = line(ctx, "Evidenzstufen der wichtigsten Erkenntnisse:", y: y, size: 9, bold: true)
                let proven = findings.filter { $0.tier == .statisch || $0.tier == .live }
                let hints = findings.filter { $0.tier == .muster || $0.tier == .emuliert }
                let guesses = findings.filter { $0.tier == .nichtVerifiziert }
                y = line(ctx, "1) Technisch nachgewiesene Eigenschaften (STATISCH/LIVE):", y: y, size: 8, bold: true)
                if proven.isEmpty {
                    y = line(ctx, "   — keine", y: y, size: 8)
                } else {
                    for f in proven.prefix(8) {
                        y = ensure(ctx, y: y, need: 28)
                        y = line(ctx, "   [\(f.tier.label)] \(f.detail)", y: y, size: 7)
                        y = line(ctx, "   Einschränkung: \(f.limitations)", y: y, size: 7)
                    }
                }
                y = line(ctx, "2) Auffälligkeiten und Indizien (MUSTER/EMULIERT):", y: y, size: 8, bold: true)
                if hints.isEmpty {
                    y = line(ctx, "   — keine", y: y, size: 8)
                } else {
                    for f in hints.prefix(8) {
                        y = ensure(ctx, y: y, need: 28)
                        y = line(ctx, "   [\(f.tier.label)] \(f.detail)", y: y, size: 7)
                        y = line(ctx, "   Einschränkung: \(f.limitations)", y: y, size: 7)
                    }
                }
                y = line(ctx, "3) Nicht bestätigte Vermutungen (NICHT_VERIFIZIERT):", y: y, size: 8, bold: true)
                if guesses.isEmpty {
                    y = line(ctx, "   — keine", y: y, size: 8)
                } else {
                    for f in guesses.prefix(6) {
                        y = ensure(ctx, y: y, need: 28)
                        y = line(ctx, "   [\(f.tier.label)] \(f.detail)", y: y, size: 7)
                    }
                }
            }
        } else {
            y = line(ctx, "Keine Deep-Analysis-Daten — nur Offline-Befunde.", y: y, size: 9)
        }

        y = gap(y)
        y = line(ctx, "Grenzen der technischen Untersuchung (Nachweisführung):", y: y, size: 9, bold: true)
        let provenanceLimits = [
            "Byte-/SHA-Identität belegt keine Installation am Fahrzeug.",
            "YARA-, Capstone- und kurze Unicorn-Läufe sind keine Live-Fahrzeugbeobachtung.",
            "Community-Referenzen mit source=oem sind ohne Provenance-Flag nicht herstellerseitig bestätigt.",
            "Byte-Diff allein begründet keine ROT-Ampel.",
        ]
        for lim in provenanceLimits {
            y = ensure(ctx, y: y, need: 22)
            y = line(ctx, "• \(lim)", y: y, size: 8)
        }
        return gap(y)
    }

    static func jsonData(_ report: FirmwareForensicReport) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(report)
    }

    private static func beginPage(_ ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        ctx.beginPage()
        return margin
    }

    private static func ensure(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat, need: CGFloat) -> CGFloat {
        if y + need > pageRect.height - margin {
            ctx.beginPage()
            return margin
        }
        return y
    }

    private static func drawTitle(_ ctx: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = y
        cursor = line(ctx, "ScooterCheck", y: cursor, size: 20, bold: true)
        cursor = line(ctx, "Firmware-Forensikbericht (Read-Only)", y: cursor, size: 12)
        return cursor + 8
    }

    private static func heading(_ ctx: UIGraphicsPDFRendererContext, _ text: String, y: CGFloat) -> CGFloat {
        let yy = ensure(ctx, y: y, need: 24)
        return line(ctx, text, y: yy, size: 13, bold: true) + 4
    }

    private static func gap(_ y: CGFloat) -> CGFloat { y + 10 }

    @discardableResult
    private static func line(
        _ ctx: UIGraphicsPDFRendererContext,
        _ text: String,
        y: CGFloat,
        size: CGFloat = 10,
        bold: Bool = false
    ) -> CGFloat {
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 200)
        let ns = text as NSString
        let bounds = ns.boundingRect(
            with: CGSize(width: contentWidth, height: 200),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        ns.draw(in: rect, withAttributes: attrs)
        return y + ceil(bounds.height) + 3
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "dd.MM.yyyy HH:mm:ss zzz"
        return f.string(from: date)
    }

    private static func formatKind(_ k: FirmwareContainerKind) -> String {
        switch k {
        case .zipV3: return "ScooterHacking ZIPv3"
        case .zipGeneric: return "ZIP (allgemein)"
        case .bareBinary: return "BIN"
        case .bareEncryptedBinary: return "BIN.ENC"
        case .json: return "JSON"
        case .text: return "TXT"
        case .unknown: return "Unbekannt"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

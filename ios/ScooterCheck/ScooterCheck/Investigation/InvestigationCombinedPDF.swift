import Foundation
import UIKit

/// Vollständiger kombinierter Untersuchungsbericht (Scooter + Firmwaredateien).
enum InvestigationCombinedPDF {
    private static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48
    private static let contentWidth: CGFloat = pageRect.width - 2 * margin

    static func render(
        record: InvestigationRecord,
        reports: [(InvestigationFirmwareRef, FirmwareForensicReport)],
        dualSource: DualSourcePanicAssessment? = nil
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "ScooterCheck Untersuchungsbericht",
            kCGPDFContextSubject as String: "investigation=\(record.id) kind=\(record.kind.rawValue)",
            kCGPDFContextKeywords as String: "combined,investigation,\(record.kind.rawValue)"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            var y = beginPage(ctx)
            y = drawTitle(ctx, y: y)
            y = section1(ctx, record: record, y: y)
            y = section2(ctx, readout: record.readout, y: y)
            y = section3(ctx, readout: record.readout, y: y)
            y = section4(ctx, refs: record.firmwareRefs, y: y)
            y = section5(ctx, reports: reports, y: y)
            y = section6(ctx, record: record, reports: reports, y: y)
            y = section7(ctx, record: record, dualSource: dualSource, reports: reports, y: y)
            y = section8(ctx, record: record, reports: reports, y: y)
            _ = y
        }
    }

    // MARK: - Sections

    private static func section1(
        _ ctx: UIGraphicsPDFRendererContext,
        record: InvestigationRecord,
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "1. Allgemeine Untersuchungsdaten", y: y)
        y = line(ctx, "Untersuchungs-ID: \(record.id)", y: y, size: 9)
        y = line(ctx, "Erstellt: \(formatDate(record.createdAt))", y: y, size: 9)
        y = line(ctx, "Zuletzt aktualisiert: \(formatDate(record.updatedAt))", y: y, size: 9)
        y = line(ctx, "Untersuchungsart: \(record.kind.label) (\(record.kind.rawValue))", y: y, size: 9)
        y = line(ctx, "Fortschritt: \(record.reconciledProgress.title)", y: y, size: 9)
        y = line(ctx, "App-Version: \(ProtocolPDF.appVersion)", y: y, size: 9)
        y = line(ctx, "Bericht erstellt: \(formatDate(Date()))", y: y, size: 9)
        if record.comparisonStale {
            y = line(ctx, "Hinweis: Vergleichsergebnisse als veraltet markiert (Scooter-Wechsel).", y: y, size: 9, bold: true)
        }
        return gap(y)
    }

    private static func section2(
        _ ctx: UIGraphicsPDFRendererContext,
        readout: InvestigationReadoutSummary?,
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "2. E-Scooter-Identifikation", y: y)
        guard let r = readout else {
            y = line(ctx, "Keine Scooter-Auslesung in dieser Untersuchung.", y: y, size: 9)
            return gap(y)
        }
        y = kv(ctx, "Hersteller", r.manufacturer ?? "—", y: y)
        y = kv(ctx, "Modell", r.modelLabel, y: y)
        y = kv(ctx, "BLE-Gerätename", r.bleAdvertisementName ?? "—", y: y)
        y = kv(ctx, "Seriennummer", r.serial ?? "—", y: y)
        y = kv(ctx, "Hardwareversion", r.hardwareVersion ?? "—", y: y)
        y = kv(ctx, "Controllerkennung", r.controllerHint ?? "—", y: y)
        y = kv(ctx, "VCU", r.fwVcu ?? "—", y: y)
        y = kv(ctx, "MCU", r.fwMcu ?? "—", y: y)
        y = kv(ctx, "BLE-FW", r.fwBle ?? "—", y: y)
        y = kv(ctx, "ESC", r.fwEsc ?? "—", y: y)
        if let lim = r.speedLimitKmh {
            y = kv(ctx, "Speed-Limit (Auslese)", String(format: "%.0f km/h", lim), y: y)
        }
        if let pn = r.protocolNumber {
            y = kv(ctx, "Prüfungsnummer", pn, y: y)
        }
        return gap(y)
    }

    private static func section3(
        _ ctx: UIGraphicsPDFRendererContext,
        readout: InvestigationReadoutSummary?,
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "3. BLE-Auslesung", y: y)
        guard let r = readout else {
            y = line(ctx, "Nicht verfügbar — reine Firmwareuntersuchung oder Auslesung ausstehend.", y: y, size: 9)
            return gap(y)
        }
        y = line(ctx, "Herkunft: Live-/gespeicherte Scooter-Auslesung (CoreBluetooth, Read-Only).", y: y, size: 9)
        y = line(ctx, "Auslesezeitpunkt: \(formatDate(r.savedAt))", y: y, size: 9)
        if let pid = r.blePeripheralId {
            y = line(ctx, "BLE-Peripheral-ID: \(pid.uuidString)", y: y, size: 8)
        }
        let fields: [(String, String?)] = [
            ("Seriennummer", r.serial),
            ("VCU", r.fwVcu),
            ("MCU", r.fwMcu),
            ("BLE", r.fwBle),
            ("ESC", r.fwEsc)
        ]
        for (name, value) in fields {
            if let value, !value.isEmpty {
                y = line(ctx, "• \(name): \(value) (erfolgreich)", y: y, size: 9)
            } else {
                y = line(ctx, "• \(name): nicht verfügbar", y: y, size: 9)
            }
        }
        y = line(
            ctx,
            "Technische Einschränkung: Nur lesende Registerzugriffe — keine Fahrzeugkonfiguration verändert.",
            y: y,
            size: 8
        )
        return gap(y)
    }

    private static func section4(
        _ ctx: UIGraphicsPDFRendererContext,
        refs: [InvestigationFirmwareRef],
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "4. Firmwaredateien", y: y)
        if refs.isEmpty {
            y = line(ctx, "Keine Firmwaredatei zugeordnet.", y: y, size: 9)
            return gap(y)
        }
        for (idx, ref) in refs.enumerated() {
            y = ensure(ctx, y: y, need: 90)
            y = line(ctx, "Datei \(idx + 1): \(ref.originalFileName)", y: y, size: 10, bold: true)
            y = kv(ctx, "Format", ref.containerKind ?? "—", y: y)
            y = kv(ctx, "Größe", ref.byteCount.map { "\($0) Byte" } ?? "—", y: y)
            y = monoLine(ctx, "SHA-256: \(ref.subjectSHA256 ?? "—")", y: y, size: 7)
            y = kv(ctx, "Import", formatDate(ref.addedAt), y: y)
            y = kv(ctx, "Analyse", ref.analyzedAt.map(formatDate) ?? "—", y: y)
            y = kv(ctx, "Server-Job-ID", ref.serverJobId ?? "—", y: y)
            y = kv(ctx, "Analyseprofil", ref.packageDisplayName ?? "—", y: y)
            y = kv(ctx, "Referenzvertrauen", ref.referenceTrust ?? "—", y: y)
            y = kv(ctx, "Archivstatus", ref.archiveStatus ?? "—", y: y)
            if let err = ref.archiveError, !err.isEmpty {
                y = line(ctx, "Archivfehler: \(err)", y: y, size: 8)
            }
            y = gap(y)
        }
        return y
    }

    private static func section5(
        _ ctx: UIGraphicsPDFRendererContext,
        reports: [(InvestigationFirmwareRef, FirmwareForensicReport)],
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "5. Firmwareanalyse", y: y)
        if reports.isEmpty {
            y = line(ctx, "Keine gespeicherten Firmwareanalyse-Ergebnisse.", y: y, size: 9)
            return gap(y)
        }
        for (ref, report) in reports {
            y = ensure(ctx, y: y, need: 80)
            y = line(ctx, report.originalFileName, y: y, size: 10, bold: true)
            y = line(ctx, "Urteil: \(report.verdict.label)", y: y, size: 9)
            y = line(ctx, report.summary, y: y, size: 8)
            if let deep = report.deepAnalysis {
                y = line(ctx, "Vollständigkeit: \(deep.analysisCompleteness ?? "—")", y: y, size: 8)
                if let maxK = deep.maxSpeedKmhInCode {
                    y = line(ctx, "Geschwindigkeitsindikator (Code): ~\(Int(maxK)) km/h", y: y, size: 8)
                }
                if !deep.comboSummaries.isEmpty {
                    y = line(ctx, "Combo-/Aktivierungshinweise: \(deep.comboSummaries.count)", y: y, size: 8)
                }
                if let stock = deep.stockDiff {
                    y = line(ctx, "Stock-Diff: \(stock.outcome.label)", y: y, size: 8)
                }
            }
            if let job = report.serverArtifacts?.jobId {
                y = line(ctx, "Ghidra/Server-Job: \(job)", y: y, size: 8)
            }
            if report.serverArtifacts?.decompileSaved == true {
                y = line(ctx, "Ghidra-Decompile: vorhanden (Artefaktreferenz)", y: y, size: 8)
            }
            let topEvidence = report.evidence.prefix(8)
            for item in topEvidence {
                y = ensure(ctx, y: y, need: 28)
                y = line(ctx, "• [\(item.verifiability.rawValue)] \(item.title)", y: y, size: 8)
            }
            if let completeness = ref.analysisCompleteness {
                y = line(ctx, "Analysevollständigkeit (Ref): \(completeness)", y: y, size: 8)
            }
            y = gap(y)
        }
        return y
    }

    private static func section6(
        _ ctx: UIGraphicsPDFRendererContext,
        record: InvestigationRecord,
        reports: [(InvestigationFirmwareRef, FirmwareForensicReport)],
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "6. Gemeinsamer Vergleich", y: y)
        guard let readout = record.readout else {
            y = line(ctx, "Nicht überprüfbar — keine Scooter-Auslesung.", y: y, size: 9)
            return gap(y)
        }
        if reports.isEmpty {
            y = line(ctx, "Nicht überprüfbar — keine Firmwareanalyse.", y: y, size: 9)
            return gap(y)
        }
        if record.comparisonStale {
            y = line(ctx, "Vergleich möglicherweise veraltet (Scooter-Zuordnung geändert).", y: y, size: 9, bold: true)
        }
        let vehicle = FirmwareVehicleContext(
            manufacturer: readout.manufacturer ?? "Segway-Ninebot / Xiaomi",
            modelLabel: readout.modelLabel,
            profileId: readout.profileId,
            serial: readout.serial,
            fwVcu: readout.fwVcu,
            fwMcu: readout.fwMcu,
            fwBle: readout.fwBle,
            fwEsc: readout.fwEsc,
            speedLimitKmh: readout.speedLimitKmh,
            speedMaxKmh: nil,
            peakSpeedKmh: nil,
            protocolNumber: readout.protocolNumber,
            fromLiveReadout: true
        )
        for (_, report) in reports {
            let match = FirmwareReadoutMatchCorrelator.assess(report: report, vehicleContext: vehicle)
            y = ensure(ctx, y: y, need: 60)
            y = line(ctx, "\(report.originalFileName): \(match.verdict.title)", y: y, size: 9, bold: true)
            y = line(ctx, match.summary, y: y, size: 8)
            for check in match.checks {
                let status: String
                switch check.status {
                case .match: status = "Übereinstimmung"
                case .mismatch: status = "Abweichung"
                case .unclear: status = "Nicht überprüfbar"
                case .missing: status = "Nicht überprüfbar"
                }
                y = ensure(ctx, y: y, need: 22)
                y = line(ctx, "• \(check.title): \(status) — \(check.detail)", y: y, size: 8)
            }
            y = gap(y)
        }
        y = line(
            ctx,
            "Eine kompatible Firmwaredatei beweist nicht, dass sie tatsächlich auf dem Scooter installiert ist.",
            y: y,
            size: 8,
            bold: true
        )
        return gap(y)
    }

    private static func section7(
        _ ctx: UIGraphicsPDFRendererContext,
        record: InvestigationRecord,
        dualSource: DualSourcePanicAssessment?,
        reports: [(InvestigationFirmwareRef, FirmwareForensicReport)],
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "7. Technische Gesamtbewertung", y: y)
        y = line(ctx, "Untersuchungsart: \(record.kind.label)", y: y, size: 9)
        if let dual = dualSource, dual.pattern != .insufficient {
            y = line(ctx, "Dual-Source-Muster: \(dual.pattern.title)", y: y, size: 9, bold: true)
            y = line(ctx, dual.correlationSummary, y: y, size: 8)
        }
        if let first = reports.first?.1 {
            y = line(ctx, "Firmware-Urteil (erste Datei): \(first.verdict.label)", y: y, size: 9)
            y = line(ctx, first.verdictRationale, y: y, size: 8)
        }
        y = line(
            ctx,
            "Keine unbelegte Manipulationsbehauptung. Nur dokumentierte Mess-/Analysebefunde.",
            y: y,
            size: 8
        )
        y = line(
            ctx,
            "Importierte Firmwaredatei ≠ nachgewiesene installierte Fahrzeugfirmware.",
            y: y,
            size: 8,
            bold: true
        )
        return gap(y)
    }

    private static func section8(
        _ ctx: UIGraphicsPDFRendererContext,
        record: InvestigationRecord,
        reports: [(InvestigationFirmwareRef, FirmwareForensicReport)],
        y: CGFloat
    ) -> CGFloat {
        var y = heading(ctx, "8. Technische Einschränkungen", y: y)
        var limits: [String] = []
        if record.readout == nil {
            limits.append("Fehlende BLE-Auslesedaten.")
        }
        if record.firmwareRefs.isEmpty {
            limits.append("Keine Firmwaredatei zugeordnet.")
        }
        for ref in record.firmwareRefs {
            if ref.archiveStatus != "ok" {
                limits.append("Firmware „\(ref.originalFileName)“: Archivierung \(ref.archiveStatus ?? "unbekannt")\(ref.archiveError.map { " — \($0)" } ?? "").")
            }
            if ref.serverJobId == nil {
                limits.append("Keine Server-Job-ID für „\(ref.originalFileName)“ — Serveranalyse ggf. nicht verfügbar.")
            }
            if let c = ref.analysisCompleteness, c.uppercased().contains("PARTIAL") {
                limits.append("Analyse von „\(ref.originalFileName)“ nur teilweise vollständig (\(c)).")
            }
        }
        for (_, report) in reports {
            if report.deepAnalysis == nil {
                limits.append("Keine Deep-/Serveranalyse für \(report.originalFileName).")
            }
            if let caveats = report.deepAnalysis?.caveats {
                limits.append(contentsOf: caveats.prefix(4))
            }
        }
        limits.append("Nicht überprüfbare Eigenschaften dürfen nicht als bestätigte Auffälligkeiten gelten.")
        limits.append("Byte-/SHA-Identität belegt keine Installation am Fahrzeug.")
        if limits.isEmpty {
            y = line(ctx, "Keine zusätzlichen Einschränkungen dokumentiert.", y: y, size: 9)
        } else {
            for lim in limits {
                y = ensure(ctx, y: y, need: 24)
                y = line(ctx, "• \(lim)", y: y, size: 8)
            }
        }
        return gap(y)
    }

    // MARK: - Drawing helpers (aligned with FirmwareForensicPDF)

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
        cursor = line(ctx, "Gesamter Untersuchungsbericht (Read-Only)", y: cursor, size: 12)
        return cursor + 8
    }

    private static func heading(_ ctx: UIGraphicsPDFRendererContext, _ text: String, y: CGFloat) -> CGFloat {
        let yy = ensure(ctx, y: y, need: 28)
        return line(ctx, text, y: yy, size: 13, bold: true) + 4
    }

    private static func gap(_ y: CGFloat) -> CGFloat { y + 10 }

    private static func kv(
        _ ctx: UIGraphicsPDFRendererContext,
        _ key: String,
        _ value: String,
        y: CGFloat
    ) -> CGFloat {
        line(ctx, "\(key): \(value)", y: y, size: 9)
    }

    @discardableResult
    private static func line(
        _ ctx: UIGraphicsPDFRendererContext,
        _ text: String,
        y: CGFloat,
        size: CGFloat = 10,
        bold: Bool = false
    ) -> CGFloat {
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        return drawText(ctx, text, y: y, font: font)
    }

    @discardableResult
    private static func monoLine(
        _ ctx: UIGraphicsPDFRendererContext,
        _ text: String,
        y: CGFloat,
        size: CGFloat = 7
    ) -> CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return drawText(ctx, text, y: y, font: font)
    }

    private static func drawText(
        _ ctx: UIGraphicsPDFRendererContext,
        _ text: String,
        y: CGFloat,
        font: UIFont
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 220)
        let ns = text as NSString
        let bounds = ns.boundingRect(
            with: CGSize(width: contentWidth, height: 220),
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
}

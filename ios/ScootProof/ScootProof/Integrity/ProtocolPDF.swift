import Foundation
import UIKit
import SwiftUI

// MARK: - Protocol JSON

enum ProtocolJSON {

    static func makeJSON(session: CheckSession, result: IntegrityResult) throws -> Data {
        let payload = ProtocolPayload(
            app: ProtocolPayload.AppInfo(
                name: "ScooterCheck",
                version: ProtocolPDF.appVersion,
                bundleId: Bundle.main.bundleIdentifier ?? "com.scootercheck.app"
            ),
            protocolNumber: session.protocolNumber,
            createdAt: ISO8601DateFormatter().string(from: session.createdAt),
            analyzedAt: ISO8601DateFormatter().string(from: result.analyzedAt),
            profile: result.profile.rawValue,
            profileLabel: result.profile.label,
            score: result.score,
            verdict: result.verdict.rawValue,
            verdictLabel: result.verdict.label,
            shortVerdict: result.evidence.shortVerdictText,
            justifyingMarkers: result.evidence.justifyingMarkers,
            decisiveEvidence: result.evidence.decisiveEvidence,
            evidenceCatalogVersion: result.evidence.catalogVersion,
            attribution: result.evidence.attribution,
            trackId: result.trackMatch.trackId.rawValue,
            trackConfidence: result.trackMatch.confidence,
            disclaimer: result.disclaimer,
            reading: result.reading,
            facts: result.facts,
            findings: result.findings,
            evidence: result.evidence,
            evidenceSha256: result.reading.evidenceSha256
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private struct ProtocolPayload: Encodable {
        struct AppInfo: Encodable {
            let name: String
            let version: String
            let bundleId: String
        }

        let app: AppInfo
        let protocolNumber: String
        let createdAt: String
        let analyzedAt: String
        let profile: String
        let profileLabel: String
        let score: Int
        let verdict: String
        let verdictLabel: String
        let shortVerdict: String
        let justifyingMarkers: [EvidenceResult]
        let decisiveEvidence: [String]
        let evidenceCatalogVersion: Int
        let attribution: AttributionAssessment?
        let trackId: String
        let trackConfidence: Double
        let disclaimer: String
        let reading: IntegrityReading
        let facts: [MeasuredFact]
        let findings: [Finding]
        let evidence: EvidenceAssessment
        let evidenceSha256: String?
    }
}

// MARK: - Protocol Pack

enum ProtocolPack {

    struct PackURLs {
        let pdfURL: URL
        let jsonURL: URL
        let directoryURL: URL
    }

    /// AirDrop-freundliche Dateinamen: `ScooterCheck_<Protokoll>_Bericht.pdf/.json`
    static func fileBaseName(protocolNumber: String) -> String {
        let safe = protocolNumber.replacingOccurrences(of: "/", with: "-")
        return "ScooterCheck_\(safe)"
    }

    static func makePack(
        session: CheckSession,
        result: IntegrityResult,
        directory: URL? = nil
    ) throws -> PackURLs {
        let baseDir = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ScooterCheck-\(session.protocolNumber)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let base = fileBaseName(protocolNumber: session.protocolNumber)
        // Canonical names used by history store + legacy short names for compatibility.
        let pdfURL = baseDir.appendingPathComponent("\(session.protocolNumber).pdf")
        let jsonURL = baseDir.appendingPathComponent("\(session.protocolNumber).json")
        let sharePdfURL = baseDir.appendingPathComponent("\(base)_Bericht.pdf")
        let shareJsonURL = baseDir.appendingPathComponent("\(base)_Daten.json")

        let pdfData = try ProtocolPDF.render(session: session, result: result)
        try pdfData.write(to: pdfURL, options: .atomic)
        try pdfData.write(to: sharePdfURL, options: .atomic)

        let jsonData = try ProtocolJSON.makeJSON(session: session, result: result)
        try jsonData.write(to: jsonURL, options: .atomic)
        try jsonData.write(to: shareJsonURL, options: .atomic)

        return PackURLs(pdfURL: sharePdfURL, jsonURL: shareJsonURL, directoryURL: baseDir)
    }
}

// MARK: - PDF Renderer

enum ProtocolPDF {

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 @ 72 dpi
    private static let margin: CGFloat = 48
    private static let lineHeight: CGFloat = 16
    private static let sectionGap: CGFloat = 14
    private static let contentWidth: CGFloat = pageRect.width - 2 * margin

    static func render(session: CheckSession, result: IntegrityResult) throws -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            var y = beginStyledPage(context)
            y = drawLetterhead(context: context, session: session, result: result, y: y)
            y = drawPlainSectionI(context: context, session: session, result: result, y: y)
            y = drawPlainSectionII(context: context, result: result, y: y)
            y = drawPlainSectionIII(context: context, result: result, y: y)
            y = drawPlainSectionIV(context: context, result: result, y: y)
            y = drawClosingNotes(context: context, session: session, result: result, y: y)
        }
    }

    // MARK: Letterhead

    private static func drawLetterhead(
        context: UIGraphicsPDFRendererContext,
        session: CheckSession,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        var cursor = y

        // Brand wordmark (Scooter + Check like in-app Wordmark)
        let brandY = cursor
        let scooterW = measure("Scooter", font: titleFont(size: 26))
        _ = drawText("Scooter", at: brandY, font: titleFont(size: 26), color: Theme.UI.accent)
        cursor = drawText(
            "Check",
            at: brandY,
            font: titleFont(size: 26),
            color: Theme.UI.text,
            xOffset: scooterW
        )
        cursor += 6
        cursor = drawText(
            "Integritätsprotokoll · schreibgeschützte Auslese",
            at: cursor,
            font: bodyFont(size: 11),
            color: Theme.UI.muted
        )
        cursor += 10

        // Meta card
        let metaH: CGFloat = 78
        drawCard(in: CGRect(x: margin, y: cursor, width: contentWidth, height: metaH))
        var metaY = cursor + 12
        metaY = drawText("Protokoll-Nr.  \(session.protocolNumber)", at: metaY, font: bodyFont(size: 11, weight: .semibold), color: Theme.UI.text, indent: 14)
        metaY = drawText("Erstellt        \(germanDate(session.createdAt))", at: metaY, font: bodyFont(size: 11), color: Theme.UI.muted, indent: 14)
        metaY = drawText("App             \(appVersion)", at: metaY, font: bodyFont(size: 11), color: Theme.UI.muted, indent: 14)
        metaY = drawText("Profil          \(result.profile.label)", at: metaY, font: bodyFont(size: 11), color: Theme.UI.muted, indent: 14)
        cursor += metaH + 12

        // Verdict strip
        let verdictColor = Theme.UI.verdict(result.verdict)
        let stripH: CGFloat = 52
        drawRoundedRect(CGRect(x: margin, y: cursor, width: contentWidth, height: stripH), fill: Theme.UI.card, stroke: verdictColor)
        _ = drawText(result.verdict.label, at: cursor + 10, font: titleFont(size: 16), color: verdictColor, indent: 14)
        _ = drawText(
            "Score \(result.score)/100  ·  \(result.trackMatch.trackId.label)",
            at: cursor + 30,
            font: bodyFont(size: 11),
            color: Theme.UI.muted,
            indent: 14
        )
        return cursor + stripH + sectionGap
    }

    // MARK: Sections I–IV (Klartext-Bericht)

    private static func drawPlainSectionI(
        context: UIGraphicsPDFRendererContext,
        session: CheckSession,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 140)
        cursor = drawHeading("I. Zusammenfassung", at: cursor)
        cursor = drawText(
            result.verdict.label,
            at: cursor,
            font: bodyFont(size: 13, weight: .semibold),
            color: Theme.UI.verdict(result.verdict)
        )
        cursor = drawParagraph(result.evidence.shortVerdictText, at: cursor)
        cursor += 4
        cursor = drawSubheading(
            result.verdict == .stock ? "Ergebnis in Klartext" : "Was ist aufgefallen?",
            at: cursor
        )
        if result.evidence.problemBullets.isEmpty {
            cursor = drawParagraph(result.evidence.problemOverview, at: cursor)
        } else {
            for bullet in result.evidence.problemBullets {
                cursor = drawParagraph("• \(bullet)", at: cursor)
            }
        }
        cursor = drawText(
            "Score \(result.score)/100 verdichtet nur die Feststellungen und erzeugt kein Gesamturteil.",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )
        cursor += 6
        cursor = drawSubheading("Fahrzeugdaten", at: cursor)
        let rows: [(String, String)] = [
            ("Fahrzeugtyp", result.profile.label),
            ("Angezeigte Seriennummer", result.reading.serialDisplay ?? "—"),
            ("Kilometerstand", Format.km.format(result.reading.odometerKm)),
            ("Protokoll", session.protocolNumber),
            ("Katalogversion", "v\(result.evidence.catalogVersion)")
        ]
        for (label, value) in rows {
            cursor = drawKeyValue(label, value: value, at: cursor)
        }
        cursor += 4
        cursor = drawParagraph(
            """
            Dieses Dokument ist eine technische Dokumentation und Zustandsprüfung auf Basis einer \
            schreibgeschützten Auslese. Es werden keine Fahrzeugparameter verändert.
            """,
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )
        return cursor + sectionGap
    }

    private static func drawPlainSectionII(
        context: UIGraphicsPDFRendererContext,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 80)
        cursor = drawHeading("II. Was ist aufgefallen?", at: cursor)
        cursor = drawText(
            "Die für das Gesamturteil maßgeblichen Punkte in Alltagssprache.",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )

        let markers = result.evidence.justifyingMarkers
        if markers.isEmpty {
            cursor = drawParagraph(
                "Es wurden keine abweichenden Punkte festgestellt, die zum Gesamturteil beitragen.",
                at: cursor
            )
        }
        for r in markers.prefix(12) {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 5)
            cursor = drawText(
                r.plainLanguage.title,
                at: cursor,
                font: bodyFont(size: 11, weight: .semibold),
                color: Theme.UI.text
            )
            cursor = drawParagraph(r.plainLanguage.summary, at: cursor)
            cursor = drawText(
                "Festgestellt: \(r.fact.interpretedValue ?? r.fact.rawValue)  ·  Erwartet: \(r.fact.expectedValue ?? "—")",
                at: cursor,
                font: bodyFont(size: 9),
                color: Theme.UI.muted
            )
            cursor = drawText(
                "Einordnung: \(r.classification.label)",
                at: cursor,
                font: bodyFont(size: 9, weight: .medium),
                color: Theme.UI.text
            )
            if let contrib = r.plainLanguage.verdictContribution {
                cursor = drawText("Bedeutung: \(contrib)", at: cursor, font: bodyFont(size: 8), color: Theme.UI.muted)
            }
            cursor += 4
        }

        let positives = result.facts.filter { $0.id.hasPrefix("positive.") }
        if !positives.isEmpty {
            cursor = ensureSpace(context: context, y: cursor, needed: 40)
            cursor = drawSubheading("Unauffällige Befunde", at: cursor)
            for fact in positives.prefix(8) {
                cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2)
                cursor = drawText("• \(fact.title)", at: cursor, font: bodyFont(size: 9, weight: .semibold), color: Theme.UI.text)
                cursor = drawText("  \(fact.erlaeuterung)", at: cursor, font: bodyFont(size: 8), color: Theme.UI.muted)
            }
        }
        return cursor + sectionGap
    }

    private static func drawPlainSectionIII(
        context: UIGraphicsPDFRendererContext,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        guard let attr = result.evidence.attribution else { return y }
        var cursor = ensureSpace(context: context, y: y, needed: 90)
        cursor = drawHeading("III. Vermutete Art der Veränderung", at: cursor)
        cursor = drawText(
            "Heuristische technische Zuordnung — zeigt nicht, mit welchem Werkzeug eine Veränderung vorgenommen wurde.",
            at: cursor,
            font: bodyFont(size: 8),
            color: Theme.UI.muted
        )
        cursor = drawText(
            attr.headline,
            at: cursor,
            font: bodyFont(size: 12, weight: .semibold),
            color: Theme.UI.text
        )
        cursor = drawText(
            "Konfidenz: \(attr.confidenceLabel) (\(String(format: "%.2f", attr.confidence))) · Katalog \(attr.catalogVersion)",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )
        cursor = drawParagraph(EvidenceExplanationEngine.attributionPlain(attr), at: cursor)
        if let pattern = attr.knownPatternId {
            cursor = drawText("Pattern: \(pattern)", at: cursor, font: monoFont(size: 8), color: Theme.UI.muted)
        }
        if !attr.supportingMarkerIds.isEmpty {
            cursor = drawText(
                "Stützende Marker: \(attr.supportingMarkerIds.joined(separator: ", "))",
                at: cursor,
                font: bodyFont(size: 8),
                color: Theme.UI.muted
            )
        }
        if !attr.contradictingMarkerIds.isEmpty {
            cursor = drawText(
                "Gegenbelege: \(attr.contradictingMarkerIds.joined(separator: ", "))",
                at: cursor,
                font: bodyFont(size: 8),
                color: Theme.UI.muted
            )
        }
        return cursor + sectionGap
    }

    private static func drawPlainSectionIV(
        context: UIGraphicsPDFRendererContext,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 60)
        cursor = drawHeading("IV. Technische Details", at: cursor)
        cursor = drawText(
            "Maschinennahe Auslese zur technischen Überprüfbarkeit. Katalog v\(result.evidence.catalogVersion).",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )

        // IV.a Rohdaten
        cursor = ensureSpace(context: context, y: cursor, needed: 40)
        cursor = drawSubheading("IV.a Rohdatenregister", at: cursor)
        cursor = drawText(
            "\(result.reading.rawRegisters.count) Register ausgelesen.",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )
        for reg in result.reading.rawRegisters {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2)
            cursor = drawText(
                "\(reg.address)  \(reg.name)  \(reg.valueHex)",
                at: cursor,
                font: monoFont(size: 8),
                color: Theme.UI.text
            )
            if let decoded = reg.valueDecoded {
                cursor = drawText("    → \(decoded)", at: cursor, font: bodyFont(size: 8), color: Theme.UI.muted)
            }
        }

        // IV.b Boards
        cursor = ensureSpace(context: context, y: cursor, needed: 50)
        cursor = drawSubheading("IV.b Boards / Steuergeräte", at: cursor)
        let boards: [(String, String?)] = [
            ("Fahrzeug/Display", result.reading.serialDisplay),
            ("VCU", result.reading.serialVcu),
            ("MCU", result.reading.serialMcu),
            ("BLE", result.reading.serialBle),
            ("BMS", result.reading.serialBms)
        ]
        for (name, sn) in boards {
            cursor = drawKeyValue(name, value: sn ?? "—", at: cursor)
        }
        for issue in result.evidence.crossBoardIssues {
            cursor = drawText("• \(issue.title): \(issue.detail)", at: cursor, font: bodyFont(size: 8), color: Theme.UI.danger)
        }

        // IV.c Firmware
        cursor = ensureSpace(context: context, y: cursor, needed: 50)
        cursor = drawSubheading("IV.c Firmware / Seriennummern", at: cursor)
        cursor = drawKeyValue("MCU-FW", value: result.reading.fwMcu ?? "—", at: cursor)
        cursor = drawKeyValue("BLE-FW", value: result.reading.fwBle ?? "—", at: cursor)
        cursor = drawKeyValue("VCU-FW", value: result.reading.fwVcu ?? "—", at: cursor)
        cursor = drawKeyValue("BMS-FW", value: result.reading.fwBms ?? "—", at: cursor)
        for fact in result.facts.filter({ $0.group == .firmware || $0.id.hasPrefix("diff.") }).prefix(12) {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2)
            cursor = drawText(
                "• \(fact.title): \(fact.auslesewert) [\(fact.status.label)]",
                at: cursor,
                font: bodyFont(size: 8),
                color: Theme.UI.text
            )
        }

        // IV.d Evidenzmatrix
        cursor = ensureSpace(context: context, y: cursor, needed: 50)
        cursor = drawSubheading("IV.d Evidenzmatrix", at: cursor)
        for r in result.evidence.results {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 3)
            cursor = drawText(
                "• \(r.fact.markerID) · \(r.classification.label) · \(r.fact.persistence.label)",
                at: cursor,
                font: bodyFont(size: 9, weight: .semibold),
                color: Theme.UI.text
            )
            for line in r.chainCitation.split(separator: "\n").prefix(8) {
                cursor = ensureSpace(context: context, y: cursor, needed: lineHeight)
                cursor = drawText("  \(line)", at: cursor, font: monoFont(size: 7), color: Theme.UI.muted)
            }
        }

        // IV.e Neutralisierungen
        let neutrals = result.evidence.results.flatMap(\.neutralizations)
        cursor = ensureSpace(context: context, y: cursor, needed: 40)
        cursor = drawSubheading("IV.e Neutralisierungen", at: cursor)
        if neutrals.isEmpty {
            cursor = drawText("Keine Neutralisierungen.", at: cursor, font: bodyFont(size: 9), color: Theme.UI.muted)
        } else {
            for n in neutrals {
                cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2)
                cursor = drawText(
                    "• \(n.ruleId): \(n.classBefore.label) → \(n.classAfter.label)",
                    at: cursor,
                    font: bodyFont(size: 9, weight: .semibold),
                    color: Theme.UI.text
                )
                cursor = drawText("  \(n.reason)", at: cursor, font: bodyFont(size: 8), color: Theme.UI.muted)
            }
        }

        // IV.f Power-Cycle
        cursor = ensureSpace(context: context, y: cursor, needed: 40)
        cursor = drawSubheading("IV.f Power-Cycle-Vergleich", at: cursor)
        if let pc = result.evidence.powerCycle {
            cursor = drawText(pc.summary, at: cursor, font: bodyFont(size: 9), color: Theme.UI.text)
            for row in pc.rows {
                let plain = EvidenceExplanationEngine.explanation(forPowerCycleRow: row)
                cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 3)
                cursor = drawText("• \(plain.title)", at: cursor, font: bodyFont(size: 9, weight: .semibold), color: Theme.UI.text)
                cursor = drawText("  \(plain.summary)", at: cursor, font: bodyFont(size: 8), color: Theme.UI.muted)
                cursor = drawText(
                    "  A \(row.scanA) → B \(row.scanB) · \(row.changeKind.label)",
                    at: cursor,
                    font: monoFont(size: 7),
                    color: Theme.UI.muted
                )
            }
        } else {
            cursor = drawText(
                "Kein Power-Cycle-Vergleich in diesem Bericht.",
                at: cursor,
                font: bodyFont(size: 9),
                color: Theme.UI.muted
            )
        }

        // IV.g Fingerprint
        cursor = ensureSpace(context: context, y: cursor, needed: 50)
        cursor = drawSubheading("IV.g Fingerprint / Hash / Katalogversion", at: cursor)
        cursor = drawKeyValue("Katalog", value: "v\(result.evidence.catalogVersion)", at: cursor)
        cursor = drawKeyValue("Fingerprint", value: result.evidence.fingerprint.digestSHA256, at: cursor)
        cursor = drawKeyValue("SHA-256 Auslese", value: result.reading.evidenceSha256 ?? "—", at: cursor)
        cursor = drawKeyValue("Analysezeitpunkt", value: germanDate(result.analyzedAt), at: cursor)
        return cursor + sectionGap
    }

    private static func drawClosingNotes(
        context: UIGraphicsPDFRendererContext,
        session: CheckSession,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 120)
        cursor = drawHeading("Hinweise zur Methodik", at: cursor)
        cursor = drawParagraph(
            """
            Die Auslese erfolgte über das Bluetooth-LE-Diagnoseprotokoll des Herstellers. \
            Register werden mit Serienprofilen verglichen. Firmware-Module (MCU, BLE, VCU, BMS) \
            werden — soweit hinterlegt — mit bekannten Serienständen abgeglichen. \
            Mustererkennung basiert auf definierten Heuristiken. Rohdaten liegen in Abschnitt IV \
            und als JSON-Anlage vor.
            """,
            at: cursor
        )
        cursor = ensureSpace(context: context, y: cursor, needed: 80)
        cursor = drawHeading("Rechtliche Hinweise", at: cursor)
        cursor = drawParagraph(result.profile.legalText, at: cursor)
        cursor += 4
        cursor = drawParagraph(result.disclaimer, at: cursor, font: bodyFont(size: 9), color: Theme.UI.muted)
        cursor = ensureSpace(context: context, y: cursor, needed: 70)
        cursor = drawHeading("Protokollvermerk", at: cursor)
        cursor = drawParagraph(
            """
            Das vorliegende Protokoll wurde maschinell erstellt und ohne Eingriff in die \
            Fahrzeugelektronik ausgewertet. Die Auslese war schreibgeschützt. \
            Ort, Datum: _________________________    Unterschrift: _________________________
            """,
            at: cursor
        )
        cursor += 8
        _ = drawText(
            "— Ende des Analyseberichts \(session.protocolNumber) —",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted
        )
        return cursor
    }

    // Unused legacy stubs removed — PDF uses drawPlainSectionI…IV + drawClosingNotes.

    @discardableResult
    private static func beginStyledPage(_ context: UIGraphicsPDFRendererContext) -> CGFloat {
        context.beginPage()
        Theme.UI.bg.setFill()
        UIBezierPath(rect: pageRect).fill()
        // Top accent bar
        Theme.UI.accent.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 4)).fill()
        return margin
    }

    private static func ensureSpace(context: UIGraphicsPDFRendererContext, y: CGFloat, needed: CGFloat) -> CGFloat {
        if y + needed > pageRect.height - margin {
            return beginStyledPage(context)
        }
        return y
    }

    private static func drawCard(in rect: CGRect) {
        drawRoundedRect(rect, fill: Theme.UI.card, stroke: Theme.UI.line)
    }

    private static func drawRoundedRect(_ rect: CGRect, fill: UIColor, stroke: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private static func drawHeading(_ text: String, at y: CGFloat) -> CGFloat {
        var cursor = drawText(text, at: y, font: titleFont(size: 14), color: Theme.UI.accent)
        drawAccentRule(at: cursor)
        return cursor + 8
    }

    private static func drawSubheading(_ text: String, at y: CGFloat) -> CGFloat {
        drawText(text, at: y, font: bodyFont(size: 11, weight: .semibold), color: Theme.UI.accent)
    }

    private static func drawAccentRule(at y: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: margin + 48, y: y))
        Theme.UI.accent.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private static func drawParagraph(
        _ text: String,
        at y: CGFloat,
        font: UIFont = bodyFont(size: 10),
        color: UIColor = Theme.UI.text
    ) -> CGFloat {
        let width = contentWidth
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        (text as NSString).draw(in: CGRect(x: margin, y: y, width: width, height: bounding.height), withAttributes: attrs)
        return y + bounding.height + 4
    }

    @discardableResult
    private static func drawText(
        _ text: String,
        at y: CGFloat,
        font: UIFont,
        color: UIColor = Theme.UI.text,
        alignment: NSTextAlignment = .left,
        indent: CGFloat = 0,
        continueSameLine: Bool = false,
        xOffset: CGFloat = 0
    ) -> CGFloat {
        let width = contentWidth - indent
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let x = margin + indent + xOffset
        let drawWidth = max(40, width - xOffset)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: drawWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        let rect = CGRect(x: x, y: y, width: drawWidth, height: max(lineHeight, bounding.height))
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        if continueSameLine { return y }
        return y + max(lineHeight, bounding.height) + 2
    }

    private static func measure(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func drawKeyValue(
        _ key: String,
        value: String,
        at y: CGFloat,
        valueColor: UIColor = Theme.UI.text
    ) -> CGFloat {
        let keyWidth: CGFloat = 150
        _ = drawText(key, at: y, font: bodyFont(size: 10), color: Theme.UI.muted)
        return drawText(
            value,
            at: y,
            font: bodyFont(size: 10, weight: .medium),
            color: valueColor,
            indent: keyWidth
        )
    }

    private static func drawTableHeader(at y: CGFloat) -> CGFloat {
        let header = String(format: "%-26@ %-14@ %-14@ %@", "Merkmal", "Auslese", "Soll", "Status")
        var cursor = drawText(header, at: y, font: monoFont(size: 9, weight: .semibold), color: Theme.UI.accent)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: cursor))
        path.addLine(to: CGPoint(x: pageRect.width - margin, y: cursor))
        Theme.UI.line.setStroke()
        path.lineWidth = 1
        path.stroke()
        return cursor + 6
    }

    private static func drawFactRow(_ fact: MeasuredFact, at y: CGFloat) -> CGFloat {
        let title = String(fact.title.prefix(24))
        let aus = String(fact.auslesewert.prefix(12))
        let soll = String(fact.sollwert.prefix(12))
        let line = String(format: "%-26@ %-14@ %-14@ %@", title, aus, soll, fact.status.label)
        return drawText(line, at: y, font: monoFont(size: 8), color: Theme.UI.fact(fact.status))
    }

    // MARK: Typography (aligned with app: SF Rounded / system)

    private static func titleFont(size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .bold).rounded()
    }

    private static func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight).rounded()
    }

    private static func monoFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func germanDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension UIFont {
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Activity Share

struct ActivityShare: UIViewControllerRepresentable {
    let items: [Any]
    var subject: String?
    var excludedActivityTypes: [UIActivity.ActivityType]? = [
        .assignToContact,
        .addToReadingList,
        .postToFacebook,
        .postToTwitter,
        .postToWeibo,
        .postToVimeo,
        .postToFlickr,
        .postToTencentWeibo
    ]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        if let subject {
            controller.setValue(subject, forKey: "subject")
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Named file wrapper so AirDrop / Files show clear ScooterCheck titles.
final class NamedShareFile: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let utType: String

    init(url: URL, title: String, utType: String) {
        self.url = url
        self.title = title
        self.utType = utType
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        utType
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        nil
    }
}

// MARK: - SwiftUI Convenience

extension View {
    func shareIntegrityPack(session: CheckSession, result: IntegrityResult, isPresented: Binding<Bool>) -> some View {
        modifier(IntegrityPackShareModifier(session: session, result: result, isPresented: isPresented))
    }

    func sharePackURLs(_ packURLs: Binding<ProtocolPack.PackURLs?>, subject: String, isPresented: Binding<Bool>) -> some View {
        modifier(PackURLsShareModifier(packURLs: packURLs, subject: subject, isPresented: isPresented))
    }
}

private struct IntegrityPackShareModifier: ViewModifier {
    let session: CheckSession
    let result: IntegrityResult
    @Binding var isPresented: Bool
    @State private var packURLs: ProtocolPack.PackURLs?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: { packURLs = nil; errorMessage = nil }) {
                if let packURLs {
                    ActivityShare(
                        items: shareItems(from: packURLs, protocolNumber: session.protocolNumber),
                        subject: "ScooterCheck Protokoll \(session.protocolNumber)"
                    )
                } else if let errorMessage {
                    Text(errorMessage)
                        .padding()
                } else {
                    ProgressView("Protokoll für AirDrop wird erstellt…")
                        .task { await preparePack() }
                }
            }
    }

    private func preparePack() async {
        do {
            // Dauerhaft im Offline-Verlauf ablegen, dann PDF+JSON teilen.
            var durable = session
            if durable.result == nil {
                durable.result = result
            }
            packURLs = try ProtocolHistoryStore.shared.save(durable)
        } catch {
            do {
                packURLs = try ProtocolPack.makePack(session: session, result: result)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PackURLsShareModifier: ViewModifier {
    @Binding var packURLs: ProtocolPack.PackURLs?
    let subject: String
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let packURLs {
                    ActivityShare(
                        items: shareItems(from: packURLs, protocolNumber: subject),
                        subject: subject
                    )
                } else {
                    ProgressView()
                }
            }
    }
}

private func shareItems(from pack: ProtocolPack.PackURLs, protocolNumber: String) -> [Any] {
    [
        NamedShareFile(
            url: pack.pdfURL,
            title: "ScooterCheck \(protocolNumber) Bericht.pdf",
            utType: "com.adobe.pdf"
        ),
        NamedShareFile(
            url: pack.jsonURL,
            title: "ScooterCheck \(protocolNumber) Daten.json",
            utType: "public.json"
        )
    ]
}

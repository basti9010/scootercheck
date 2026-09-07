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
            trackId: result.trackMatch.trackId.rawValue,
            trackConfidence: result.trackMatch.confidence,
            disclaimer: result.disclaimer,
            reading: result.reading,
            facts: result.facts,
            findings: result.findings,
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
        let trackId: String
        let trackConfidence: Double
        let disclaimer: String
        let reading: IntegrityReading
        let facts: [MeasuredFact]
        let findings: [Finding]
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
            y = drawSectionI(context: context, y: y)
            y = drawSectionII(context: context, session: session, result: result, y: y)
            y = drawSectionIII(context: context, y: y)
            y = drawSectionIV(context: context, result: result, y: y)
            y = drawSectionIVa(context: context, result: result, y: y)
            y = drawSectionV(context: context, result: result, y: y)
            y = drawSectionVI(context: context, result: result, y: y)
            y = drawSectionVII(context: context, result: result, y: y)
            y = drawSectionVIII(context: context, result: result, y: y)
            y = drawSectionIX(context: context, y: y)
            _ = drawSectionX(context: context, session: session, y: y)
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

    // MARK: Sections I–X

    private static func drawSectionI(context: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 120)
        cursor = drawHeading("I. Gegenstand und Zweck", at: cursor)
        let text = """
        Gegenstand dieses Protokolls ist die dokumentierte, ausschließlich lesende Auswertung \
        elektronisch gespeicherter Fahrzeugparameter eines Elektrokleinstfahrzeugs. Zweck ist die \
        nachvollziehbare Feststellung, ob Auslesewerte mit werkseitigen Sollwerten übereinstimmen \
        oder Abweichungen erkennbar sind. Es werden keine Parameter verändert.
        """
        return drawParagraph(text, at: cursor) + sectionGap
    }

    private static func drawSectionII(
        context: UIGraphicsPDFRendererContext,
        session: CheckSession,
        result: IntegrityResult,
        y: CGFloat
    ) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 160)
        cursor = drawHeading("II. Sachverhalt / Gerätedaten", at: cursor)
        let rows: [(String, String)] = [
            ("Fahrzeugtyp", result.profile.label),
            ("Angezeigte Seriennummer", result.reading.serialDisplay ?? "—"),
            ("MCU-Seriennummer", result.reading.serialMcu ?? "—"),
            ("Kilometerstand", Format.km.format(result.reading.odometerKm)),
            ("MCU-Firmware", result.reading.fwMcu ?? "—"),
            ("BLE-Firmware", result.reading.fwBle ?? "—"),
            ("VCU-Firmware", result.reading.fwVcu ?? "—"),
            ("BMS-Firmware", result.reading.fwBms ?? "—"),
            ("Protokoll-Generation", Format.num.format(result.reading.protocolGen))
        ]
        for (label, value) in rows {
            cursor = drawKeyValue(label, value: value, at: cursor)
        }
        return cursor + sectionGap
    }

    private static func drawSectionIII(context: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 100)
        cursor = drawHeading("III. Methodik", at: cursor)
        let text = """
        Die Auslese erfolgte über das Bluetooth-LE-Diagnoseprotokoll des Herstellers. \
        Ausgelesene Register werden mit typgenehmigungsrelevanten Sollwerten verglichen. \
        Firmware-Module (MCU, BLE, VCU, BMS) werden als Versionsregister ausgelesen und — \
        soweit für das Modell hinterlegt — mit öffentlich bekannten Serienständen abgeglichen. \
        Mustererkennung (Serienkonfiguration, Web-App, SHU) basiert auf definierten \
        Heuristiken. Alle Rohdaten werden im Anhang IV.a und als JSON-Anlage bereitgestellt.
        """
        return drawParagraph(text, at: cursor) + sectionGap
    }

    private static func drawSectionIV(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 80)
        cursor = drawHeading("IV. Auslesewerte (Zusammenfassung)", at: cursor)
        cursor = drawTableHeader(at: cursor)

        let summaryFacts = result.facts.filter {
            [.speed, .serial, .firmware, .flags].contains($0.group)
        }.prefix(22)

        for fact in summaryFacts {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight + 6)
            cursor = drawFactRow(fact, at: cursor)
        }

        cursor = ensureSpace(context: context, y: cursor, needed: 80)
        cursor += 8
        cursor = drawSubheading("IV.b Firmware-Analyse", at: cursor)
        cursor = drawText(
            "Modulversionen, Katalogstatus und Rohhex der Versionsregister.",
            at: cursor,
            font: bodyFont(size: 10),
            color: Theme.UI.muted
        )
        let fwFacts = result.facts.filter { $0.group == .firmware }
        for fact in fwFacts {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2 + 4)
            cursor = drawKeyValue(fact.title, value: "\(fact.auslesewert) · \(fact.bewertung)", at: cursor)
            if let raw = fact.raw, !raw.isEmpty {
                cursor = drawText(
                    "  Nachweis: \(raw)",
                    at: cursor,
                    font: monoFont(size: 8),
                    color: Theme.UI.muted
                )
            }
        }
        return cursor + sectionGap
    }

    private static func drawSectionIVa(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 60)
        cursor = drawHeading("IV.a Anhang — Rohdatenregister", at: cursor)
        cursor = drawText(
            "Vollständige Liste der ausgelesenen Register (\(result.reading.rawRegisters.count) Einträge).",
            at: cursor,
            font: bodyFont(size: 10),
            color: Theme.UI.muted
        )

        for reg in result.reading.rawRegisters {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2)
            let line = "\(reg.address)  \(reg.name)  \(reg.valueHex)"
            cursor = drawText(line, at: cursor, font: monoFont(size: 9), color: Theme.UI.text)
            if let decoded = reg.valueDecoded {
                cursor = drawText("    → \(decoded)", at: cursor, font: bodyFont(size: 9), color: Theme.UI.muted)
            }
            if let note = reg.note {
                cursor = drawText("    Hinweis: \(note)", at: cursor, font: bodyFont(size: 9), color: Theme.UI.danger)
            }
        }
        return cursor + sectionGap
    }

    private static func drawSectionV(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 60)
        cursor = drawHeading("V. Bewertung der Einzelfakten", at: cursor)

        for group in FactGroup.allCases {
            guard let groupFacts = result.factGroups[group], !groupFacts.isEmpty else { continue }
            cursor = ensureSpace(context: context, y: cursor, needed: 40)
            cursor = drawSubheading(group.rawValue, at: cursor)
            for fact in groupFacts where fact.status != .regelkonform {
                cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 3)
                cursor = drawText(
                    "• \(fact.title): \(fact.bewertung)",
                    at: cursor,
                    font: bodyFont(size: 10, weight: .semibold),
                    color: Theme.UI.text
                )
                cursor = drawText(
                    "  [\(fact.status.label)]",
                    at: cursor,
                    font: bodyFont(size: 9, weight: .medium),
                    color: Theme.UI.fact(fact.status)
                )
                cursor = drawText(
                    "  Auslesewert: \(fact.auslesewert)  ·  Sollwert: \(fact.sollwert)",
                    at: cursor,
                    font: bodyFont(size: 9),
                    color: Theme.UI.muted
                )
                cursor = drawText(
                    "  \(fact.erlaeuterung)",
                    at: cursor,
                    font: bodyFont(size: 9),
                    color: Theme.UI.muted
                )
            }
        }
        return cursor + sectionGap
    }

    private static func drawSectionVI(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 110)
        cursor = drawHeading("VI. Gesamtbewertung", at: cursor)
        cursor = drawKeyValue("Integritätsscore", value: "\(result.score) / 100", at: cursor)
        cursor = drawKeyValue("Bewertung", value: result.verdict.label, at: cursor, valueColor: Theme.UI.verdict(result.verdict))
        cursor = drawKeyValue(
            "Musterzuordnung",
            value: "\(result.trackMatch.trackId.label) (\(Int(result.trackMatch.confidence * 100)) %)",
            at: cursor
        )
        cursor += 4
        cursor = drawParagraph(result.verdict.laymanText, at: cursor)
        return cursor + sectionGap
    }

    private static func drawSectionVII(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 80)
        cursor = drawHeading("VII. Rechtliche Hinweise", at: cursor)
        cursor = drawParagraph(result.profile.legalText, at: cursor)
        cursor += 4
        cursor = drawParagraph(result.disclaimer, at: cursor, font: bodyFont(size: 9), color: Theme.UI.muted)
        return cursor + sectionGap
    }

    private static func drawSectionVIII(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 60)
        cursor = drawHeading("VIII. Integritätsnachweis", at: cursor)
        cursor = drawKeyValue("SHA-256 (Evidenz)", value: result.reading.evidenceSha256 ?? "—", at: cursor)
        cursor = drawKeyValue("Analysezeitpunkt", value: germanDate(result.analyzedAt), at: cursor)
        return cursor + sectionGap
    }

    private static func drawSectionIX(context: UIGraphicsPDFRendererContext, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 50)
        cursor = drawHeading("IX. Anlagen", at: cursor)
        cursor = drawText("1. JSON-Datensatz (siehe Exportpaket)", at: cursor, font: bodyFont(size: 10), color: Theme.UI.text)
        cursor = drawText("2. Rohdatenregister (Abschnitt IV.a)", at: cursor, font: bodyFont(size: 10), color: Theme.UI.text)
        return cursor + sectionGap
    }

    private static func drawSectionX(context: UIGraphicsPDFRendererContext, session: CheckSession, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 90)
        cursor = drawHeading("X. Protokollvermerk", at: cursor)
        let text = """
        Das vorliegende Protokoll wurde maschinell erstellt und ohne Eingriff in die \
        Fahrzeugelektronik ausgewertet. Die Auslese war schreibgeschützt. \
        Ort, Datum: _________________________    Unterschrift: _________________________
        """
        cursor = drawParagraph(text, at: cursor)
        cursor += 10
        _ = drawText(
            "— Ende des Protokolls \(session.protocolNumber) —",
            at: cursor,
            font: bodyFont(size: 9),
            color: Theme.UI.muted,
            alignment: .center
        )
        return cursor
    }

    // MARK: Drawing Primitives

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

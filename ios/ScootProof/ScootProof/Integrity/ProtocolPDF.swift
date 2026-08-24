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
                bundleId: Bundle.main.bundleIdentifier ?? "com.tuningscanner"
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

    static func makePack(
        session: CheckSession,
        result: IntegrityResult,
        directory: URL? = nil
    ) throws -> PackURLs {
        let baseDir = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ScooterCheck-\(session.protocolNumber)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let pdfURL = baseDir.appendingPathComponent("\(session.protocolNumber).pdf")
        let jsonURL = baseDir.appendingPathComponent("\(session.protocolNumber).json")

        let pdfData = try ProtocolPDF.render(session: session, result: result)
        try pdfData.write(to: pdfURL, options: .atomic)

        let jsonData = try ProtocolJSON.makeJSON(session: session, result: result)
        try jsonData.write(to: jsonURL, options: .atomic)

        return PackURLs(pdfURL: pdfURL, jsonURL: jsonURL, directoryURL: baseDir)
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
    private static let margin: CGFloat = 56
    private static let lineHeight: CGFloat = 16
    private static let sectionGap: CGFloat = 12

    static func render(session: CheckSession, result: IntegrityResult) throws -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            var y = margin
            y = drawLetterhead(context: context, session: session, y: y)
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

    private static func drawLetterhead(context: UIGraphicsPDFRendererContext, session: CheckSession, y: CGFloat) -> CGFloat {
        context.beginPage()
        var cursor = y

        cursor = drawText("ScooterCheck", at: cursor, font: font(name: "TimesNewRomanPS-BoldMT", size: 22))
        cursor = drawText("Integritätsprotokoll — schreibgeschützte Auslese", at: cursor, font: bodyFont(size: 11), color: .darkGray)
        cursor += 4
        cursor = drawText("Protokoll-Nr.: \(session.protocolNumber)", at: cursor, font: bodyFont(size: 11))
        cursor = drawText("Erstellt am: \(germanDate(session.createdAt))", at: cursor, font: bodyFont(size: 11))
        cursor = drawText("App-Version: \(appVersion)", at: cursor, font: bodyFont(size: 11))
        cursor += sectionGap
        drawHorizontalRule(at: cursor)
        return cursor + sectionGap
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
        }.prefix(18)

        for fact in summaryFacts {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight + 4)
            cursor = drawFactRow(fact, at: cursor)
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
            color: .darkGray
        )

        for reg in result.reading.rawRegisters {
            cursor = ensureSpace(context: context, y: cursor, needed: lineHeight * 2)
            let line = "\(reg.address)  \(reg.name)  \(reg.valueHex)"
            cursor = drawText(line, at: cursor, font: monoFont(size: 9))
            if let decoded = reg.valueDecoded {
                cursor = drawText("    → \(decoded)", at: cursor, font: bodyFont(size: 9), color: .darkGray)
            }
            if let note = reg.note {
                cursor = drawText("    Hinweis: \(note)", at: cursor, font: bodyFont(size: 9), color: .systemRed)
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
                cursor = drawText("• \(fact.title): \(fact.bewertung) [\(fact.status.label)]", at: cursor, font: bodyFont(size: 10, bold: true))
                cursor = drawText("  Auslesewert: \(fact.auslesewert)  |  Sollwert: \(fact.sollwert)", at: cursor, font: bodyFont(size: 9))
                cursor = drawText("  Erläuterung: \(fact.erlaeuterung)", at: cursor, font: bodyFont(size: 9), color: .darkGray)
            }
        }
        return cursor + sectionGap
    }

    private static func drawSectionVI(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 100)
        cursor = drawHeading("VI. Gesamtbewertung", at: cursor)
        cursor = drawKeyValue("Integritätsscore", value: "\(result.score) / 100", at: cursor)
        cursor = drawKeyValue("Bewertung", value: result.verdict.label, at: cursor)
        cursor = drawKeyValue("Musterzuordnung", value: "\(result.trackMatch.trackId.label) (\(Int(result.trackMatch.confidence * 100)) %)", at: cursor)
        cursor += 4
        cursor = drawParagraph(result.verdict.laymanText, at: cursor)
        return cursor + sectionGap
    }

    private static func drawSectionVII(context: UIGraphicsPDFRendererContext, result: IntegrityResult, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 80)
        cursor = drawHeading("VII. Rechtliche Hinweise", at: cursor)
        cursor = drawParagraph(result.profile.legalText, at: cursor)
        cursor += 4
        cursor = drawParagraph(result.disclaimer, at: cursor, font: bodyFont(size: 9), color: .darkGray)
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
        cursor = drawText("1. JSON-Datensatz (\(sessionPlaceholder))", at: cursor, font: bodyFont(size: 10))
        cursor = drawText("2. Rohdatenregister (Abschnitt IV.a)", at: cursor, font: bodyFont(size: 10))
        return cursor + sectionGap
    }

    private static let sessionPlaceholder = "siehe Exportpaket"

    private static func drawSectionX(context: UIGraphicsPDFRendererContext, session: CheckSession, y: CGFloat) -> CGFloat {
        var cursor = ensureSpace(context: context, y: y, needed: 80)
        cursor = drawHeading("X. Protokollvermerk", at: cursor)
        let text = """
        Das vorliegende Protokoll wurde maschinell erstellt und ohne Eingriff in die \
        Fahrzeugelektronik ausgewertet. Die Auslese war schreibgeschützt. \
        Ort, Datum: _________________________    Unterschrift: _________________________
        """
        cursor = drawParagraph(text, at: cursor)
        cursor += 8
        _ = drawText(
            "— Ende des Protokolls \(session.protocolNumber) —",
            at: cursor,
            font: bodyFont(size: 9),
            color: .gray,
            alignment: .center
        )
        return cursor
    }

    // MARK: Drawing Primitives

    private static func ensureSpace(context: UIGraphicsPDFRendererContext, y: CGFloat, needed: CGFloat) -> CGFloat {
        if y + needed > pageRect.height - margin {
            context.beginPage()
            return margin
        }
        return y
    }

    private static func drawHeading(_ text: String, at y: CGFloat) -> CGFloat {
        drawText(text, at: y, font: font(name: "TimesNewRomanPS-BoldMT", size: 14))
    }

    private static func drawSubheading(_ text: String, at y: CGFloat) -> CGFloat {
        drawText(text, at: y, font: font(name: "TimesNewRomanPS-BoldMT", size: 11))
    }

    private static func drawParagraph(
        _ text: String,
        at y: CGFloat,
        font: UIFont = bodyFont(size: 10),
        color: UIColor = .black
    ) -> CGFloat {
        let width = pageRect.width - 2 * margin
        let rect = CGRect(x: margin, y: y, width: width, height: .greatestFiniteMagnitude)
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

    private static func drawText(
        _ text: String,
        at y: CGFloat,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let width = pageRect.width - 2 * margin
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: margin, y: y, width: width, height: lineHeight * 3)
        (text as NSString).draw(with: rect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attrs,
            context: nil
        )
        return y + max(lineHeight, bounding.height) + 2
    }

    private static func drawKeyValue(_ key: String, value: String, at y: CGFloat) -> CGFloat {
        let text = "\(key): \(value)"
        return drawText(text, at: y, font: bodyFont(size: 10))
    }

    private static func drawHorizontalRule(at y: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func drawTableHeader(at y: CGFloat) -> CGFloat {
        let header = String(format: "%-28@ %-14@ %-14@ %@", "Merkmal", "Auslesewert", "Sollwert", "Bewertung")
        var cursor = drawText(header, at: y, font: monoFont(size: 9, bold: true))
        drawHorizontalRule(at: cursor)
        return cursor + 4
    }

    private static func drawFactRow(_ fact: MeasuredFact, at y: CGFloat) -> CGFloat {
        let title = String(fact.title.prefix(26))
        let aus = String(fact.auslesewert.prefix(12))
        let soll = String(fact.sollwert.prefix(12))
        let line = String(format: "%-28@ %-14@ %-14@ %@", title, aus, soll, fact.status.label)
        return drawText(line, at: y, font: monoFont(size: 8))
    }

  private static func font(name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    private static func bodyFont(size: CGFloat, bold: Bool = false) -> UIFont {
        let name = bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT"
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func monoFont(size: CGFloat, bold: Bool = false) -> UIFont {
        let name = bold ? "Courier-Bold" : "Courier"
        return UIFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func germanDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Activity Share

struct ActivityShare: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - SwiftUI Convenience

extension View {
    func shareIntegrityPack(session: CheckSession, result: IntegrityResult, isPresented: Binding<Bool>) -> some View {
        modifier(IntegrityPackShareModifier(session: session, result: result, isPresented: isPresented))
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
            .sheet(isPresented: $isPresented, onDismiss: { packURLs = nil }) {
                if let packURLs {
                    ActivityShare(items: [packURLs.pdfURL, packURLs.jsonURL, packURLs.directoryURL])
                } else if let errorMessage {
                    Text(errorMessage)
                        .padding()
                } else {
                    ProgressView("Protokoll wird erstellt…")
                        .task { await preparePack() }
                }
            }
    }

    private func preparePack() async {
        do {
            packURLs = try ProtocolPack.makePack(session: session, result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

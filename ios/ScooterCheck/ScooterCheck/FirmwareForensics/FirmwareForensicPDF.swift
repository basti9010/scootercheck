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

            y = heading(ctx, "Paketmetadaten", y: y)
            y = line(ctx, "Format: \(formatKind(report.containerKind))", y: y)
            y = line(ctx, "Name: \(report.meta.displayName ?? "—")", y: y)
            y = line(ctx, "Modelle: \(report.meta.models.joined(separator: ", ").nilIfEmpty ?? "—")", y: y)
            y = line(ctx, "Steuergerät: \(report.meta.type ?? "—")", y: y)
            y = line(ctx, "Boards: \(report.meta.compatible.joined(separator: ", ").nilIfEmpty ?? "—")", y: y)
            y = gap(y)

            y = heading(ctx, "Archivinhalt", y: y)
            for e in report.entries {
                y = ensure(ctx, y: y, need: 36)
                y = line(ctx, "• \(e.path) — \(e.digest.byteCount) B — \(e.analysisStatus)", y: y)
                y = line(ctx, "  SHA-256: \(e.digest.sha256)", y: y, size: 9)
            }
            y = gap(y)

            y = heading(ctx, "Verschlüsselung", y: y)
            y = line(ctx, report.crypto.status.label, y: y)
            y = line(ctx, "Format: \(report.crypto.detectedFormat)", y: y)
            y = line(ctx, "Entschlüsselung: \(report.crypto.decryptionAvailable ? "verfügbar" : "nicht verfügbar")", y: y)
            y = line(ctx, report.crypto.decryptionNote, y: y, size: 9)
            y = gap(y)

            y = heading(ctx, "Technische Befunde", y: y)
            for item in report.evidence {
                y = ensure(ctx, y: y, need: 52)
                y = line(ctx, "[\(item.verifiability.label)] \(item.title)", y: y)
                y = line(ctx, item.detail, y: y, size: 9)
                y = line(ctx, "Beleg: \(item.evidence) · Methode: \(item.method)", y: y, size: 8)
            }
            y = gap(y)

            if let cmp = report.comparison {
                y = heading(ctx, "Referenzvergleich", y: y)
                y = line(ctx, cmp.outcome.label, y: y)
                y = line(ctx, cmp.note, y: y, size: 9)
                y = gap(y)
            }

            y = heading(ctx, "Forensische Bewertung", y: y)
            y = line(ctx, report.verdict.label, y: y)
            y = line(ctx, report.verdictRationale, y: y, size: 9)
            y = gap(y)

            y = heading(ctx, "Grenzen der Untersuchung", y: y)
            for lim in report.limits {
                y = ensure(ctx, y: y, need: 28)
                y = line(ctx, "• \(lim)", y: y, size: 9)
            }
            y = gap(y)
            y = line(ctx, "ScooterCheck Firmware-Forensik — nur lesend. Keine Aussage über Rechtmäßigkeit ohne weiteren Kontext.", y: y, size: 8)
            _ = y
        }
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
        let bounds = ns.boundingRect(with: CGSize(width: contentWidth, height: 200), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
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

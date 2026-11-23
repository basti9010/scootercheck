import Foundation

/// Forensische Evidenzstufe — darf nicht „hochgestuft“ werden ohne neue Quelle.
enum FirmwareEvidenceTier: String, Codable, Sendable, CaseIterable {
    case muster
    case statisch
    case emuliert
    case live
    case nichtVerifiziert

    var label: String {
        switch self {
        case .muster: return "MUSTER"
        case .statisch: return "STATISCH"
        case .emuliert: return "EMULIERT"
        case .live: return "LIVE"
        case .nichtVerifiziert: return "NICHT_VERIFIZIERT"
        }
    }

    var shortExplanation: String {
        switch self {
        case .muster:
            return "Auffälligkeit durch YARA, Bytefolge oder Heuristik — kein Funktionsnachweis."
        case .statisch:
            return "Nachvollziehbare Code-/Strukturanalyse (ohne Fahrzeugbeobachtung)."
        case .emuliert:
            return "In kontrollierter Teil-Emulation beobachtet — nicht am realen Fahrzeug."
        case .live:
            return "An einem realen Testgerät dokumentiert."
        case .nichtVerifiziert:
            return "Technische Vermutung ohne ausreichenden Nachweis."
        }
    }
}

/// Vertrauenswürdigkeit einer Stock-/OEM-Referenz.
enum FirmwareReferenceTrust: String, Codable, Sendable {
    /// Herstellerseitig oder intern verifizierte OEM-/Serien-Referenz.
    case manufacturerVerified
    /// Bibliothekseintrag (z. B. Community), SHA-Match möglich, Herkunft nicht bestätigt.
    case communityLibrary
    case serialProduction
    case unknown

    var label: String {
        switch self {
        case .manufacturerVerified: return "Hersteller-/intern verifiziert"
        case .communityLibrary: return "Community-/Bibliotheksreferenz (nicht herstellerseitig bestätigt)"
        case .serialProduction: return "Serien-/Produktionsreferenz"
        case .unknown: return "Referenzvertrauen unbekannt"
        }
    }

    /// Nur manufacturerVerified zählt für Ampel-GRÜN bei Identitätsmatch.
    var allowsGreenIdentity: Bool {
        self == .manufacturerVerified
    }
}

/// Klassifizierter Einzelfund für UI/PDF/JSON (abwärtskompatibel optional).
struct FirmwareClassifiedFinding: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var category: String
    var tier: FirmwareEvidenceTier
    var tool: String
    var fileName: String?
    var offsetOrAddress: String?
    var detail: String
    var evidenceSource: String
    var limitations: String
    var confidence: FirmwareFindingConfidence
    var observedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, category, tier, tool, fileName, offsetOrAddress, detail
        case evidenceSource, limitations, confidence, observedAt
    }
}

enum FirmwareEvidenceClassifier {
    /// Baut eine konservative Fundliste aus Deep-Analysis — ohne Hochstufung.
    static func classify(from deep: FirmwareDeepAnalysisResult, fileName: String? = nil) -> [FirmwareClassifiedFinding] {
        var out: [FirmwareClassifiedFinding] = []
        let when = deep.producedAt

        if let stock = deep.stockDiff {
            let trust = Self.referenceTrust(for: stock)
            out.append(.init(
                id: "stock-\(stock.outcome.rawValue)",
                category: "stockDiff",
                tier: .statisch,
                tool: "stockDiff",
                fileName: fileName,
                offsetOrAddress: stock.firstDiffOffset.map { String(format: "0x%X", $0) },
                detail: stock.note,
                evidenceSource: [
                    stock.referenceLabel,
                    stock.referenceSHA256.map { "refSHA=\($0.prefix(16))…" },
                    trust.label
                ].compactMap { $0 }.joined(separator: " · "),
                limitations: "Byte-/SHA-Vergleich belegt keine Installation am Fahrzeug. Community-Refs sind nicht herstellerseitig bestätigt.",
                confidence: stock.outcome == .identical ? .high : .medium,
                observedAt: when
            ))
        }

        for m in deep.yaraMatches {
            out.append(.init(
                id: "yara-\(m.rule)",
                category: "yara",
                tier: .muster,
                tool: "yara",
                fileName: fileName,
                offsetOrAddress: nil,
                detail: "\(m.rule): \(m.description)",
                evidenceSource: "family=\(m.family ?? "—") confidence=\(m.confidence)",
                limitations: "YARA erkennt Bytefolgen/Muster — kein Nachweis realen Fahrzeugverhaltens.",
                confidence: m.confidence.lowercased() == "high" ? .medium : .low,
                observedAt: when
            ))
        }

        for s in deep.speedLimits {
            let tier: FirmwareEvidenceTier = {
                switch s.source {
                case .serverEmulation: return .emuliert
                case .liveVehicleContext: return .live
                case .serverYara, .knownCatalog: return .muster
                case .serverLLM: return .nichtVerifiziert
                default: return .statisch
                }
            }()
            out.append(.init(
                id: s.id,
                category: "speedLimit",
                tier: tier,
                tool: s.source.label,
                fileName: fileName,
                offsetOrAddress: nil,
                detail: "\(Int(s.kmh)) km/h — \(s.role.label). \(s.evidence)",
                evidenceSource: s.source.rawValue,
                limitations: tier == .emuliert
                    ? "Teil-Emulation, keine Peripherie/Fahrzeugbeobachtung."
                    : "Codefund ≠ installierte Firmware.",
                confidence: s.confidence,
                observedAt: when
            ))
        }

        for line in deep.comboSummaries {
            let live = FirmwareComboPolicy.isValidatedCombo(line)
            out.append(.init(
                id: "combo-\(line.hashValue)",
                category: "combo",
                tier: live ? .live : .nichtVerifiziert,
                tool: "combo_policy",
                fileName: fileName,
                offsetOrAddress: nil,
                detail: line,
                evidenceSource: live ? "Live-/Belegt-/Validiert-Prefix" : "unbekannt",
                limitations: live
                    ? "Nur gültig für dokumentierten Live-/Belegt-Kontext."
                    : "Ohne Validierungs-Prefix keine Tastenfolge.",
                confidence: live ? .high : .low,
                observedAt: when
            ))
        }

        if let ivt = deep.cortexMIvt {
            out.append(.init(
                id: "ivt",
                category: "ivt",
                tier: .statisch,
                tool: "cortex_m_ivt",
                fileName: fileName,
                offsetOrAddress: ivt.resetHandler,
                detail: "Cortex-M IVT Heuristik: likely=\(ivt.likely.map(String.init) ?? "?") reset=\(ivt.resetHandler ?? "—")",
                evidenceSource: "serverIvt",
                limitations: "Heuristik auf Vektortabelle — kein Laufzeitbeweis.",
                confidence: (ivt.likely == true) ? .medium : .low,
                observedAt: when
            ))
        }

        if let pin = deep.boardPinout {
            out.append(.init(
                id: "pinout-\(pin.id ?? "x")",
                category: "boardPinout",
                tier: .nichtVerifiziert,
                tool: "board_pinouts",
                fileName: fileName,
                offsetOrAddress: nil,
                detail: pin.notes ?? "Board-Pinout-Hinweis",
                evidenceSource: pin.id ?? "board_pinouts",
                limitations: "Community-/Board-Heuristik, kein Schaltplan-Nachweis.",
                confidence: .low,
                observedAt: when
            ))
        }

        if deep.sources.contains(.serverEmulation) || deep.sources.contains(.serverAngr) {
            out.append(.init(
                id: "emulation-scope",
                category: "emulation",
                tier: .emuliert,
                tool: "unicorn/angr",
                fileName: fileName,
                offsetOrAddress: nil,
                detail: "Kurzfenster-Emulation / Pfadhinweise ausgeführt.",
                evidenceSource: deep.sources.map(\.rawValue).joined(separator: ","),
                limitations: "Keine UART/GPIO/BLE-Modellierung; kein Boot des Controllers.",
                confidence: .low,
                observedAt: when
            ))
        }

        return out
    }

    static func referenceTrust(for stock: FirmwareStockDiffResult) -> FirmwareReferenceTrust {
        if let raw = stock.referenceTrust, let parsed = FirmwareReferenceTrust(rawValue: raw) {
            return parsed
        }
        let src = (stock.referenceSource ?? "").lowercased()
        let note = (stock.note + " " + (stock.referenceLabel ?? "")).lowercased()
        if stock.referenceProvenanceVerified == true {
            return .manufacturerVerified
        }
        if note.contains("rexzy") || note.contains("community") || note.contains("x3-firmware") {
            return .communityLibrary
        }
        if src == "serial" || src == "serie" || src == "production" {
            return .serialProduction
        }
        if src == "oem" || src == "factory" || src == "stock" {
            // source=oem ohne Provenance-Flag → nicht automatisch Herstellerursprung
            return .communityLibrary
        }
        return .unknown
    }
}

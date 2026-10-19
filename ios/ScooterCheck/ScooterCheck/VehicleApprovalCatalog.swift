import Foundation

/// Deutscher Zulassungsstatus für eine konkret identifizierte Fahrzeugausführung.
enum GermanVehicleApprovalStatus: String, Codable, Sendable, Equatable {
    /// Bestätigte deutsche Genehmigung für diese Ausführung (soweit im Katalog belegt).
    case approved
    /// Bekannte Ausführung ohne dokumentierte deutsche Genehmigung im Katalog.
    case noGermanApprovalDocumented
    /// Zulassungsstatus nicht bestätigt.
    case unconfirmed
    /// Modell nicht eindeutig identifiziert.
    case modelUnidentified

    var label: String {
        switch self {
        case .approved: return "Deutsche Genehmigung dokumentiert (Katalog)"
        case .noGermanApprovalDocumented: return "Keine deutsche Genehmigung dokumentiert"
        case .unconfirmed: return "Zulassungsstatus nicht bestätigt"
        case .modelUnidentified: return "Modell nicht eindeutig identifiziert"
        }
    }

    /// Darf eine gesonderte Zulassungswarnung auslösen?
    var warrantsApprovalAlert: Bool {
        self == .noGermanApprovalDocumented
    }

    /// Unsichere Zuordnung → mildere Warnung (Fall C).
    var warrantsPossibleApprovalAlert: Bool {
        self == .modelUnidentified
    }
}

struct VehicleApprovalEntry: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var manufacturer: String
    var model: String
    var variantKeys: [String]
    var namePatterns: [String]
    var bleNamePatterns: [String]
    var germanApproval: GermanVehicleApprovalStatus
    var abeNumber: String?
    var maxSpeedKmhDocumented: Double?
    var source: String
    var sourceUrl: String
    var updatedAt: String
    var confidence: String
    var notes: String?
}

struct VehicleApprovalMatch: Equatable, Sendable {
    var entry: VehicleApprovalEntry
    /// true = konkrete Variante; false = nur Marke / unsicher.
    var concreteVariant: Bool
    var matchedOn: String
}

/// Versionierte, lokal gebündelte Zulassungshinweise — keine erfundenen ABE-Nummern.
struct VehicleApprovalCatalog: Sendable {
    struct File: Codable, Sendable {
        var version: Int
        var source: String
        var sourceUrl: String
        var updatedAt: String
        var note: String?
        var entries: [VehicleApprovalEntry]
    }

    private(set) var version: Int
    private(set) var source: String
    private(set) var sourceUrl: String
    private(set) var updatedAt: String
    private(set) var entries: [VehicleApprovalEntry]

    static let shared: VehicleApprovalCatalog = {
        VehicleApprovalCatalog.loadBundled() ?? .emptyFallback()
    }()

    /// Match gegen Anzeigename / BLE-Name / Identifikationsmodell.
    func match(
        displayName: String?,
        bleName: String?,
        modelLabel: String?,
        manufacturerHint: String?
    ) -> VehicleApprovalMatch? {
        let hay = [displayName, bleName, modelLabel, manufacturerHint]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.uppercased() }
            .joined(separator: " ")
        guard !hay.isEmpty else { return nil }

        // Konkrete Varianten zuerst (G2 Master, G4, …), Familie zuletzt.
        let ordered = entries.sorted { a, b in
            specificity(a) > specificity(b)
        }

        for entry in ordered {
            if let key = entry.variantKeys.first(where: { hay.contains($0.uppercased()) }) {
                let concrete = entry.germanApproval != .modelUnidentified
                    && !entry.id.hasSuffix("uncertain")
                return VehicleApprovalMatch(entry: entry, concreteVariant: concrete, matchedOn: key)
            }
            if let pat = entry.namePatterns.first(where: { hay.contains($0.uppercased()) }) {
                // KuKirin G2 darf nicht Ninebot Max G2 treffen: Brand-Marker verlangen
                if entry.manufacturer.uppercased().contains("KUKIRIN") {
                    guard hay.contains("KUKIRIN") || hay.contains("KUGOO") else { continue }
                }
                let concrete = entry.germanApproval != .modelUnidentified
                return VehicleApprovalMatch(entry: entry, concreteVariant: concrete, matchedOn: pat)
            }
        }
        return nil
    }

    private func specificity(_ e: VehicleApprovalEntry) -> Int {
        let keys = e.variantKeys.map(\.count).max() ?? 0
        let names = e.namePatterns.map(\.count).max() ?? 0
        let penalty = e.germanApproval == .modelUnidentified ? 1000 : 0
        return keys + names - penalty
    }

    private init(file: File) {
        version = file.version
        source = file.source
        sourceUrl = file.sourceUrl
        updatedAt = file.updatedAt
        entries = file.entries
    }

    private static func loadBundled() -> VehicleApprovalCatalog? {
        guard let url = Bundle.main.url(forResource: "vehicle_approval_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return nil
        }
        return VehicleApprovalCatalog(file: file)
    }

    private static func emptyFallback() -> VehicleApprovalCatalog {
        VehicleApprovalCatalog(
            file: File(
                version: 0,
                source: "Embedded empty fallback",
                sourceUrl: "https://www.kba.de/",
                updatedAt: "fallback",
                note: "Bundle JSON missing",
                entries: []
            )
        )
    }
}

// MARK: - KuKirin / brand model hints (name-based, no invented UUIDs)

enum ExtendedScooterModelHint {
    struct Result: Equatable, Sendable {
        var title: String
        var shortBadge: String
        var brand: String
        var isConcrete: Bool
    }

    static func recognize(bleName: String?, displayName: String? = nil) -> Result? {
        let hay = [bleName, displayName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !hay.isEmpty else { return nil }

        let isKu = hay.contains("KUKIRIN") || hay.contains("KUGOO KIRIN")
            || (hay.contains("KUGOO") && (hay.contains("G2") || hay.contains("G3") || hay.contains("G4")))
        guard isKu else { return nil }

        if hay.contains("G2 MASTER") {
            return Result(title: "KuKirin G2 Master", shortBadge: "G2 Master", brand: "KuKirin", isConcrete: true)
        }
        if hay.range(of: #"\bG4\b"#, options: .regularExpression) != nil || hay.contains("G4 MAX") {
            return Result(title: "KuKirin G4", shortBadge: "G4", brand: "KuKirin", isConcrete: true)
        }
        if hay.range(of: #"\bG3\b"#, options: .regularExpression) != nil {
            return Result(title: "KuKirin G3", shortBadge: "G3", brand: "KuKirin", isConcrete: true)
        }
        if hay.range(of: #"\bG2\b"#, options: .regularExpression) != nil {
            return Result(title: "KuKirin G2", shortBadge: "G2", brand: "KuKirin", isConcrete: true)
        }
        return Result(title: "KuKirin (Modell unklar)", shortBadge: "KuKirin", brand: "KuKirin", isConcrete: false)
    }
}

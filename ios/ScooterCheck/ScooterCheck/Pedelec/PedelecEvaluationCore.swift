import Foundation

/// Read-only Pedelec-/eBike-Heuristik (kein Bosch-Protokoll-Dump).
///
/// Ziel: BLE-Kandidaten erkennen und Pilotmodelle dokumentieren.
/// Tiefenauslese (Limit/Tuning-Register) ist für Bosch Smart System noch nicht verfügbar.
enum PedelecEvaluationCore {

    /// Bluetooth SIG Company Identifier: Robert Bosch GmbH.
    static let boschCompanyId: UInt16 = 0x02A6

    /// DE/EU: unterstützte Geschwindigkeit mit Motorassistenz (Pedelec).
    static let legalAssistLimitKmhDE: Int = 25

    /// Pilotfahrzeug aus Feldversuch (Ghost + Bosch Performance Line CX).
    static let pilotGhostRiotEN = PedelecPilotModel(
        id: "ghost-riot-en-universal-bosch-cx",
        brand: "GHOST",
        model: "RIOT EN UNIVERSAL",
        frameSizeHint: "S",
        driveSystem: "Bosch Smart System",
        motor: "Performance Line CX",
        displayHint: "Kiox 300 / Kiox 500",
        remoteHint: "Bosch LED Remote",
        legalAssistLimitKmh: legalAssistLimitKmhDE,
        notes: [
            "Mid-Drive mit Bosch-ePowered-Gehäuse und CX-Kennzeichnung.",
            "Anzeige und LED-Remote gehören zum Smart System (BLE, Pairing/Bonding).",
            "Prüffrage: Assistenz über dem gesetzlichen Limit (DE 25 km/h) möglich?",
        ]
    )

    static let pilotModels: [PedelecPilotModel] = [pilotGhostRiotEN]

    /// Namens-/Service-Hinweise aus Advertisements (konservativ).
    static let advertisementNameTokens: [String] = [
        "bosch",
        "ebike",
        "e-bike",
        "e bike",
        "bes3",
        "kiox",
        "purion",
        "intuvia",
        "smart system",
        "flow",
        "ghost",
        "pedelec",
    ]

    /// Bewertet ein gescanntes BLE-Gerät als möglichen Pedelec-/Bosch-Kandidaten.
    static func evaluate(device: ScannedPedelecAdvertisement) -> PedelecCandidateMatch {
        var reasons: [String] = []
        var score = 0

        if let companyId = device.manufacturerCompanyId {
            if companyId == boschCompanyId {
                score += 70
                reasons.append("Manufacturer Company ID 0x02A6 (Robert Bosch GmbH)")
            } else if let name = BluetoothCompanyCatalog.shared.name(forCompanyId: companyId),
                      name.localizedCaseInsensitiveContains("Bosch") {
                score += 55
                reasons.append("Hersteller laut SIG: \(name)")
            }
        }

        let haystack = [
            device.name,
            device.cryptoName,
            device.modelLabel ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        for token in advertisementNameTokens {
            if haystack.contains(token) {
                score += token == "bosch" || token == "ghost" ? 25 : 12
                reasons.append("Name enthält „\(token)“")
            }
        }

        // Deduplicate reason lines while keeping order.
        var seen = Set<String>()
        reasons = reasons.filter { seen.insert($0).inserted }

        score = min(score, 100)
        let confidence: PedelecMatchConfidence
        switch score {
        case 70...: confidence = .high
        case 35..<70: confidence = .medium
        case 1..<35: confidence = .low
        default: confidence = .none
        }

        return PedelecCandidateMatch(
            score: score,
            confidence: confidence,
            reasons: reasons,
            deepReadoutAvailable: false
        )
    }

    /// Filtert und sortiert Kandidaten aus einer Geräteliste.
    static func rankedCandidates(from devices: [ScannedPedelecAdvertisement]) -> [PedelecRankedDevice] {
        devices.compactMap { device in
            let match = evaluate(device: device)
            guard match.confidence != .none else { return nil }
            return PedelecRankedDevice(device: device, match: match)
        }
        .sorted {
            if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
            return $0.device.rssi > $1.device.rssi
        }
    }

    /// Kurzer Status für die UI: was heute geht / was noch fehlt.
    static var readoutCapabilitySummary: String {
        """
        BLE-Näherkennung (Bosch-Manufacturer-ID / Namensmuster) ist aktiv. \
        Eine Register-Auslese wie bei Ninebot/Xiaomi (Limit, Peak, Firmware) \
        ist für Bosch Smart System noch nicht implementiert — Pairing und \
        proprietäres Protokoll stehen aus.
        """
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "  ", with: " ")
    }
}

// MARK: - Models

struct PedelecPilotModel: Identifiable, Equatable, Sendable {
    let id: String
    let brand: String
    let model: String
    let frameSizeHint: String?
    let driveSystem: String
    let motor: String
    let displayHint: String
    let remoteHint: String
    let legalAssistLimitKmh: Int
    let notes: [String]

    var title: String { "\(brand) \(model)" }

    var subtitle: String {
        "\(driveSystem) · \(motor) · Assistenz-Limit DE \(legalAssistLimitKmh) km/h"
    }
}

struct ScannedPedelecAdvertisement: Equatable, Sendable {
    let id: UUID
    let name: String
    let cryptoName: String
    let rssi: Int
    let modelLabel: String?
    let manufacturerDataHex: String?
    let serviceUUIDs: [String]

    var manufacturerCompanyId: UInt16? {
        BLEManufacturerParsing.companyId(fromManufacturerHex: manufacturerDataHex)
    }

    init(
        id: UUID,
        name: String,
        cryptoName: String,
        rssi: Int,
        modelLabel: String? = nil,
        manufacturerDataHex: String? = nil,
        serviceUUIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.cryptoName = cryptoName
        self.rssi = rssi
        self.modelLabel = modelLabel
        self.manufacturerDataHex = manufacturerDataHex
        self.serviceUUIDs = serviceUUIDs
    }

    init(device: ScannedDevice) {
        self.init(
            id: device.id,
            name: device.name,
            cryptoName: device.cryptoName,
            rssi: device.rssi,
            modelLabel: device.modelLabel,
            manufacturerDataHex: device.manufacturerDataHex,
            serviceUUIDs: device.serviceUUIDs
        )
    }
}

enum PedelecMatchConfidence: String, Equatable, Sendable {
    case none
    case low
    case medium
    case high

    var labelDE: String {
        switch self {
        case .none: return "kein Treffer"
        case .low: return "schwach"
        case .medium: return "möglich"
        case .high: return "wahrscheinlich"
        }
    }
}

struct PedelecCandidateMatch: Equatable, Sendable {
    let score: Int
    let confidence: PedelecMatchConfidence
    let reasons: [String]
    /// Immer false, bis ein Bosch-Read-Only-Protokoll angebunden ist.
    let deepReadoutAvailable: Bool
}

struct PedelecRankedDevice: Identifiable, Equatable, Sendable {
    var id: UUID { device.id }
    let device: ScannedPedelecAdvertisement
    let match: PedelecCandidateMatch
}

import Foundation

/// Lokale, versionierte Bluetooth-SIG Company-Identifier-Datenbank.
/// Quelle: Bluetooth SIG Assigned Numbers — Company Identifiers.
struct BluetoothCompanyCatalog: Sendable {
    struct Entry: Codable, Sendable, Equatable {
        var id: UInt16
        var hex: String
        var name: String
    }

    struct File: Codable, Sendable {
        var version: Int
        var source: String
        var sourceUrl: String
        var updatedAt: String
        var note: String?
        var companies: [Entry]
    }

    private(set) var version: Int
    private(set) var source: String
    private(set) var sourceUrl: String
    private(set) var updatedAt: String
    private var byId: [UInt16: Entry]

    static let shared: BluetoothCompanyCatalog = {
        BluetoothCompanyCatalog.loadBundled() ?? BluetoothCompanyCatalog.fallbackMinimal()
    }()

    var companyCount: Int { byId.count }

    func name(forCompanyId id: UInt16) -> String? {
        byId[id]?.name
    }

    func entry(forCompanyId id: UInt16) -> Entry? {
        byId[id]
    }

    private init(file: File) {
        version = file.version
        source = file.source
        sourceUrl = file.sourceUrl
        updatedAt = file.updatedAt
        var map: [UInt16: Entry] = [:]
        for c in file.companies {
            map[c.id] = c
        }
        byId = map
    }

    private static func loadBundled() -> BluetoothCompanyCatalog? {
        let url =
            Bundle.main.url(forResource: "bluetooth_company_identifiers", withExtension: "json")
            ?? Bundle.main.url(
                forResource: "bluetooth_company_identifiers",
                withExtension: "json",
                subdirectory: "Resources"
            )
        guard let url,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return nil
        }
        return BluetoothCompanyCatalog(file: file)
    }

    /// Minimale Offline-Fallback-Liste, falls Bundle-JSON fehlt (Tests / Preview).
    private static func fallbackMinimal() -> BluetoothCompanyCatalog {
        let companies: [Entry] = [
            .init(id: 0x004C, hex: "0x004C", name: "Apple, Inc."),
            .init(id: 0x0075, hex: "0x0075", name: "Samsung Electronics Co. Ltd."),
            .init(id: 0x038F, hex: "0x038F", name: "Xiaomi Inc."),
            .init(id: 0x0F1F, hex: "0x0F1F", name: "Ninebot (Changzhou) Tech Co., Ltd."),
            .init(id: 0x0059, hex: "0x0059", name: "Nordic Semiconductor ASA"),
            .init(id: 0x00E0, hex: "0x00E0", name: "Google"),
            .init(id: 0x0006, hex: "0x0006", name: "Microsoft"),
            .init(id: 0x00C4, hex: "0x00C4", name: "LG Electronics"),
            .init(id: 0x015D, hex: "0x015D", name: "Estimote, Inc."),
            .init(id: 0x02E5, hex: "0x02E5", name: "Espressif Incorporated"),
        ]
        return BluetoothCompanyCatalog(
            file: File(
                version: 0,
                source: "Embedded fallback subset",
                sourceUrl: "https://www.bluetooth.com/specifications/assigned-numbers/",
                updatedAt: "fallback",
                note: "Bundle JSON missing — using curated minimal set.",
                companies: companies
            )
        )
    }
}

// MARK: - Documented vendor / service patterns (no invented model IDs)

enum BLEKnownServiceUUID {
    /// Ninebot custom UART (dokumentiert in ScooterCheck-Protokollschicht).
    static let ninebotUART = "6E400001-0000-0000-006E-696E65626F74"
    /// Nordic UART — von Xiaomi-Scootern und vielen anderen Geräten genutzt (allein nicht scooterspezifisch).
    static let nordicUART = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

    static let genericAccess = "1800"
    static let genericAttribute = "1801"
    static let deviceInformation = "180A"
    static let battery = "180F"
    static let heartRate = "180D"
    static let cyclingSpeedCadence = "1816"
    static let runningSpeedCadence = "1814"
    static let environmentalSensing = "181A"
    static let automationIO = "1815"
    static let immediateAlert = "1802"
    static let linkLoss = "1803"
    static let txPower = "1804"
    static let humanInterfaceDevice = "1812"
    static let bloodPressure = "1810"
    static let glucose = "1808"
    static let pulseOximeter = "1822"
    static let weightScale = "181D"
    static let eddystone = "FEAA"
    static let exposureNotification = "FD6F"
    static let appleContinuityPrefix = "FD"

    static func normalize(_ uuid: String) -> String {
        uuid.uppercased().replacingOccurrences(of: "-", with: "")
    }

    static func shortForm(_ uuid: String) -> String {
        let n = normalize(uuid)
        if n.count == 32, n.hasPrefix("0000"), n.hasSuffix("00001000800000805F9B34FB") {
            return String(n.dropFirst(4).prefix(4))
        }
        if n.count == 4 { return n }
        return uuid.uppercased()
    }
}

/// Company IDs, die häufig bei Endgeräten vorkommen, aber keine Geräteklasse implizieren.
enum BLECompanyId {
    static let apple: UInt16 = 0x004C
    static let samsung: UInt16 = 0x0075
    static let xiaomi: UInt16 = 0x038F
    static let ninebot: UInt16 = 0x0F1F
    static let nordic: UInt16 = 0x0059
    static let google: UInt16 = 0x00E0
    static let microsoft: UInt16 = 0x0006
    static let lg: UInt16 = 0x00C4
    static let estimote: UInt16 = 0x015D
    static let espressif: UInt16 = 0x02E5
    static let sony: UInt16 = 0x012D
    static let bose: UInt16 = 0x009E
    static let garmin: UInt16 = 0x0087
    static let fitbit: UInt16 = 0x018E
}

// MARK: - Vendor pattern catalog (separate from SIG company list)

/// Versionierte, dokumentierte Erkennungsmuster — nie allein Geräteklasse aus Hersteller.
struct BLEVendorPatternCatalog: Sendable {
    struct Pattern: Codable, Sendable, Equatable {
        var id: String
        var organization: String?
        var companyIds: [String]
        var serviceUUIDs: [String]
        var suggestedCategory: String?
        var requires: String
        var evidence: String
        var aloneImpliesCategory: Bool
    }

    struct File: Codable, Sendable {
        var version: Int
        var source: String
        var sourceUrl: String
        var updatedAt: String
        var note: String?
        var patterns: [Pattern]
    }

    private(set) var version: Int
    private(set) var source: String
    private(set) var patterns: [Pattern]

    static let shared: BLEVendorPatternCatalog = {
        BLEVendorPatternCatalog.loadBundled() ?? .embeddedFallback()
    }()

    func patterns(matchingCompanyId id: UInt16) -> [Pattern] {
        let hex = String(format: "0x%04X", id).uppercased()
        return patterns.filter { p in
            p.companyIds.contains { $0.uppercased() == hex }
        }
    }

    func patterns(matchingServiceUUID uuid: String) -> [Pattern] {
        let n = BLEKnownServiceUUID.normalize(uuid)
        return patterns.filter { p in
            p.serviceUUIDs.contains { BLEKnownServiceUUID.normalize($0) == n
                || n.contains(BLEKnownServiceUUID.normalize($0))
                || BLEKnownServiceUUID.normalize($0).contains(n) }
        }
    }

    private init(file: File) {
        version = file.version
        source = file.source
        patterns = file.patterns
    }

    private static func loadBundled() -> BLEVendorPatternCatalog? {
        guard let url = Bundle.main.url(forResource: "ble_vendor_patterns", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return nil
        }
        return BLEVendorPatternCatalog(file: file)
    }

    private static func embeddedFallback() -> BLEVendorPatternCatalog {
        BLEVendorPatternCatalog(
            file: File(
                version: 0,
                source: "Embedded fallback",
                sourceUrl: "https://www.bluetooth.com/specifications/assigned-numbers/",
                updatedAt: "fallback",
                note: "Bundle JSON missing",
                patterns: [
                    Pattern(
                        id: "ninebot-uart",
                        organization: "Ninebot (Changzhou) Tech Co., Ltd.",
                        companyIds: ["0x0F1F"],
                        serviceUUIDs: [BLEKnownServiceUUID.ninebotUART],
                        suggestedCategory: "eScooter",
                        requires: "ninebotUART",
                        evidence: "Documented Ninebot UART",
                        aloneImpliesCategory: false
                    )
                ]
            )
        )
    }
}

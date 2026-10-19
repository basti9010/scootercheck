import Foundation

/// Ergebnis der passiven Fingerprint-Einordnung (ohne erfundenes Modell).
enum BLEFingerprintStatus: String, Sendable, Equatable {
    case identified
    case likelyFamily
    case unknown

    var label: String {
        switch self {
        case .identified: return "Identifiziert"
        case .likelyFamily: return "Wahrscheinliche Gerätefamilie"
        case .unknown: return "Unbekannt"
        }
    }

    static func from(confidence: BLEIdentificationConfidence?) -> BLEFingerprintStatus {
        switch confidence {
        case .high: return .identified
        case .medium: return .likelyFamily
        case .low, .unknown, .none: return .unknown
        }
    }
}

/// Verifizierte Gerätefähigkeiten aus GATT-Discovery (keine Namens-Annahmen).
struct BLEDeviceCapabilities: Equatable, Sendable {
    var supportsImmediateAlert = false
    /// Alert Level erlaubt Write oder WriteWithoutResponse.
    var alertPreferWriteWithoutResponse = false
    /// Dokumentierter Nordic LED Button Service (Demo-/Dev-Boards).
    var supportsNordicLed = false
    var supportsBatteryReading = false
    var supportsDeviceInformation = false
    /// RSSI-Näherungssuche am iPhone — immer verfügbar, steuert kein Fremdgerät.
    var proximitySearchAvailable = true
    var discoveredServiceUUIDs: [String] = []
    var probed = false

    var supportsAlert: Bool { supportsImmediateAlert }
    var supportsVisualIdentification: Bool { supportsNordicLed }

    var hasAnyDeviceAction: Bool {
        supportsImmediateAlert || supportsNordicLed
    }
}

enum BLELocateActionPhase: Equatable, Sendable {
    case idle
    case probing
    case ready
    case sending
    /// BLE-Stack hat den Write bestätigt (oder WriteWithoutResponse wurde abgesetzt).
    case commandSent
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Bereit"
        case .probing: return "Schnittstellen werden geprüft…"
        case .ready: return "Erkannt"
        case .sending: return "Befehl wird gesendet…"
        case .commandSent: return "Befehl gesendet (akustische Reaktion nicht verifiziert)"
        case .failed(let msg): return msg
        }
    }
}

/// Standardisierte Find-Me / Immediate-Alert Level (SIG).
enum BLEImmediateAlertLevel: UInt8, CaseIterable, Sendable {
    case none = 0
    case mild = 1
    case high = 2
}

/// Bekannte, dokumentierte UUIDs für sichere Capability-/Schreibpfade.
enum BLECapabilityUUID {
    static let immediateAlertService = "1802"
    static let alertLevel = "2A06"
    static let batteryService = "180F"
    static let batteryLevel = "2A19"
    static let deviceInformation = "180A"
    /// Nordic LED Button Service (nRF Blinky) — dokumentiertes Demo-GATT.
    static let nordicLedButtonService = "00001523-1212-EFDE-1523-785FEABCD123"
    static let nordicLedCharacteristic = "00001525-1212-EFDE-1523-785FEABCD123"

    static func matches(_ uuid: String, shortOrFull needle: String) -> Bool {
        let a = uuid.uppercased().replacingOccurrences(of: "-", with: "")
        let b = needle.uppercased().replacingOccurrences(of: "-", with: "")
        if a == b { return true }
        // 16-bit in 128-bit Bluetooth Base UUID (0000XXXX…)
        if b.count == 4 {
            return a.hasPrefix("0000\(b)") || a.contains(b)
        }
        return a.contains(b) || b.contains(a)
    }
}

enum BLECapabilityDeriver {
    struct CharProbe: Equatable, Sendable {
        var serviceUUID: String
        var uuid: String
        var canWrite: Bool
        var canWriteWithoutResponse: Bool
    }

    static func derive(services: [String], characteristics: [CharProbe]) -> BLEDeviceCapabilities {
        var caps = BLEDeviceCapabilities()
        caps.discoveredServiceUUIDs = services
        caps.probed = true

        for s in services {
            if BLECapabilityUUID.matches(s, shortOrFull: BLECapabilityUUID.batteryService) {
                caps.supportsBatteryReading = true
            }
            if BLECapabilityUUID.matches(s, shortOrFull: BLECapabilityUUID.deviceInformation) {
                caps.supportsDeviceInformation = true
            }
        }

        // Immediate Alert / LED nur bei schreibbarer, dokumentierter Characteristic — nie nur am Service-Namen.
        for ch in characteristics {
            if BLECapabilityUUID.matches(ch.uuid, shortOrFull: BLECapabilityUUID.alertLevel),
               BLECapabilityUUID.matches(ch.serviceUUID, shortOrFull: BLECapabilityUUID.immediateAlertService),
               ch.canWrite || ch.canWriteWithoutResponse {
                caps.supportsImmediateAlert = true
                caps.alertPreferWriteWithoutResponse = ch.canWriteWithoutResponse
            }
            if BLECapabilityUUID.matches(ch.uuid, shortOrFull: BLECapabilityUUID.nordicLedCharacteristic),
               (ch.canWrite || ch.canWriteWithoutResponse) {
                caps.supportsNordicLed = true
            }
            if BLECapabilityUUID.matches(ch.uuid, shortOrFull: BLECapabilityUUID.batteryLevel) {
                caps.supportsBatteryReading = true
            }
        }

        return caps
    }
}

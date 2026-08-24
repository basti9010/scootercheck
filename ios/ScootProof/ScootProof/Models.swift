import Foundation

// MARK: - Formatting helpers for register decode

enum Format {
    /// 0.1 km/h units → km/h
    static func kmh(_ raw: UInt16) -> Double {
        Double(raw) / 10.0
    }

    /// Whole km/h (speed limit register).
    static func kmhWhole(_ raw: UInt16) -> Double {
        Double(raw)
    }

    /// Millimetre odometer → km.
    static func km(_ millimetres: UInt32) -> Double {
        Double(millimetres) / 1000.0
    }

    /// 10 m trip units → km.
    static func tripKm(_ raw: UInt16) -> Double {
        Double(raw) / 100.0
    }

    /// 0.1 km remaining range → km.
    static func rangeKm(_ raw: UInt16) -> Double {
        Double(raw) / 10.0
    }

    /// Seconds → minutes.
    static func minutesFromSeconds(_ raw: UInt16) -> Double {
        Double(raw) / 60.0
    }

    /// 0.01 V → volts.
    static func volts(_ raw: UInt16) -> Double {
        Double(raw) / 100.0
    }

    /// 0.1 °C → celsius.
    static func celsius(_ raw: Int16) -> Double {
        Double(raw) / 10.0
    }

    static func firmware(_ raw: UInt16) -> String {
        let major = (raw >> 8) & 0xFF
        let minor = (raw >> 4) & 0xF
        let patch = raw & 0xF
        return "\(major).\(minor).\(patch)"
    }
}

// MARK: - Integrity reading (diagnostic snapshot)

struct IntegrityReading: Codable, Equatable {
    var serialNumber: String?
    var mcuSerialNumber: String?
    var bleSerialNumber: String?
    var bmsSerialNumber: String?
    var vcuSerialNumber: String?

    var speedLimitKmh: Double?
    var ratedMaxKmh: Double?
    var tripMaxKmh: Double?
    var tripAvgKmh: Double?
    var currentSpeedKmh: Double?
    var remainingKm: Double?
    var tripKm: Double?
    var odoKm: Double?
    var tripTimeMin: Double?
    var totalRideTimeMin: Double?

    var mcuMaxKmh: Double?
    var speedSafeLock: Double?
    var gearTopKmh: Double?

    var dashboardFw: String?
    var ecuFw: String?
    var bleFw: String?
    var mcuFwDirect: String?
    var bmsFw: String?
    var vcuFw: String?

    var errorCode: UInt16?
    var alarmCode: UInt16?

    var batteryPercent: Double?
    var batteryVoltageV: Double?
    var batteryCurrentA: Double?
    var batteryCycles: UInt16?
    var batteryRemainMah: UInt16?
    var batteryDesignMah: UInt16?

    var motorTempC: Double?
    var controllerTempC: Double?

    var peakLimitSeenKmh: Double?

    var rawRegisters: [String: String] = [:]
    var liveBoards: [String] = []
    var protocolGen: ProtocolGen?
    var evidenceSha256: String?

    init() {}
}

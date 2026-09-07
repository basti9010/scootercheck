import Foundation

// MARK: - Register value scaling (used by decode)

enum RegisterScale {
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

    /// Vier Nibbles → a.b.c.d (z. B. BMS 4.1.4.8 auf Max G3).
    static func firmwareFourNibbles(_ raw: UInt16) -> String {
        let a = (raw >> 12) & 0xF
        let b = (raw >> 8) & 0xF
        let c = (raw >> 4) & 0xF
        let d = raw & 0xF
        return "\(a).\(b).\(c).\(d)"
    }

    /// Vier Bytes → a.b.c.d (längere G3-Versionen wie VCU 10.10.0.3).
    static func firmwareBytes(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        return "\(data[0]).\(data[1]).\(data[2]).\(data[3])"
    }
}

// MARK: - Diagnostic register map

enum DiagnosticMap {
    enum Category: String, CaseIterable {
        case identity
        case limit
        case history
        case firmware
        case battery
        case status
    }

    struct Spec: Hashable {
        let id: String
        let board: Nb.Board
        let register: UInt8
        let readLen: Int
        let category: Category

        var key: String {
            "\(board.rawValue)-\(String(format: "%02X", register))"
        }
    }

    static let fields: [Spec] = identityFields + limitFields + historyFields + firmwareFields + batteryFields + statusFields

    /// Profilabhängige Registerliste — Max G3 nutzt andere Board-/Versions-Adressen.
    static func fields(for profile: ScooterProfile) -> [Spec] {
        if profile.family == .maxG3 {
            return g3IdentityFields + g3LimitFields + g3HistoryFields
                + g3FirmwareFields + g3BatteryFields + g3StatusFields
        }
        return fields
    }

    // MARK: - Display (DIS 0x01)

    private static let identityFields: [Spec] = [
        Spec(id: "dis_sn", board: .dis, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "ble_sn", board: .ble, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "vcu_sn", board: .vcu, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "mcu_sn", board: .mcu, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "bms_sn", board: .bms, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
    ]

    private static let g3IdentityFields: [Spec] = [
        // Fahrzeug-SN liegt auf VCU; BLE-Name ist oft schon die ID.
        Spec(id: "vcu_g3_sn", board: .vcuG3, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "dis_sn", board: .dis, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "mcu_g3_sn", board: .mcuG3, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "ble_sn", board: .ble, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
        Spec(id: "bms_g3_sn", board: .bmsG3, register: Nb.Register.serialNumber, readLen: 14, category: .identity),
    ]

    /// Max G3: Limits auf den Boards, die live antworten (VCU/DIS/MCU) — klassische G30-Map ist oft tot.
    private static let g3LimitFields: [Spec] = [
        Spec(id: "vcu_g3_limit", board: .vcuG3, register: Nb.Register.speedLimit, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_rated", board: .vcuG3, register: Nb.Register.ratedSpeed, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_safe", board: .vcuG3, register: Nb.Register.speedSafeLock, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_max", board: .vcuG3, register: Nb.Register.mcuMaxSpeed, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_gear", board: .vcuG3, register: Nb.Register.gearTopSpeed, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_cfg", board: .vcuG3, register: 0x74, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_g1", board: .vcuG3, register: 0x7E, readLen: 2, category: .limit),
        Spec(id: "vcu_g3_g2", board: .vcuG3, register: 0x7F, readLen: 2, category: .limit),
        Spec(id: "dis_limit", board: .dis, register: Nb.Register.speedLimit, readLen: 2, category: .limit),
        Spec(id: "dis_rated", board: .dis, register: Nb.Register.ratedSpeed, readLen: 2, category: .limit),
        Spec(id: "mcu_g3_limit", board: .mcuG3, register: Nb.Register.speedLimit, readLen: 2, category: .limit),
        Spec(id: "mcu_g3_rated", board: .mcuG3, register: Nb.Register.ratedSpeed, readLen: 2, category: .limit),
        Spec(id: "mcu_g3_max", board: .mcuG3, register: Nb.Register.mcuMaxSpeed, readLen: 2, category: .limit),
        Spec(id: "mcu_g3_safe", board: .mcuG3, register: Nb.Register.speedSafeLock, readLen: 2, category: .limit),
        Spec(id: "mcu_g3_gear", board: .mcuG3, register: Nb.Register.gearTopSpeed, readLen: 2, category: .limit),
    ]

    private static let g3HistoryFields: [Spec] = [
        Spec(id: "vcu_g3_trip_max", board: .vcuG3, register: Nb.Register.tripMaxSpeed, readLen: 2, category: .history),
        Spec(id: "vcu_g3_speed", board: .vcuG3, register: Nb.Register.currentSpeed, readLen: 2, category: .history),
        Spec(id: "vcu_g3_range", board: .vcuG3, register: Nb.Register.remainingRange, readLen: 2, category: .history),
        Spec(id: "vcu_g3_odo", board: .vcuG3, register: Nb.Register.odometer, readLen: 4, category: .history),
        Spec(id: "vcu_g3_trip_km", board: .vcuG3, register: Nb.Register.tripDistance, readLen: 2, category: .history),
        Spec(id: "vcu_g3_trip4", board: .vcuG3, register: Nb.Register.tripDistance, readLen: 4, category: .history),
        Spec(id: "dis_trip_max", board: .dis, register: Nb.Register.tripMaxSpeed, readLen: 2, category: .history),
        Spec(id: "dis_speed", board: .dis, register: Nb.Register.currentSpeed, readLen: 2, category: .history),
        Spec(id: "dis_range", board: .dis, register: Nb.Register.remainingRange, readLen: 2, category: .history),
        Spec(id: "dis_odo", board: .dis, register: Nb.Register.odometer, readLen: 4, category: .history),
        Spec(id: "dis_trip_km", board: .dis, register: Nb.Register.tripDistance, readLen: 2, category: .history),
        Spec(id: "dis_trip4", board: .dis, register: Nb.Register.tripDistance, readLen: 4, category: .history),
        Spec(id: "dis_trip_time", board: .dis, register: Nb.Register.tripTime, readLen: 2, category: .history),
        Spec(id: "tft_odo", board: .tft, register: Nb.Register.odometer, readLen: 4, category: .history),
        Spec(id: "tft_trip4", board: .tft, register: Nb.Register.tripDistance, readLen: 4, category: .history),
        Spec(id: "mcu_g3_odo", board: .mcuG3, register: Nb.Register.odometer, readLen: 4, category: .history),
    ]

    private static let g3BatteryFields: [Spec] = [
        Spec(id: "dis_battery", board: .dis, register: Nb.Register.batteryPercent, readLen: 2, category: .battery),
        Spec(id: "vcu_g3_battery", board: .vcuG3, register: Nb.Register.batteryPercent, readLen: 2, category: .battery),
        Spec(id: "bms_g3_voltage", board: .bmsG3, register: Nb.Register.bmsVoltage, readLen: 2, category: .battery),
        Spec(id: "bms_g3_cycles", board: .bmsG3, register: Nb.Register.cycleCount, readLen: 2, category: .battery),
        Spec(id: "bms_g3_soc", board: .bmsG3, register: Nb.Register.bmsSoc, readLen: 2, category: .battery),
    ]

    private static let g3StatusFields: [Spec] = [
        Spec(id: "vcu_g3_error", board: .vcuG3, register: Nb.Register.error, readLen: 2, category: .status),
        Spec(id: "vcu_g3_alarm", board: .vcuG3, register: Nb.Register.alarm, readLen: 2, category: .status),
        Spec(id: "dis_error", board: .dis, register: Nb.Register.error, readLen: 2, category: .status),
        Spec(id: "dis_alarm", board: .dis, register: Nb.Register.alarm, readLen: 2, category: .status),
        Spec(id: "mcu_g3_error", board: .mcuG3, register: Nb.Register.error, readLen: 2, category: .status),
        // Soft-Unlock / Session-Flags: unbekannte Indizes als Rohdaten für Heuristik
        Spec(id: "vcu_g3_flag_a", board: .vcuG3, register: 0x5E, readLen: 2, category: .status),
        Spec(id: "vcu_g3_flag_b", board: .vcuG3, register: 0xA4, readLen: 4, category: .status),
    ]

    private static let limitFields: [Spec] = [
        Spec(id: "dis_limit", board: .dis, register: Nb.Register.speedLimit, readLen: 2, category: .limit),
        Spec(id: "dis_rated", board: .dis, register: Nb.Register.ratedSpeed, readLen: 2, category: .limit),
        Spec(id: "mcu_max", board: .mcu, register: Nb.Register.mcuMaxSpeed, readLen: 2, category: .limit),
        Spec(id: "mcu_safe", board: .mcu, register: Nb.Register.speedSafeLock, readLen: 2, category: .limit),
        Spec(id: "mcu_gear", board: .mcu, register: Nb.Register.gearTopSpeed, readLen: 2, category: .limit),
    ]

    private static let historyFields: [Spec] = [
        Spec(id: "dis_trip_max", board: .dis, register: Nb.Register.tripMaxSpeed, readLen: 2, category: .history),
        Spec(id: "dis_trip_avg", board: .dis, register: Nb.Register.averageSpeed, readLen: 2, category: .history),
        Spec(id: "dis_speed", board: .dis, register: Nb.Register.currentSpeed, readLen: 2, category: .history),
        Spec(id: "dis_range", board: .dis, register: Nb.Register.remainingRange, readLen: 2, category: .history),
        Spec(id: "dis_odo", board: .dis, register: Nb.Register.odometer, readLen: 4, category: .history),
        Spec(id: "dis_trip_km", board: .dis, register: Nb.Register.tripDistance, readLen: 2, category: .history),
        Spec(id: "dis_trip_time", board: .dis, register: Nb.Register.tripTime, readLen: 2, category: .history),
    ]

    private static let firmwareFields: [Spec] = [
        Spec(id: "dis_fw", board: .dis, register: Nb.Register.disVersion, readLen: 2, category: .firmware),
        Spec(id: "dis_mcu_fw", board: .dis, register: Nb.Register.mcuVersion, readLen: 2, category: .firmware),
        Spec(id: "dis_ecu_fw", board: .dis, register: Nb.Register.ecuVersion, readLen: 2, category: .firmware),
        Spec(id: "ble_fw", board: .ble, register: Nb.Register.bleVersion, readLen: 2, category: .firmware),
        Spec(id: "mcu_fw", board: .mcu, register: Nb.Register.disVersion, readLen: 2, category: .firmware),
        Spec(id: "bms_fw", board: .bms, register: Nb.Register.disVersion, readLen: 2, category: .firmware),
        Spec(id: "vcu_fw", board: .vcu, register: Nb.Register.disVersion, readLen: 2, category: .firmware),
    ]

    /// Max G3: Board-/Register-Map laut öffentlichem G3-Flasher (+ 4-Byte-VCU-Versuch).
    private static let g3FirmwareFields: [Spec] = [
        Spec(id: "g3_ble_fw", board: .ble, register: Nb.G3Register.bleVersion, readLen: 2, category: .firmware),
        Spec(id: "g3_vcu_fw", board: .vcuG3, register: Nb.G3Register.vcuVersion, readLen: 2, category: .firmware),
        Spec(id: "g3_vcu_fw4", board: .vcuG3, register: Nb.G3Register.vcuVersion, readLen: 4, category: .firmware),
        Spec(id: "g3_mcu_fw", board: .mcuG3, register: Nb.G3Register.mcuVersion, readLen: 2, category: .firmware),
        Spec(id: "g3_mcu_fw_fb", board: .vcuG3, register: Nb.G3Register.mcuVersionFallback, readLen: 2, category: .firmware),
        Spec(id: "g3_bms_fw", board: .vcuG3, register: Nb.G3Register.bmsVersion, readLen: 2, category: .firmware),
    ]

    private static let batteryFields: [Spec] = [
        Spec(id: "dis_battery", board: .dis, register: Nb.Register.batteryPercent, readLen: 2, category: .battery),
        Spec(id: "bms_voltage", board: .bms, register: Nb.Register.bmsVoltage, readLen: 2, category: .battery),
        Spec(id: "bms_cycles", board: .bms, register: Nb.Register.cycleCount, readLen: 2, category: .battery),
        Spec(id: "bms_soc", board: .bms, register: Nb.Register.bmsSoc, readLen: 2, category: .battery),
        Spec(id: "bms_remain", board: .bms, register: Nb.Register.remainCapacity, readLen: 2, category: .battery),
        Spec(id: "bms_design", board: .bms, register: Nb.Register.designCapacity, readLen: 2, category: .battery),
        Spec(id: "dis_power", board: .dis, register: Nb.Register.power, readLen: 2, category: .battery),
    ]

    private static let statusFields: [Spec] = [
        Spec(id: "dis_error", board: .dis, register: Nb.Register.error, readLen: 2, category: .status),
        Spec(id: "dis_alarm", board: .dis, register: Nb.Register.alarm, readLen: 2, category: .status),
        Spec(id: "mcu_motor_temp", board: .mcu, register: Nb.Register.motorTemp, readLen: 2, category: .status),
        Spec(id: "mcu_ctrl_temp", board: .mcu, register: Nb.Register.controllerTemp, readLen: 2, category: .status),
    ]

    // MARK: - Decode

    static func decode(spec: Spec, data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        switch spec.id {
        case "dis_sn", "ble_sn", "vcu_sn", "mcu_sn", "bms_sn", "mcu_g3_sn", "vcu_g3_sn", "bms_g3_sn":
            return Nb.asciiString(data)

        case "dis_limit", "mcu_max", "mcu_safe", "mcu_gear",
             "vcu_g3_limit", "vcu_g3_safe", "vcu_g3_max", "vcu_g3_gear",
             "mcu_g3_limit", "mcu_g3_max", "mcu_g3_safe", "mcu_g3_gear",
             "vcu_g3_cfg", "vcu_g3_g1", "vcu_g3_g2":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.kmh.format(Optional(RegisterScale.kmhWhole(raw)))

        case "dis_rated", "dis_trip_max", "dis_trip_avg", "dis_speed",
             "vcu_g3_rated", "vcu_g3_trip_max", "vcu_g3_speed",
             "mcu_g3_rated":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.kmh.format(Optional(RegisterScale.kmh(raw)))

        case "dis_range", "vcu_g3_range":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.km.format(Optional(RegisterScale.rangeKm(raw)))

        case "dis_odo", "vcu_g3_odo", "tft_odo", "mcu_g3_odo":
            return Format.km.format(plausibleOdometerKm(data))

        case "dis_trip_km", "vcu_g3_trip_km":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.km.format(Optional(RegisterScale.tripKm(raw)))

        case "dis_trip4", "vcu_g3_trip4", "tft_trip4":
            return Format.km.format(plausibleOdometerKm(data))

        case "dis_trip_time":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.minutes.format(Int(RegisterScale.minutesFromSeconds(raw).rounded()))

        case "dis_fw", "dis_mcu_fw", "dis_ecu_fw", "ble_fw", "mcu_fw", "bms_fw", "vcu_fw",
             "g3_ble_fw", "g3_vcu_fw", "g3_mcu_fw", "g3_mcu_fw_fb":
            guard let raw = Nb.u16(data) else { return nil }
            return RegisterScale.firmware(raw)

        case "g3_bms_fw":
            guard let raw = Nb.u16(data) else { return nil }
            return RegisterScale.firmwareFourNibbles(raw)

        case "g3_vcu_fw4":
            return RegisterScale.firmwareBytes(data)

        case "dis_battery", "bms_soc", "vcu_g3_battery", "bms_g3_soc":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.num.format(Int(raw)) + " %"

        case "bms_voltage", "bms_g3_voltage":
            guard let raw = Nb.u16(data) else { return nil }
            return String(format: "%.2f V", RegisterScale.volts(raw))

        case "bms_cycles", "bms_remain", "bms_design", "bms_g3_cycles":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.num.format(Int(raw))

        case "dis_power":
            guard let raw = Nb.i16(data) else { return nil }
            return String(format: "%.0f W", Double(raw))

        case "dis_error", "dis_alarm", "vcu_g3_error", "vcu_g3_alarm", "mcu_g3_error",
             "vcu_g3_flag_a":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.code.format("0x\(String(format: "%04X", raw))")

        case "vcu_g3_flag_b":
            return Nb.hex(data)

        case "mcu_motor_temp", "mcu_ctrl_temp":
            guard let raw = Nb.i16(data) else { return nil }
            return String(format: "%.1f °C", RegisterScale.celsius(raw))

        default:
            return Nb.hex(data)
        }
    }

    // MARK: - Apply into IntegrityReading

    static func apply(spec: Spec, data: Data, into reading: inout IntegrityReading) {
        let decoded = decode(spec: spec, data: data)
        let raw = RawRegister(
            address: spec.key,
            index: Int(spec.register),
            name: spec.id,
            valueHex: Nb.hex(data),
            valueDecoded: decoded
        )
        reading.rawRegisters.append(raw)

        switch spec.id {
        case "dis_sn":
            if let sn = Nb.asciiString(data), looksLikeVehicleSerial(sn) {
                reading.serialDisplay = sn
            }
        case "ble_sn":
            reading.serialBle = Nb.asciiString(data)
        case "vcu_sn", "vcu_g3_sn":
            if let sn = Nb.asciiString(data) {
                reading.serialVcu = sn
                // Max G3: VCU-SN ist die Fahrzeug-SN.
                if looksLikeVehicleSerial(sn) {
                    reading.serialDisplay = reading.serialDisplay ?? sn
                    reading.serialExpected = reading.serialExpected ?? sn
                }
            }
        case "mcu_sn", "mcu_g3_sn":
            reading.serialMcu = Nb.asciiString(data)
        case "bms_sn", "bms_g3_sn":
            reading.serialBms = Nb.asciiString(data)

        case "dis_limit", "vcu_g3_limit", "mcu_g3_limit":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                // 0 oft „kein Soft-Limit“ / leeres Register — nicht als Peak werten.
                if kmh > 0 {
                    reading.speedLimitKmh = max(reading.speedLimitKmh ?? 0, kmh)
                    reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
                    markSoftUnlockIfNeeded(kmh: kmh, into: &reading)
                }
            }

        case "dis_rated", "vcu_g3_rated", "mcu_g3_rated":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmh(raw)
                if kmh > 0 {
                    reading.speedRatedKmh = max(reading.speedRatedKmh ?? 0, kmh)
                    reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
                    markSoftUnlockIfNeeded(kmh: kmh, into: &reading)
                }
            }

        case "dis_trip_max", "vcu_g3_trip_max":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmh(raw)
                if kmh > 0 {
                    reading.speedMaxKmh = max(reading.speedMaxKmh ?? 0, kmh)
                    reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
                }
            }

        case "dis_trip_avg":
            if let raw = Nb.u16(data) { _ = RegisterScale.kmh(raw) }

        case "dis_speed", "vcu_g3_speed":
            if let raw = Nb.u16(data) { reading.speedCurrentKmh = RegisterScale.kmh(raw) }

        case "dis_range", "vcu_g3_range":
            if let raw = Nb.u16(data) { reading.remainKm = RegisterScale.rangeKm(raw) }

        case "dis_odo", "vcu_g3_odo", "tft_odo", "mcu_g3_odo":
            if let km = plausibleOdometerKm(data) {
                reading.odometerKm = max(reading.odometerKm ?? 0, km)
            }

        case "dis_trip_km", "vcu_g3_trip_km":
            if let raw = Nb.u16(data) { reading.tripKm = RegisterScale.tripKm(raw) }

        case "dis_trip4", "vcu_g3_trip4", "tft_trip4":
            if let km = plausibleOdometerKm(data) {
                reading.tripKm = max(reading.tripKm ?? 0, km)
            }

        case "dis_trip_time":
            if let raw = Nb.u16(data) {
                reading.rideTimeMinutes = Int(RegisterScale.minutesFromSeconds(raw).rounded())
            }

        case "mcu_max", "vcu_g3_max", "mcu_g3_max", "vcu_g3_gear", "mcu_g3_gear", "mcu_gear",
             "vcu_g3_g1", "vcu_g3_g2":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                if kmh > 0 && kmh < 120 {
                    reading.speedMaxKmh = max(reading.speedMaxKmh ?? 0, kmh)
                    reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
                    markSoftUnlockIfNeeded(kmh: kmh, into: &reading)
                }
            }

        case "mcu_safe", "vcu_g3_safe", "mcu_g3_safe":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                // SafeLock: >0 oft aktiv; 0 = offen / Soft-Unlock-Hinweis.
                reading.safeLockActive = kmh > 0
                if kmh > 0 && kmh < 120 {
                    reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
                }
            }

        case "vcu_g3_cfg":
            if let raw = Nb.u16(data), raw > 1 {
                // Erweiterter Fahrmodus / Config — Hinweis auf Soft-Unlock.
                reading.gearMax = max(reading.gearMax ?? 1, Int(raw))
                if raw >= 2 { reading.hiddenTuningDetected = reading.hiddenTuningDetected ?? true }
            }

        case "dis_fw":
            if let raw = Nb.u16(data) { reading.fwEsc = RegisterScale.firmware(raw) }

        case "dis_mcu_fw", "mcu_fw", "g3_mcu_fw", "g3_mcu_fw_fb":
            if let raw = Nb.u16(data) { reading.fwMcu = RegisterScale.firmware(raw) }

        case "dis_ecu_fw":
            if let raw = Nb.u16(data) { reading.fwEsc = RegisterScale.firmware(raw) }

        case "ble_fw", "g3_ble_fw":
            if let raw = Nb.u16(data) { reading.fwBle = RegisterScale.firmware(raw) }

        case "bms_fw":
            if let raw = Nb.u16(data) { reading.fwBms = RegisterScale.firmware(raw) }

        case "g3_bms_fw":
            if let raw = Nb.u16(data) { reading.fwBms = RegisterScale.firmwareFourNibbles(raw) }

        case "vcu_fw", "g3_vcu_fw":
            if let raw = Nb.u16(data) { reading.fwVcu = RegisterScale.firmware(raw) }

        case "g3_vcu_fw4":
            if let ver = RegisterScale.firmwareBytes(data) { reading.fwVcu = ver }

        case "dis_error", "vcu_g3_error", "mcu_g3_error":
            if let raw = Nb.u16(data) {
                reading.errorCode = String(format: "0x%04X", raw)
                reading.errorActive = raw != 0
            }

        case "dis_alarm", "vcu_g3_alarm":
            if let raw = Nb.u16(data) {
                reading.alarmCode = String(format: "0x%04X", raw)
            }

        case "dis_battery", "vcu_g3_battery":
            if let raw = Nb.u16(data) { reading.batteryPercent = Int(raw) }

        case "bms_voltage", "bms_g3_voltage":
            if let raw = Nb.u16(data) { reading.batteryVoltage = RegisterScale.volts(raw) }

        case "bms_cycles", "bms_g3_cycles":
            if let raw = Nb.u16(data) { reading.chargeCycles = Int(raw) }

        case "bms_soc", "bms_g3_soc":
            if let raw = Nb.u16(data) { reading.batteryPercent = reading.batteryPercent ?? Int(raw) }

        case "dis_power":
            if let raw = Nb.i16(data) { reading.batteryCurrent = Double(raw) / 100.0 }

        case "mcu_motor_temp":
            if let raw = Nb.i16(data) { reading.motorTempC = RegisterScale.celsius(raw) }

        case "mcu_ctrl_temp":
            if let raw = Nb.i16(data) { reading.mcuTempC = RegisterScale.celsius(raw) }

        default:
            break
        }
    }

    /// Fahrzeug-SN (z. B. 1CGB…) vs. Modul-/MCU-Hardware-IDs (Z07…, Hex-MAC).
    private static func looksLikeVehicleSerial(_ value: String) -> Bool {
        let sn = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard sn.count >= 10 else { return false }
        if sn.hasPrefix("1CG") || sn.hasPrefix("N4G") || sn.hasPrefix("N2") { return true }
        // Alphanumerisch, beginnt mit Ziffer → oft Fahrzeug-ID
        if sn.first?.isNumber == true, sn.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return true
        }
        return false
    }

    /// Odometer: BLE oft 0.001 km (Meter). Manche Boards liefern mm — plausibelste Skala wählen.
    private static func plausibleOdometerKm(_ data: Data) -> Double? {
        guard let raw = Nb.u32(data), raw > 0 else { return nil }
        let asMetres = Double(raw) / 1000.0          // 0.001 km units
        let asMillimetres = Double(raw) / 1_000_000.0
        // Typischer Scooter: 0…50 000 km
        if asMetres > 0, asMetres < 50_000 { return asMetres }
        if asMillimetres > 0, asMillimetres < 50_000 { return asMillimetres }
        if asMetres < 500_000 { return asMetres }
        return nil
    }

    private static func markSoftUnlockIfNeeded(kmh: Double, into reading: inout IntegrityReading) {
        guard SoftUnlockSettings.isEnabledSnapshot() else { return }
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        if kmh >= threshold {
            reading.hiddenTuningDetected = true
        }
    }

    static func fields(for category: Category) -> [Spec] {
        fields.filter { $0.category == category }
    }
}

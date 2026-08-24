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

    // MARK: - Display (DIS 0x01)

    private static let identityFields: [Spec] = [
        Spec(id: "dis_sn", board: .dis, register: Nb.Register.serialNumber.rawValue, readLen: 14, category: .identity),
        Spec(id: "ble_sn", board: .ble, register: Nb.Register.serialNumber.rawValue, readLen: 14, category: .identity),
        Spec(id: "vcu_sn", board: .vcu, register: Nb.Register.serialNumber.rawValue, readLen: 14, category: .identity),
        Spec(id: "mcu_sn", board: .mcu, register: Nb.Register.serialNumber.rawValue, readLen: 14, category: .identity),
        Spec(id: "bms_sn", board: .bms, register: Nb.Register.serialNumber.rawValue, readLen: 14, category: .identity),
    ]

    private static let limitFields: [Spec] = [
        Spec(id: "dis_limit", board: .dis, register: Nb.Register.speedLimit.rawValue, readLen: 2, category: .limit),
        Spec(id: "dis_rated", board: .dis, register: Nb.Register.ratedSpeed.rawValue, readLen: 2, category: .limit),
        Spec(id: "mcu_max", board: .mcu, register: Nb.Register.mcuMaxSpeed.rawValue, readLen: 2, category: .limit),
        Spec(id: "mcu_safe", board: .mcu, register: Nb.Register.speedSafeLock.rawValue, readLen: 2, category: .limit),
        Spec(id: "mcu_gear", board: .mcu, register: Nb.Register.gearTopSpeed.rawValue, readLen: 2, category: .limit),
    ]

    private static let historyFields: [Spec] = [
        Spec(id: "dis_trip_max", board: .dis, register: Nb.Register.tripMaxSpeed.rawValue, readLen: 2, category: .history),
        Spec(id: "dis_trip_avg", board: .dis, register: Nb.Register.averageSpeed.rawValue, readLen: 2, category: .history),
        Spec(id: "dis_speed", board: .dis, register: Nb.Register.currentSpeed.rawValue, readLen: 2, category: .history),
        Spec(id: "dis_range", board: .dis, register: Nb.Register.remainingRange.rawValue, readLen: 2, category: .history),
        Spec(id: "dis_odo", board: .dis, register: Nb.Register.odometer.rawValue, readLen: 4, category: .history),
        Spec(id: "dis_trip_km", board: .dis, register: Nb.Register.tripDistance.rawValue, readLen: 2, category: .history),
        Spec(id: "dis_trip_time", board: .dis, register: Nb.Register.tripTime.rawValue, readLen: 2, category: .history),
    ]

    private static let firmwareFields: [Spec] = [
        Spec(id: "dis_fw", board: .dis, register: Nb.Register.disVersion.rawValue, readLen: 2, category: .firmware),
        Spec(id: "dis_mcu_fw", board: .dis, register: Nb.Register.mcuVersion.rawValue, readLen: 2, category: .firmware),
        Spec(id: "dis_ecu_fw", board: .dis, register: Nb.Register.ecuVersion.rawValue, readLen: 2, category: .firmware),
        Spec(id: "ble_fw", board: .ble, register: Nb.Register.bleVersion.rawValue, readLen: 2, category: .firmware),
        Spec(id: "mcu_fw", board: .mcu, register: Nb.Register.disVersion.rawValue, readLen: 2, category: .firmware),
        Spec(id: "bms_fw", board: .bms, register: Nb.Register.disVersion.rawValue, readLen: 2, category: .firmware),
        Spec(id: "vcu_fw", board: .vcu, register: Nb.Register.disVersion.rawValue, readLen: 2, category: .firmware),
    ]

    private static let batteryFields: [Spec] = [
        Spec(id: "dis_battery", board: .dis, register: Nb.Register.batteryPercent.rawValue, readLen: 2, category: .battery),
        Spec(id: "bms_voltage", board: .bms, register: Nb.Register.bmsVoltage.rawValue, readLen: 2, category: .battery),
        Spec(id: "bms_cycles", board: .bms, register: Nb.Register.cycleCount.rawValue, readLen: 2, category: .battery),
        Spec(id: "bms_soc", board: .bms, register: Nb.Register.bmsSoc.rawValue, readLen: 2, category: .battery),
        Spec(id: "bms_remain", board: .bms, register: Nb.Register.remainCapacity.rawValue, readLen: 2, category: .battery),
        Spec(id: "bms_design", board: .bms, register: Nb.Register.designCapacity.rawValue, readLen: 2, category: .battery),
        Spec(id: "dis_power", board: .dis, register: Nb.Register.power.rawValue, readLen: 2, category: .battery),
    ]

    private static let statusFields: [Spec] = [
        Spec(id: "dis_error", board: .dis, register: Nb.Register.error.rawValue, readLen: 2, category: .status),
        Spec(id: "dis_alarm", board: .dis, register: Nb.Register.alarm.rawValue, readLen: 2, category: .status),
        Spec(id: "mcu_motor_temp", board: .mcu, register: Nb.Register.motorTemp.rawValue, readLen: 2, category: .status),
        Spec(id: "mcu_ctrl_temp", board: .mcu, register: Nb.Register.controllerTemp.rawValue, readLen: 2, category: .status),
    ]

    // MARK: - Decode

    static func decode(spec: Spec, data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        switch spec.id {
        case "dis_sn", "ble_sn", "vcu_sn", "mcu_sn", "bms_sn":
            return Nb.asciiString(data)

        case "dis_limit", "mcu_max", "mcu_safe", "mcu_gear":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.kmh.format(Optional(RegisterScale.kmhWhole(raw)))

        case "dis_rated", "dis_trip_max", "dis_trip_avg", "dis_speed":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.kmh.format(Optional(RegisterScale.kmh(raw)))

        case "dis_range":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.km.format(Optional(RegisterScale.rangeKm(raw)))

        case "dis_odo":
            guard let raw = Nb.u32(data) else { return nil }
            return Format.km.format(Optional(RegisterScale.km(raw)))

        case "dis_trip_km":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.km.format(Optional(RegisterScale.tripKm(raw)))

        case "dis_trip_time":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.minutes.format(Int(RegisterScale.minutesFromSeconds(raw).rounded()))

        case "dis_fw", "dis_mcu_fw", "dis_ecu_fw", "ble_fw", "mcu_fw", "bms_fw", "vcu_fw":
            guard let raw = Nb.u16(data) else { return nil }
            return RegisterScale.firmware(raw)

        case "dis_battery", "bms_soc":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.num.format(Int(raw)) + " %"

        case "bms_voltage":
            guard let raw = Nb.u16(data) else { return nil }
            return String(format: "%.2f V", RegisterScale.volts(raw))

        case "bms_cycles", "bms_remain", "bms_design":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.num.format(Int(raw))

        case "dis_power":
            guard let raw = Nb.i16(data) else { return nil }
            return String(format: "%.0f W", Double(raw))

        case "dis_error", "dis_alarm":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.code.format("0x\(String(format: "%04X", raw))")

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
            reading.serialDisplay = Nb.asciiString(data)
        case "ble_sn":
            reading.serialBle = Nb.asciiString(data)
        case "vcu_sn":
            reading.serialVcu = Nb.asciiString(data)
        case "mcu_sn":
            reading.serialMcu = Nb.asciiString(data)
        case "bms_sn":
            reading.serialBms = Nb.asciiString(data)

        case "dis_limit":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                reading.speedLimitKmh = kmh
                reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
            }

        case "dis_rated":
            if let raw = Nb.u16(data) { reading.speedRatedKmh = RegisterScale.kmh(raw) }

        case "dis_trip_max":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmh(raw)
                reading.speedMaxKmh = kmh
                reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
            }

        case "dis_trip_avg":
            if let raw = Nb.u16(data) { _ = RegisterScale.kmh(raw) }

        case "dis_speed":
            if let raw = Nb.u16(data) { reading.speedCurrentKmh = RegisterScale.kmh(raw) }

        case "dis_range":
            if let raw = Nb.u16(data) { reading.remainKm = RegisterScale.rangeKm(raw) }

        case "dis_odo":
            if let raw = Nb.u32(data) { reading.odometerKm = RegisterScale.km(raw) }

        case "dis_trip_km":
            if let raw = Nb.u16(data) { reading.tripKm = RegisterScale.tripKm(raw) }

        case "dis_trip_time":
            if let raw = Nb.u16(data) {
                reading.rideTimeMinutes = Int(RegisterScale.minutesFromSeconds(raw).rounded())
            }

        case "mcu_max":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                reading.gearMax = Int(kmh)
                reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
            }

        case "mcu_safe":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                reading.safeLockActive = kmh > 0
                reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
            }

        case "mcu_gear":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmhWhole(raw)
                reading.gearMax = Int(kmh)
                reading.peakSpeedKmh = max(reading.peakSpeedKmh ?? 0, kmh)
            }

        case "dis_fw":
            if let raw = Nb.u16(data) { reading.fwEsc = RegisterScale.firmware(raw) }

        case "dis_mcu_fw", "mcu_fw":
            if let raw = Nb.u16(data) { reading.fwMcu = RegisterScale.firmware(raw) }

        case "dis_ecu_fw":
            if let raw = Nb.u16(data) { reading.fwEsc = RegisterScale.firmware(raw) }

        case "ble_fw":
            if let raw = Nb.u16(data) { reading.fwBle = RegisterScale.firmware(raw) }

        case "bms_fw":
            if let raw = Nb.u16(data) { reading.fwBms = RegisterScale.firmware(raw) }

        case "vcu_fw":
            if let raw = Nb.u16(data) { reading.fwVcu = RegisterScale.firmware(raw) }

        case "dis_error":
            if let raw = Nb.u16(data) {
                reading.errorCode = String(format: "0x%04X", raw)
                reading.errorActive = raw != 0
            }

        case "dis_alarm":
            if let raw = Nb.u16(data) {
                reading.alarmCode = String(format: "0x%04X", raw)
            }

        case "dis_battery":
            if let raw = Nb.u16(data) { reading.batteryPercent = Int(raw) }

        case "bms_voltage":
            if let raw = Nb.u16(data) { reading.batteryVoltage = RegisterScale.volts(raw) }

        case "bms_cycles":
            if let raw = Nb.u16(data) { reading.chargeCycles = Int(raw) }

        case "bms_soc":
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

    static func fields(for category: Category) -> [Spec] {
        fields.filter { $0.category == category }
    }
}

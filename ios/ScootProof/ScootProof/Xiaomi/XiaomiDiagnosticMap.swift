import Foundation

/// Read-only register map for Xiaomi classic BLE (55 AA).
enum XiaomiDiagnosticMap {
    struct Spec: Hashable {
        let id: String
        let board: Xiaomi.Board
        let register: UInt8
        let readLen: Int

        var key: String {
            "xm-\(String(format: "%02X", board.rawValue))-\(String(format: "%02X", register))"
        }
    }

    static let fields: [Spec] = [
        // Identity
        Spec(id: "esc_sn", board: .esc, register: Xiaomi.Register.serialNumber, readLen: 14),
        Spec(id: "ble_sn", board: .ble, register: Xiaomi.Register.serialNumber, readLen: 14),
        Spec(id: "bms_sn", board: .bms, register: Xiaomi.Register.serialNumber, readLen: 14),

        // Limits / speed
        Spec(id: "esc_limit", board: .esc, register: Xiaomi.Register.speedLimit, readLen: 2),
        Spec(id: "esc_speed", board: .esc, register: Xiaomi.Register.currentSpeed, readLen: 2),
        Spec(id: "esc_avg", board: .esc, register: Xiaomi.Register.averageSpeed, readLen: 2),
        Spec(id: "esc_trip_max", board: .esc, register: Xiaomi.Register.tripMaxSpeed, readLen: 2),

        // History
        Spec(id: "esc_odo", board: .esc, register: Xiaomi.Register.totalMileage, readLen: 4),
        Spec(id: "esc_trip", board: .esc, register: Xiaomi.Register.tripDistance, readLen: 2),
        Spec(id: "esc_range", board: .esc, register: Xiaomi.Register.remainingRange, readLen: 2),
        Spec(id: "esc_trip_time", board: .esc, register: Xiaomi.Register.tripTime, readLen: 2),

        // Firmware
        Spec(id: "esc_fw", board: .esc, register: Xiaomi.Register.firmware, readLen: 2),
        Spec(id: "ble_fw", board: .ble, register: Xiaomi.Register.firmware, readLen: 2),
        Spec(id: "bms_fw", board: .bms, register: Xiaomi.Register.bmsFirmware, readLen: 2),

        // Battery
        Spec(id: "esc_battery", board: .esc, register: Xiaomi.Register.batteryPercent, readLen: 2),
        Spec(id: "bms_voltage", board: .bms, register: Xiaomi.Register.voltage, readLen: 2),
        Spec(id: "bms_cycles", board: .bms, register: Xiaomi.Register.cycleCount, readLen: 2),
        Spec(id: "bms_remain", board: .bms, register: Xiaomi.Register.remainCapacity, readLen: 2),
        Spec(id: "bms_design", board: .bms, register: Xiaomi.Register.designCapacity, readLen: 2),

        // Status
        Spec(id: "esc_error", board: .esc, register: Xiaomi.Register.error, readLen: 2),
        Spec(id: "esc_motor_temp", board: .esc, register: Xiaomi.Register.motorTemp, readLen: 2),
        Spec(id: "esc_frame_temp", board: .esc, register: Xiaomi.Register.frameTemp, readLen: 2),
        Spec(id: "esc_lock", board: .esc, register: Xiaomi.Register.lockStatus, readLen: 2),
    ]

    static func decode(spec: Spec, data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        switch spec.id {
        case "esc_sn", "ble_sn", "bms_sn":
            return Nb.asciiString(data)
        case "esc_limit", "esc_speed", "esc_avg", "esc_trip_max":
            guard let raw = Nb.u16(data) else { return nil }
            // Xiaomi often stores 0.1 km/h; limit register may be whole km/h.
            if spec.id == "esc_limit" {
                return Format.kmh.format(Optional(RegisterScale.kmhWhole(raw)))
            }
            return Format.kmh.format(Optional(RegisterScale.kmh(raw)))
        case "esc_odo":
            guard let raw = Nb.u32(data) else { return nil }
            // Total mileage typically in metres on Xiaomi ESC.
            return Format.km.format(Optional(Double(raw) / 1000.0))
        case "esc_trip", "esc_range":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.km.format(Optional(Double(raw) / 100.0))
        case "esc_trip_time":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.minutes.format(Int(Double(raw) / 60.0))
        case "esc_fw", "ble_fw", "bms_fw":
            guard let raw = Nb.u16(data) else { return nil }
            return RegisterScale.firmware(raw)
        case "esc_battery":
            guard let raw = Nb.u16(data) else { return nil }
            return "\(Int(raw)) %"
        case "bms_voltage":
            guard let raw = Nb.u16(data) else { return nil }
            return String(format: "%.2f V", RegisterScale.volts(raw))
        case "bms_cycles", "bms_remain", "bms_design":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.num.format(Int(raw))
        case "esc_error", "esc_lock":
            guard let raw = Nb.u16(data) else { return nil }
            return Format.code.format("0x\(String(format: "%04X", raw))")
        case "esc_motor_temp", "esc_frame_temp":
            guard let raw = Nb.i16(data) else { return nil }
            return String(format: "%.1f °C", RegisterScale.celsius(raw))
        default:
            return Nb.hex(data)
        }
    }

    static func apply(spec: Spec, data: Data, into reading: inout IntegrityReading) {
        let decoded = decode(spec: spec, data: data)
        reading.rawRegisters.append(
            RawRegister(
                address: spec.key,
                index: Int(spec.register),
                name: spec.id,
                valueHex: Nb.hex(data),
                valueDecoded: decoded
            )
        )

        switch spec.id {
        case "esc_sn":
            reading.serialDisplay = Nb.asciiString(data)
        case "ble_sn":
            reading.serialBle = Nb.asciiString(data)
        case "bms_sn":
            reading.serialBms = Nb.asciiString(data)
        case "esc_limit":
            if let raw = Nb.u16(data) { reading.speedLimitKmh = RegisterScale.kmhWhole(raw) }
        case "esc_speed":
            if let raw = Nb.u16(data) { reading.speedCurrentKmh = RegisterScale.kmh(raw) }
        case "esc_avg":
            break
        case "esc_trip_max":
            if let raw = Nb.u16(data) { reading.peakSpeedKmh = RegisterScale.kmh(raw) }
        case "esc_odo":
            if let raw = Nb.u32(data) { reading.odometerKm = Double(raw) / 1000.0 }
        case "esc_trip":
            if let raw = Nb.u16(data) { reading.tripKm = Double(raw) / 100.0 }
        case "esc_range":
            if let raw = Nb.u16(data) { reading.remainKm = Double(raw) / 100.0 }
        case "esc_trip_time":
            if let raw = Nb.u16(data) { reading.rideTimeMinutes = Int(Double(raw) / 60.0) }
        case "esc_fw":
            if let raw = Nb.u16(data) { reading.fwEsc = RegisterScale.firmware(raw) }
        case "ble_fw":
            if let raw = Nb.u16(data) { reading.fwBle = RegisterScale.firmware(raw) }
        case "bms_fw":
            if let raw = Nb.u16(data) { reading.fwBms = RegisterScale.firmware(raw) }
        case "esc_battery":
            if let raw = Nb.u16(data) { reading.batteryPercent = Int(raw) }
        case "bms_voltage":
            if let raw = Nb.u16(data) { reading.batteryVoltage = RegisterScale.volts(raw) }
        case "bms_cycles":
            if let raw = Nb.u16(data) { reading.chargeCycles = Int(raw) }
        case "esc_error":
            if let raw = Nb.u16(data) {
                reading.errorCode = String(format: "0x%04X", raw)
                reading.errorActive = raw != 0
            }
        case "esc_motor_temp":
            if let raw = Nb.i16(data) { reading.motorTempC = RegisterScale.celsius(raw) }
        case "esc_frame_temp":
            if let raw = Nb.i16(data) { reading.mcuTempC = RegisterScale.celsius(raw) }
        case "esc_lock":
            if let raw = Nb.u16(data) { reading.safeLockActive = raw != 0 }
        default:
            break
        }
    }
}

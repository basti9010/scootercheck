import Foundation

/// Kontinuierlich gepollte Livedaten — DarknessBot-Parität für KickScooter (ohne EUC PWM/Pitch).
struct LiveTelemetrySnapshot: Equatable, Sendable {
    var updatedAt: Date = Date()
    var speedKmh: Double?
    var batteryPercent: Int?
    var voltageV: Double?
    var currentA: Double?
    var powerW: Double?
    var remainKm: Double?
    var tripKm: Double?
    var tripMinutes: Int?
    var controllerTempC: Double?
    var batteryTempC: Double?
    var rawRegisterCount: Int = 0

    var hasAnyValue: Bool {
        speedKmh != nil || batteryPercent != nil || voltageV != nil || currentA != nil
            || powerW != nil || remainKm != nil || controllerTempC != nil || batteryTempC != nil
    }

    mutating func apply(spec: DiagnosticMap.Spec, data: Data) {
        switch spec.id {
        case "vcu_g3_speed", "dis_speed":
            if let raw = Nb.u16(data) {
                let kmh = RegisterScale.kmh(raw)
                if kmh >= 0, kmh < 120 { speedKmh = kmh }
                else if let packed = RegisterScale.g3StoredSpeedKmh(raw) { speedKmh = packed }
            }
        case "vcu_g3_battery", "dis_battery":
            if let raw = Nb.u16(data) { batteryPercent = Int(raw) }
        case "bms_g3_voltage", "bms_voltage":
            if let raw = Nb.u16(data) { voltageV = RegisterScale.volts(raw) }
        case "bms_g3_current":
            if let raw = Nb.i16(data) { currentA = Double(raw) / 100.0 }
        case "dis_power":
            if let raw = Nb.i16(data) { powerW = abs(Double(raw)) }
        case "vcu_g3_remain", "dis_range":
            if let raw = Nb.u16(data) { remainKm = RegisterScale.rangeKm(raw) }
        case "vcu_g3_trip":
            if let raw = Nb.u16(data) { tripKm = RegisterScale.g3TripMileageKm(raw) }
        case "vcu_g3_runtime_trip", "vcu_g3_ridetime_trip", "dis_trip_time":
            if let raw = Nb.u16(data) {
                tripMinutes = Int(RegisterScale.minutesFromSeconds(raw).rounded())
            }
        case "vcu_g3_bodytemp", "mcu_ctrl_temp":
            if let raw = Nb.i16(data) { controllerTempC = RegisterScale.celsius(raw) }
        case "bms_g3_temp":
            if let t = DiagnosticMap.decodeBmsTempC(data) { batteryTempC = t }
        default:
            break
        }
        if let v = voltageV, let a = currentA {
            let w = abs(v * a)
            if w > 0, w < 5000 { powerW = w }
        }
        rawRegisterCount += 1
        updatedAt = Date()
    }
}

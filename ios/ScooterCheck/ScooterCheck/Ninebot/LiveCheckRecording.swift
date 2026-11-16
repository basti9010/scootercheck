import Foundation

/// Ein Abtastpunkt der LiveCheck-Session (1 Hz typisch).
struct LiveCheckSample: Codable, Hashable, Sendable {
    var at: Date
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

    init(at: Date = Date(), from snap: LiveTelemetrySnapshot) {
        self.at = at
        self.speedKmh = snap.speedKmh
        self.batteryPercent = snap.batteryPercent
        self.voltageV = snap.voltageV
        self.currentA = snap.currentA
        self.powerW = snap.powerW
        self.remainKm = snap.remainKm
        self.tripKm = snap.tripKm
        self.tripMinutes = snap.tripMinutes
        self.controllerTempC = snap.controllerTempC
        self.batteryTempC = snap.batteryTempC
    }
}

/// Ereignis in der LiveCheck-Timeline (neuer Peak oder Schwellenüberschreitung).
struct LiveCheckEvent: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case newPeakSpeed
        case newPeakPower
        case newPeakControllerTemp
        case newPeakBatteryTemp
        case thresholdSpeed
        case thresholdPower
        case thresholdControllerTemp
        case thresholdBatteryTemp
    }

    var id: UUID
    var at: Date
    var kind: Kind
    var value: Double
    var threshold: Double?
    var message: String

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        kind: Kind,
        value: Double,
        threshold: Double? = nil,
        message: String
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.value = value
        self.threshold = threshold
        self.message = message
    }

    var isAlarm: Bool {
        switch kind {
        case .thresholdSpeed, .thresholdPower, .thresholdControllerTemp, .thresholdBatteryTemp:
            return true
        default:
            return false
        }
    }
}

/// Forensische Live-Aufzeichnung bis Stop — speicherbar als JSON/CSV an der Prüfung.
struct LiveCheckRecording: Codable, Hashable, Identifiable, Sendable {
    /// Anzeige-/Alarm-Schwellen (nur Hinweise, nicht bewertungsrelevant für das Protokollurteil).
    enum Thresholds {
        static let speedWarnKmh: Double = 25
        static let powerWarnW: Double = 1_200
        /// Gleiche Soft-/Hard-Grenzen wie Temperatur-Facts im Analyzer.
        static let tempWarnC: Double = 55
        static let tempAlertC: Double = 70
    }

    var id: UUID
    var protocolNumber: String?
    var serialDisplay: String?
    var startedAt: Date
    var endedAt: Date?
    var samples: [LiveCheckSample]
    var events: [LiveCheckEvent]
    var peakSpeedKmh: Double?
    var peakPowerW: Double?
    var maxControllerTempC: Double?
    var maxBatteryTempC: Double?

    /// Harte Obergrenze (~1 h bei 1 Hz), damit der Speicher nicht explodiert.
    static let maxSamples = 3600
    static let maxEvents = 200

    enum CodingKeys: String, CodingKey {
        case id, protocolNumber, serialDisplay, startedAt, endedAt
        case samples, events
        case peakSpeedKmh, peakPowerW, maxControllerTempC, maxBatteryTempC
    }

    init(
        id: UUID = UUID(),
        protocolNumber: String? = nil,
        serialDisplay: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        samples: [LiveCheckSample] = [],
        events: [LiveCheckEvent] = [],
        peakSpeedKmh: Double? = nil,
        peakPowerW: Double? = nil,
        maxControllerTempC: Double? = nil,
        maxBatteryTempC: Double? = nil
    ) {
        self.id = id
        self.protocolNumber = protocolNumber
        self.serialDisplay = serialDisplay
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.samples = samples
        self.events = events
        self.peakSpeedKmh = peakSpeedKmh
        self.peakPowerW = peakPowerW
        self.maxControllerTempC = maxControllerTempC
        self.maxBatteryTempC = maxBatteryTempC
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        protocolNumber = try c.decodeIfPresent(String.self, forKey: .protocolNumber)
        serialDisplay = try c.decodeIfPresent(String.self, forKey: .serialDisplay)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        samples = try c.decodeIfPresent([LiveCheckSample].self, forKey: .samples) ?? []
        events = try c.decodeIfPresent([LiveCheckEvent].self, forKey: .events) ?? []
        peakSpeedKmh = try c.decodeIfPresent(Double.self, forKey: .peakSpeedKmh)
        peakPowerW = try c.decodeIfPresent(Double.self, forKey: .peakPowerW)
        maxControllerTempC = try c.decodeIfPresent(Double.self, forKey: .maxControllerTempC)
        maxBatteryTempC = try c.decodeIfPresent(Double.self, forKey: .maxBatteryTempC)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(protocolNumber, forKey: .protocolNumber)
        try c.encodeIfPresent(serialDisplay, forKey: .serialDisplay)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encode(samples, forKey: .samples)
        try c.encode(events, forKey: .events)
        try c.encodeIfPresent(peakSpeedKmh, forKey: .peakSpeedKmh)
        try c.encodeIfPresent(peakPowerW, forKey: .peakPowerW)
        try c.encodeIfPresent(maxControllerTempC, forKey: .maxControllerTempC)
        try c.encodeIfPresent(maxBatteryTempC, forKey: .maxBatteryTempC)
    }

    /// Schwellen-Events nur einmal — anhand der bereits gespeicherten Events.
    private func hasEvent(_ kind: LiveCheckEvent.Kind) -> Bool {
        events.contains { $0.kind == kind }
    }

    var sampleCount: Int { samples.count }

    var durationSeconds: TimeInterval {
        let end = endedAt ?? samples.last?.at ?? startedAt
        return max(0, end.timeIntervalSince(startedAt))
    }

    var alarmEvents: [LiveCheckEvent] {
        events.filter(\.isAlarm)
    }

    var summaryLine: String {
        let mins = Int(durationSeconds / 60)
        let secs = Int(durationSeconds) % 60
        var parts = [
            "\(sampleCount) Punkte",
            "\(mins):\(String(format: "%02d", secs))"
        ]
        if let peak = peakSpeedKmh {
            parts.append(String(format: "%.1f km/h Peak", peak))
        }
        if let power = peakPowerW {
            parts.append(String(format: "%.0f W Peak", power))
        }
        if !alarmEvents.isEmpty {
            parts.append("\(alarmEvents.count) Alarm\(alarmEvents.count == 1 ? "" : "e")")
        }
        return parts.joined(separator: " · ")
    }

    /// Aktive Schwellenhinweise für die Live-UI (letzter Sample + Session-Max).
    func liveAlerts(for snap: LiveTelemetrySnapshot) -> [String] {
        var lines: [String] = []
        if let speed = snap.speedKmh, speed >= Thresholds.speedWarnKmh {
            lines.append(String(format: "Speed ≥ %.0f km/h (%.1f)", Thresholds.speedWarnKmh, speed))
        }
        if let power = snap.powerW, power >= Thresholds.powerWarnW {
            lines.append(String(format: "Leistung ≥ %.0f W (%.0f)", Thresholds.powerWarnW, power))
        }
        let ctrl = snap.controllerTempC ?? maxControllerTempC
        if let temp = ctrl {
            if temp >= Thresholds.tempAlertC {
                lines.append(String(format: "Controller ≥ %.0f °C (%.1f)", Thresholds.tempAlertC, temp))
            } else if temp >= Thresholds.tempWarnC {
                lines.append(String(format: "Controller ≥ %.0f °C (%.1f)", Thresholds.tempWarnC, temp))
            }
        }
        let batt = snap.batteryTempC ?? maxBatteryTempC
        if let temp = batt {
            if temp >= Thresholds.tempAlertC {
                lines.append(String(format: "Batterie ≥ %.0f °C (%.1f)", Thresholds.tempAlertC, temp))
            } else if temp >= Thresholds.tempWarnC {
                lines.append(String(format: "Batterie ≥ %.0f °C (%.1f)", Thresholds.tempWarnC, temp))
            }
        }
        return lines
    }

    mutating func append(_ snap: LiveTelemetrySnapshot) {
        guard samples.count < Self.maxSamples else { return }
        let sample = LiveCheckSample(from: snap)
        samples.append(sample)
        let at = sample.at

        if let speed = sample.speedKmh {
            if speed > (peakSpeedKmh ?? -1) {
                peakSpeedKmh = speed
                recordEvent(
                    kind: .newPeakSpeed,
                    at: at,
                    value: speed,
                    message: String(format: "Neuer Speed-Peak %.1f km/h", speed)
                )
            }
            if !hasEvent(.thresholdSpeed), speed >= Thresholds.speedWarnKmh {
                recordEvent(
                    kind: .thresholdSpeed,
                    at: at,
                    value: speed,
                    threshold: Thresholds.speedWarnKmh,
                    message: String(format: "Speed-Schwelle %.0f km/h überschritten (%.1f)", Thresholds.speedWarnKmh, speed)
                )
            }
        }
        if let power = sample.powerW {
            if power > (peakPowerW ?? -1) {
                peakPowerW = power
                recordEvent(
                    kind: .newPeakPower,
                    at: at,
                    value: power,
                    message: String(format: "Neuer Leistungs-Peak %.0f W", power)
                )
            }
            if !hasEvent(.thresholdPower), power >= Thresholds.powerWarnW {
                recordEvent(
                    kind: .thresholdPower,
                    at: at,
                    value: power,
                    threshold: Thresholds.powerWarnW,
                    message: String(format: "Leistungs-Schwelle %.0f W überschritten (%.0f)", Thresholds.powerWarnW, power)
                )
            }
        }
        if let temp = sample.controllerTempC {
            if temp > (maxControllerTempC ?? -100) {
                maxControllerTempC = temp
                recordEvent(
                    kind: .newPeakControllerTemp,
                    at: at,
                    value: temp,
                    message: String(format: "Neuer Controller-Temp-Peak %.1f °C", temp)
                )
            }
            let thr = temp >= Thresholds.tempAlertC ? Thresholds.tempAlertC : Thresholds.tempWarnC
            if !hasEvent(.thresholdControllerTemp), temp >= Thresholds.tempWarnC {
                recordEvent(
                    kind: .thresholdControllerTemp,
                    at: at,
                    value: temp,
                    threshold: thr,
                    message: String(format: "Controller-Temp-Schwelle %.0f °C überschritten (%.1f)", thr, temp)
                )
            }
        }
        if let temp = sample.batteryTempC {
            if temp > (maxBatteryTempC ?? -100) {
                maxBatteryTempC = temp
                recordEvent(
                    kind: .newPeakBatteryTemp,
                    at: at,
                    value: temp,
                    message: String(format: "Neuer Batterie-Temp-Peak %.1f °C", temp)
                )
            }
            let thr = temp >= Thresholds.tempAlertC ? Thresholds.tempAlertC : Thresholds.tempWarnC
            if !hasEvent(.thresholdBatteryTemp), temp >= Thresholds.tempWarnC {
                recordEvent(
                    kind: .thresholdBatteryTemp,
                    at: at,
                    value: temp,
                    threshold: thr,
                    message: String(format: "Batterie-Temp-Schwelle %.0f °C überschritten (%.1f)", thr, temp)
                )
            }
        }
    }

    private mutating func recordEvent(
        kind: LiveCheckEvent.Kind,
        at: Date,
        value: Double,
        threshold: Double? = nil,
        message: String
    ) {
        guard events.count < Self.maxEvents else { return }
        events.append(LiveCheckEvent(at: at, kind: kind, value: value, threshold: threshold, message: message))
    }

    func csvString() -> String {
        var lines = [
            "timestamp_iso,speed_kmh,battery_percent,voltage_v,current_a,power_w,remain_km,trip_km,trip_min,controller_temp_c,battery_temp_c"
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for s in samples {
            func num(_ v: Double?) -> String {
                guard let v else { return "" }
                return String(format: "%.3f", v)
            }
            func int(_ v: Int?) -> String {
                guard let v else { return "" }
                return "\(v)"
            }
            lines.append([
                formatter.string(from: s.at),
                num(s.speedKmh),
                int(s.batteryPercent),
                num(s.voltageV),
                num(s.currentA),
                num(s.powerW),
                num(s.remainKm),
                num(s.tripKm),
                int(s.tripMinutes),
                num(s.controllerTempC),
                num(s.batteryTempC)
            ].joined(separator: ","))
        }
        if !events.isEmpty {
            lines.append("")
            lines.append("# events")
            lines.append("timestamp_iso,kind,value,threshold,message")
            for e in events {
                let thr = e.threshold.map { String(format: "%.3f", $0) } ?? ""
                let msg = e.message.replacingOccurrences(of: ",", with: ";")
                lines.append([
                    formatter.string(from: e.at),
                    e.kind.rawValue,
                    String(format: "%.3f", e.value),
                    thr,
                    msg
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

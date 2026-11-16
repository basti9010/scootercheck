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

/// Forensische Live-Aufzeichnung bis Stop — speicherbar als JSON/CSV an der Prüfung.
struct LiveCheckRecording: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var protocolNumber: String?
    var serialDisplay: String?
    var startedAt: Date
    var endedAt: Date?
    var samples: [LiveCheckSample]
    var peakSpeedKmh: Double?
    var peakPowerW: Double?
    var maxControllerTempC: Double?
    var maxBatteryTempC: Double?

    /// Harte Obergrenze (~1 h bei 1 Hz), damit der Speicher nicht explodiert.
    static let maxSamples = 3600

    init(
        id: UUID = UUID(),
        protocolNumber: String? = nil,
        serialDisplay: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        samples: [LiveCheckSample] = [],
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
        self.peakSpeedKmh = peakSpeedKmh
        self.peakPowerW = peakPowerW
        self.maxControllerTempC = maxControllerTempC
        self.maxBatteryTempC = maxBatteryTempC
    }

    var sampleCount: Int { samples.count }

    var durationSeconds: TimeInterval {
        let end = endedAt ?? samples.last?.at ?? startedAt
        return max(0, end.timeIntervalSince(startedAt))
    }

    var summaryLine: String {
        let mins = Int(durationSeconds / 60)
        let secs = Int(durationSeconds) % 60
        let peak = peakSpeedKmh.map { String(format: "%.1f km/h Peak", $0) } ?? "kein Peak"
        return "\(sampleCount) Punkte · \(mins):\(String(format: "%02d", secs)) · \(peak)"
    }

    mutating func append(_ snap: LiveTelemetrySnapshot) {
        guard samples.count < Self.maxSamples else { return }
        let sample = LiveCheckSample(from: snap)
        samples.append(sample)
        if let speed = sample.speedKmh {
            peakSpeedKmh = max(peakSpeedKmh ?? speed, speed)
        }
        if let power = sample.powerW {
            peakPowerW = max(peakPowerW ?? power, power)
        }
        if let temp = sample.controllerTempC {
            maxControllerTempC = max(maxControllerTempC ?? temp, temp)
        }
        if let temp = sample.batteryTempC {
            maxBatteryTempC = max(maxBatteryTempC ?? temp, temp)
        }
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
        return lines.joined(separator: "\n") + "\n"
    }
}

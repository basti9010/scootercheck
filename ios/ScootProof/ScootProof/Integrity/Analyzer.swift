import Foundation
import CryptoKit

// MARK: - Integrity Analyzer

enum IntegrityAnalyzer {

    // MARK: - Public API

    static func analyze(
        reading: IntegrityReading,
        profile: ScooterProfile,
        sessionId: UUID = UUID()
    ) -> IntegrityResult {
        let trackMatch = TrackClassifier.classify(reading: reading, profile: profile)
        var facts: [MeasuredFact] = []

        facts += buildSerialFacts(reading: reading, profile: profile)
        facts += buildSpeedFacts(reading: reading, profile: profile)
        facts += buildFirmwareFacts(reading: reading, profile: profile)
        facts += buildOdometerFacts(reading: reading)
        facts += buildBatteryFacts(reading: reading)
        facts += buildTemperatureFacts(reading: reading)
        facts += buildErrorFacts(reading: reading)
        facts += buildFlagFacts(reading: reading)
        facts += buildGearFacts(reading: reading, profile: profile)
        facts += buildProtocolFacts(reading: reading)
        facts += buildIntegrityFacts(reading: reading)
        facts += buildBoardFacts(reading: reading)
        facts += buildHistoryFacts(reading: reading)
        facts += buildPhysicalFacts(reading: reading)

        let findings = buildFindings(facts: facts, trackMatch: trackMatch)
        let score = computeScore(facts: facts, trackMatch: trackMatch)
        let verdict = verdictFor(score: score, facts: facts, trackMatch: trackMatch)

        return IntegrityResult(
            sessionId: sessionId,
            profile: profile,
            reading: reading,
            facts: facts,
            findings: findings,
            trackMatch: trackMatch,
            score: score,
            verdict: verdict
        )
    }

    // MARK: - Demo Data

    enum DemoKind: String, CaseIterable {
        case stock
        case webapp
        case shu
        case shuDump = "shu_dump"
    }

    static func fillDemo(_ kind: DemoKind, profile: ScooterProfile = .zt3ProD) -> IntegrityReading {
        var reading = IntegrityReading()
        let stockSN = (profile.stockSerialHints.first ?? "SN") + "FACTORY001"

        switch kind {
        case .stock:
            reading.serialDisplay = stockSN
            reading.serialExpected = stockSN
            reading.serialMcu = stockSN
            reading.serialBle = stockSN
            reading.serialBms = stockSN
            reading.serialVcu = stockSN
            reading.speedCurrentKmh = 0
            reading.speedMaxKmh = profile.ratedMaxKmh
            reading.speedRatedKmh = profile.ratedMaxKmh
            reading.speedLimitKmh = profile.ratedMaxKmh
            reading.peakSpeedKmh = profile.ratedMaxKmh - 1
            reading.odometerKm = 342.5
            reading.tripKm = 0
            reading.remainKm = 18.2
            reading.rideTimeMinutes = 0
            reading.totalRideTimeMinutes = 1240
            reading.chargeCycles = 47
            reading.fwMcu = "1.2.8_DE"
            reading.fwBle = "1.1.4"
            reading.fwBms = "1.0.3"
            reading.fwVcu = "1.2.1"
            reading.fwEsc = "1.2.8_DE"
            reading.fwAppCustom = false
            reading.batteryPercent = 78
            reading.batteryVoltage = 41.2
            reading.batteryCurrent = 0
            reading.batteryHealth = 96
            reading.batteryTempC = 24.0
            reading.mcuTempC = 28.0
            reading.motorTempC = 26.0
            reading.errorCode = "0"
            reading.alarmCode = "0"
            reading.errorActive = false
            reading.peakPowerW = 400
            reading.panicModeActive = false
            reading.hiddenTuningDetected = false
            reading.safeLockActive = true
            reading.unboundRebound = false
            reading.gearMode = 1
            reading.gearMax = 1
            reading.protocolGen = 1
            reading.liveBoards = ["MCU", "BMS"]
            reading.physicalMarks = []
            reading.rawRegisters = demoStockRegisters()
            reading.evidenceSha256 = sha256Hex(of: "stock-demo-\(stockSN)")

        case .webapp:
            reading.serialDisplay = stockSN
            reading.serialExpected = "N4GSD9999YYYYYY"
            reading.serialMcu = stockSN
            reading.serialBle = stockSN
            reading.serialBms = stockSN
            reading.serialVcu = stockSN
            reading.speedLimitKmh = profile.tuningClearKmh
            reading.speedMaxKmh = profile.tuningClearKmh + 2
            reading.speedRatedKmh = profile.ratedMaxKmh
            reading.peakSpeedKmh = profile.tuningClearKmh + 1
            reading.odometerKm = 890.0
            reading.tripKm = 5.2
            reading.remainKm = 22.0
            reading.totalRideTimeMinutes = 3200
            reading.chargeCycles = 112
            reading.fwMcu = "1.2.8-WEB-MOD"
            reading.fwBle = "1.1.4"
            reading.fwBms = "1.0.3"
            reading.fwVcu = "1.2.1-CUSTOM"
            reading.fwAppCustom = true
            reading.batteryPercent = 65
            reading.batteryVoltage = 40.8
            reading.batteryHealth = 91
            reading.safeLockActive = false
            reading.panicModeActive = false
            reading.hiddenTuningDetected = false
            reading.unboundRebound = false
            reading.gearMode = 3
            reading.gearMax = 3
            reading.protocolGen = 1
            reading.liveBoards = ["MCU", "BMS", "VCU"]
            reading.rawRegisters = demoWebappRegisters()
            reading.evidenceSha256 = sha256Hex(of: "webapp-demo-\(stockSN)")

        case .shu:
            reading.serialDisplay = stockSN
            reading.serialExpected = stockSN
            reading.serialMcu = "N4GSU2301ZZZZZZ"
            reading.serialBle = stockSN
            reading.serialBms = stockSN
            reading.serialVcu = stockSN
            reading.speedLimitKmh = profile.tuningClearKmh + 5
            reading.speedMaxKmh = profile.tuningClearKmh + 8
            reading.peakSpeedKmh = profile.tuningClearKmh + 7
            reading.fwMcu = "1.2.8-SHU-PATCH"
            reading.fwVcu = "1.2.1-SHU"
            reading.fwAppCustom = true
            reading.panicModeActive = true
            reading.hiddenTuningDetected = true
            reading.unboundRebound = true
            reading.safeLockActive = false
            reading.gearMode = 5
            reading.gearMax = 5
            reading.protocolGen = 2
            reading.liveBoards = ["MCU", "BMS", "VCU", "ESC"]
            reading.rawRegisters = demoShuRegisters()
            reading.evidenceSha256 = sha256Hex(of: "shu-demo-\(stockSN)")

        case .shuDump:
            reading = fillDemo(.shu, profile: profile)
            reading.protocolGen = 3
            reading.liveBoards = ["MCU", "BMS", "VCU", "ESC", "BLE", "DISPLAY"]
            reading.rawRegisters = demoShuDumpRegisters()
            reading.odometerKm = 1520.8
            reading.totalRideTimeMinutes = 8900
            reading.evidenceSha256 = sha256Hex(of: reading.rawRegisters.map(\.valueHex).joined())
        }

        return reading
    }

    static func demoResult(_ kind: DemoKind, profile: ScooterProfile = .zt3ProD) -> IntegrityResult {
        let reading = fillDemo(kind, profile: profile)
        return analyze(reading: reading, profile: profile)
    }

    // MARK: - Fact Builders

    private static func buildSerialFacts(reading: IntegrityReading, profile: ScooterProfile) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []
        let sollSN = reading.serialExpected ?? profile.stockSerialHints.first ?? "—"

        facts.append(MeasuredFact(
            id: "serial.display",
            group: .serial,
            title: "Angezeigte Seriennummer",
            auslesewert: reading.serialDisplay ?? "—",
            sollwert: sollSN,
            status: serialStatus(reading.serialDisplay, expected: reading.serialExpected, profile: profile),
            bewertung: serialBewertung(reading.serialDisplay, expected: reading.serialExpected),
            erlaeuterung: "Die im Display bzw. App sichtbare Seriennummer.",
            raw: reading.serialDisplay
        ))

        facts.append(MeasuredFact(
            id: "serial.mcu",
            group: .serial,
            title: "MCU-Seriennummer",
            auslesewert: reading.serialMcu ?? "—",
            sollwert: TrackClassifier.looksLikeModuleSerial(reading.serialMcu)
                ? "eigene Board-ID (Max G3)"
                : (reading.serialDisplay ?? sollSN),
            status: {
                if reading.serialMcu == nil { return .nichtFeststellbar }
                if TrackClassifier.looksLikeModuleSerial(reading.serialMcu) { return .regelkonform }
                return TrackClassifier.mcuSerialMismatch(reading: reading) ? .erheblichAbweichend : .regelkonform
            }(),
            bewertung: {
                if reading.serialMcu == nil { return "Nicht auslesbar" }
                if TrackClassifier.looksLikeModuleSerial(reading.serialMcu) {
                    return "MCU-Hardware-ID (kein Fahrzeug-SN)"
                }
                return TrackClassifier.mcuSerialMismatch(reading: reading)
                    ? "MCU-SN weicht von Fahrzeug-SN ab"
                    : "MCU-SN konsistent"
            }(),
            erlaeuterung: "Direkt aus dem Motorsteuergerät (MCU) ausgelesene Seriennummer. Auf Max G3 ist das oft eine eigene Board-ID (z. B. Z07…).",
            raw: reading.serialMcu
        ))

        let region = TrackClassifier.serialRegion(for: reading.serialDisplay ?? reading.serialVcu)
        let foreignUS = region == .us
        facts.append(MeasuredFact(
            id: "serial.region",
            group: .serial,
            title: "Seriennummern-Region",
            auslesewert: region.label,
            sollwert: profile.market == .de20 ? "DE (1CGB…)" : "EU / DE",
            status: foreignUS && profile.market == .de20
                ? .erheblichAbweichend
                : (region == .unknown ? .nichtFeststellbar : .regelkonform),
            bewertung: foreignUS && profile.market == .de20
                ? "US-Region (1CGC) — Region-Unlock"
                : region.label,
            erlaeuterung: "Regionale Zuordnung anhand des SN-Präfixes (Max G3: 1CGB=DE, 1CGC=US).",
            raw: reading.serialDisplay ?? reading.serialVcu
        ))

        for (field, title, value) in [
            ("serial.ble", "BLE-Seriennummer", reading.serialBle),
            ("serial.bms", "BMS-Seriennummer", reading.serialBms),
            ("serial.vcu", "VCU-Seriennummer", reading.serialVcu)
        ] as [(String, String, String?)] {
            let isModule = TrackClassifier.looksLikeModuleSerial(value)
            let mismatch = !isModule && TrackClassifier.serialsMismatch(value, reading.serialDisplay)
            facts.append(MeasuredFact(
                id: field,
                group: .serial,
                title: title,
                auslesewert: value ?? "—",
                sollwert: isModule ? "Modulkennung" : (reading.serialDisplay ?? sollSN),
                status: value == nil ? .nichtFeststellbar : (isModule ? .regelkonform : (mismatch ? .abweichend : .regelkonform)),
                bewertung: {
                    if value == nil { return "Nicht auslesbar" }
                    if isModule { return "Modulkennung (kein Fahrzeug-SN)" }
                    return mismatch ? "Abweichung" : "Konsistent"
                }(),
                erlaeuterung: "Auslesung des zugehörigen Steuergeräts.",
                raw: value
            ))
        }

        return facts
    }

    private static func serialStatus(
        _ display: String?,
        expected: String?,
        profile: ScooterProfile
    ) -> FactStatus {
        if display == nil { return .nichtFeststellbar }
        if TrackClassifier.serialsMismatch(display, expected) { return .erheblichAbweichend }
        if let display, !profile.stockSerialHints.contains(where: { display.uppercased().hasPrefix($0) }) {
            return .abweichend
        }
        return .regelkonform
    }

    private static func serialBewertung(_ display: String?, expected: String?) -> String {
        if display == nil { return "Nicht auslesbar" }
        if TrackClassifier.serialsMismatch(display, expected) { return "SN-Mismatch" }
        return "Konsistent"
    }

    private static func buildSpeedFacts(reading: IntegrityReading, profile: ScooterProfile) -> [MeasuredFact] {
        let rated = profile.ratedMaxKmh
        var facts: [MeasuredFact] = []

        for (id, title, value, fmt) in [
            ("speed.limit", "Geschwindigkeitslimit", reading.speedLimitKmh, Format.kmh),
            ("speed.max", "Maximale Geschwindigkeit (gespeichert)", reading.speedMaxKmh, Format.kmh),
            ("speed.peak", "Spitzengeschwindigkeit (Peak)", reading.peakSpeedKmh, Format.kmh),
            ("speed.rated", "Bauartbedingte Höchstgeschwindigkeit", reading.speedRatedKmh, Format.kmh)
        ] as [(String, String, Double?, Format)] {
            let status = speedStatus(value: value, profile: profile)
            facts.append(MeasuredFact(
                id: id,
                group: .speed,
                title: title,
                auslesewert: fmt.format(value),
                sollwert: fmt.format(rated),
                status: status,
                bewertung: speedBewertung(value: value, profile: profile),
                erlaeuterung: "Vergleich mit typgenehmigter Höchstgeschwindigkeit (\(profile.shortLabel)).",
                raw: value.map { String($0) }
            ))
        }

        return facts
    }

    private static func speedStatus(value: Double?, profile: ScooterProfile) -> FactStatus {
        guard let value else { return .nichtFeststellbar }
        if value >= profile.tuningClearKmh { return .erheblichAbweichend }
        if value > profile.tuningSuspectKmh { return .abweichend }
        if value > profile.ratedMaxKmh + 1 { return .abweichend }
        return .regelkonform
    }

    private static func speedBewertung(value: Double?, profile: ScooterProfile) -> String {
        guard let value else { return "Nicht feststellbar" }
        if value >= profile.tuningClearKmh { return "Deutlich über Soll" }
        if value > profile.tuningSuspectKmh { return "Verdächtig erhöht" }
        return "Im Sollbereich"
    }

    private static func buildFirmwareFacts(reading: IntegrityReading, profile: ScooterProfile) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []
        let stockHint = "Werkseitiges Muster (z. B. x.y.z_DE)"

        for (id, title, value) in [
            ("fw.mcu", "MCU-Firmware", reading.fwMcu),
            ("fw.ble", "BLE-Firmware", reading.fwBle),
            ("fw.bms", "BMS-Firmware", reading.fwBms),
            ("fw.vcu", "VCU-Firmware", reading.fwVcu),
            ("fw.esc", "ESC-Firmware", reading.fwEsc)
        ] {
            let custom = value.map { TrackClassifier.matchesFwRegex($0, regex: TrackClassifier.customFwRegex) } ?? false
            let webapp = value.map { TrackClassifier.matchesFwRegex($0, regex: TrackClassifier.webappFwRegex) } ?? false
            let shu = value.map { TrackClassifier.matchesFwRegex($0, regex: TrackClassifier.shuFwRegex) } ?? false
            let status: FactStatus = value == nil ? .nichtFeststellbar : (shu || custom ? .erheblichAbweichend : (webapp ? .abweichend : .regelkonform))
            var bewertung = "Serienmäßig"
            if shu { bewertung = "SHU-Kennung" }
            else if webapp { bewertung = "Web-App-Kennung" }
            else if custom { bewertung = "Custom-Firmware" }

            facts.append(MeasuredFact(
                id: id,
                group: .firmware,
                title: title,
                auslesewert: value ?? "—",
                sollwert: stockHint,
                status: status,
                bewertung: bewertung,
                erlaeuterung: "Firmware-Version des Steuergeräts; Abweichungen können auf Parameteränderungen hinweisen.",
                raw: value
            ))
        }

        facts.append(MeasuredFact(
            id: "fw.app.custom",
            group: .firmware,
            title: "Custom-App-Firmware-Flag",
            auslesewert: reading.fwAppCustom == true ? "gesetzt" : (reading.fwAppCustom == false ? "nicht gesetzt" : "—"),
            sollwert: "nicht gesetzt",
            status: reading.fwAppCustom == true ? .erheblichAbweichend : (reading.fwAppCustom == nil ? .nichtFeststellbar : .regelkonform),
            bewertung: reading.fwAppCustom == true ? "Custom-Firmware aktiv" : "Serienzustand",
            erlaeuterung: "Flag für nicht-werkseitige Firmware-Installation.",
            raw: reading.fwAppCustom.map { String($0) }
        ))

        _ = profile // reserved for profile-specific fw checks
        return facts
    }

    private static func buildOdometerFacts(reading: IntegrityReading) -> [MeasuredFact] {
        [
            MeasuredFact(
                id: "odo.total",
                group: .odometer,
                title: "Gesamtkilometerstand",
                auslesewert: Format.km.format(reading.odometerKm),
                sollwert: "—",
                status: reading.odometerKm == nil ? .nichtFeststellbar : .regelkonform,
                bewertung: "Auslesewert dokumentiert",
                erlaeuterung: "Kumulierter Kilometerstand laut Steuergerät.",
                raw: reading.odometerKm.map { String($0) }
            ),
            MeasuredFact(
                id: "odo.trip",
                group: .odometer,
                title: "Trip-Kilometerstand",
                auslesewert: Format.km.format(reading.tripKm),
                sollwert: "—",
                status: reading.tripKm == nil ? .nichtFeststellbar : .regelkonform,
                bewertung: "Auslesewert dokumentiert",
                erlaeuterung: "Aktuelle Fahrtstrecke.",
                raw: reading.tripKm.map { String($0) }
            ),
            MeasuredFact(
                id: "odo.remain",
                group: .odometer,
                title: "Restreichweite",
                auslesewert: Format.km.format(reading.remainKm),
                sollwert: "—",
                status: reading.remainKm == nil ? .nichtFeststellbar : .regelkonform,
                bewertung: "Auslesewert dokumentiert",
                erlaeuterung: "Geschätzte Restreichweite.",
                raw: reading.remainKm.map { String($0) }
            )
        ]
    }

    private static func buildBatteryFacts(reading: IntegrityReading) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []
        if let pct = reading.batteryPercent {
            facts.append(MeasuredFact(
                id: "bat.percent",
                group: .battery,
                title: "Ladezustand",
                auslesewert: "\(pct) %",
                sollwert: "0–100 %",
                status: (0...100).contains(pct) ? .regelkonform : .abweichend,
                bewertung: "Plausibel",
                erlaeuterung: "Aktueller Batterieladezustand.",
                raw: String(pct)
            ))
        }
        if let v = reading.batteryVoltage {
            facts.append(MeasuredFact(
                id: "bat.voltage",
                group: .battery,
                title: "Batteriespannung",
                auslesewert: String(format: "%.1f V", v),
                sollwert: "36–42 V (typ.)",
                status: (30...45).contains(v) ? .regelkonform : .abweichend,
                bewertung: (30...45).contains(v) ? "Plausibel" : "Unplausibel",
                erlaeuterung: "Nennspannung des Akkupacks.",
                raw: String(v)
            ))
        }
        if let health = reading.batteryHealth {
            facts.append(MeasuredFact(
                id: "bat.health",
                group: .battery,
                title: "Batteriegesundheit",
                auslesewert: "\(health) %",
                sollwert: "≥ 80 %",
                status: health >= 80 ? .regelkonform : (health >= 60 ? .abweichend : .erheblichAbweichend),
                bewertung: health >= 80 ? "Gut" : "Abgenutzt",
                erlaeuterung: "SOH-Wert des Batteriemanagementsystems.",
                raw: String(health)
            ))
        }
        if let cycles = reading.chargeCycles {
            facts.append(MeasuredFact(
                id: "bat.cycles",
                group: .battery,
                title: "Ladezyklen",
                auslesewert: Format.num.format(cycles),
                sollwert: "—",
                status: .regelkonform,
                bewertung: "Dokumentiert",
                erlaeuterung: "Anzahl vollständiger Ladezyklen.",
                raw: String(cycles)
            ))
        }
        return facts
    }

    private static func buildTemperatureFacts(reading: IntegrityReading) -> [MeasuredFact] {
        var facts: [MeasuredFact] = []
        for (id, title, value) in [
            ("temp.battery", "Batterietemperatur", reading.batteryTempC),
            ("temp.mcu", "MCU-Temperatur", reading.mcuTempC),
            ("temp.motor", "Motortemperatur", reading.motorTempC)
        ] {
            guard let value else { continue }
            let status: FactStatus = value > 70 ? .erheblichAbweichend : (value > 55 ? .abweichend : .regelkonform)
            facts.append(MeasuredFact(
                id: id,
                group: .temperature,
                title: title,
                auslesewert: String(format: "%.1f °C", value),
                sollwert: "< 55 °C (Betrieb)",
                status: status,
                bewertung: status == .regelkonform ? "Normal" : "Erhöht",
                erlaeuterung: "Temperaturauslesewert zum Prüfzeitpunkt.",
                raw: String(value)
            ))
        }
        return facts
    }

    private static func buildErrorFacts(reading: IntegrityReading) -> [MeasuredFact] {
        let hasError = reading.errorActive == true
            || (reading.errorCode != nil && reading.errorCode != "0" && reading.errorCode != "—")
        return [
            MeasuredFact(
                id: "error.code",
                group: .error,
                title: "Fehlercode",
                auslesewert: reading.errorCode ?? "—",
                sollwert: "0",
                status: hasError ? .abweichend : (reading.errorCode == nil ? .nichtFeststellbar : .regelkonform),
                bewertung: hasError ? "Fehler aktiv" : "Kein Fehler",
                erlaeuterung: "Aktiver Diagnosefehlercode des Fahrzeugsystems.",
                raw: reading.errorCode
            ),
            MeasuredFact(
                id: "error.alarm",
                group: .error,
                title: "Alarmcode",
                auslesewert: reading.alarmCode ?? "—",
                sollwert: "0",
                status: (reading.alarmCode != nil && reading.alarmCode != "0") ? .abweichend : .regelkonform,
                bewertung: (reading.alarmCode != nil && reading.alarmCode != "0") ? "Alarm gesetzt" : "Kein Alarm",
                erlaeuterung: "Alarmzustand des Batterie- oder Antriebssystems.",
                raw: reading.alarmCode
            )
        ]
    }

    private static func buildFlagFacts(reading: IntegrityReading) -> [MeasuredFact] {
        [
            flagFact(id: "flag.safelock", title: "SafeLock", value: reading.safeLockActive, soll: true, inverted: true),
            flagFact(id: "flag.panic", title: "Panic-Modus", value: reading.panicModeActive, soll: false, inverted: false),
            MeasuredFact(
                id: "flag.hidden",
                group: .flags,
                title: "Verstecktes / Soft-Unlock",
                auslesewert: {
                    if reading.hiddenTuningDetected == true {
                        let limit = reading.speedLimitKmh ?? reading.speedRatedKmh
                        if let limit, limit >= 25 {
                            return "Limit \(Format.kmh.format(Optional(limit)))"
                        }
                        return "gesetzt"
                    }
                    if reading.hiddenTuningDetected == false { return "inaktiv" }
                    return "—"
                }(),
                sollwert: "inaktiv",
                status: {
                    if reading.hiddenTuningDetected == true { return .erheblichAbweichend }
                    if reading.hiddenTuningDetected == false { return .regelkonform }
                    return .nichtFeststellbar
                }(),
                bewertung: {
                    if reading.hiddenTuningDetected == true {
                        return "Soft-Unlock / erhöhtes Limit (z. B. nach Bremshebel-Sequenz)"
                    }
                    if reading.hiddenTuningDetected == false { return "Serienzustand" }
                    return "Nicht feststellbar"
                }(),
                erlaeuterung: "Erhöhte Limits oder Unlock-Flags. Die Bremshebel-Geste selbst ist nicht speicherbar — nur ihre Wirkung auf Register.",
                raw: reading.hiddenTuningDetected.map { $0 ? "1" : "0" }
            ),
            flagFact(id: "flag.unbound", title: "Unbound Rebound", value: reading.unboundRebound, soll: false, inverted: false)
        ]
    }

    private static func flagFact(id: String, title: String, value: Bool?, soll: Bool, inverted: Bool) -> MeasuredFact {
        let auslese = value == nil ? "—" : (value == true ? "aktiv" : "inaktiv")
        let sollText = soll ? "aktiv" : "inaktiv"
        var status: FactStatus = .nichtFeststellbar
        if let value {
            let matches = value == soll
            if inverted {
                status = matches ? .regelkonform : (value ? .erheblichAbweichend : .abweichend)
            } else {
                status = matches ? .regelkonform : (value ? .erheblichAbweichend : .regelkonform)
            }
        }
        return MeasuredFact(
            id: id,
            group: .flags,
            title: title,
            auslesewert: auslese,
            sollwert: sollText,
            status: status,
            bewertung: status == .regelkonform ? "Unauffällig" : (status == .nichtFeststellbar ? "Nicht feststellbar" : "Auffällig"),
            erlaeuterung: "Sicherheits- bzw. Manipulationsrelevantes Flag.",
            raw: value.map { String($0) }
        )
    }

    private static func buildGearFacts(reading: IntegrityReading, profile: ScooterProfile) -> [MeasuredFact] {
        let maxGear = reading.gearMax
        return [
            MeasuredFact(
                id: "gear.mode",
                group: .gear,
                title: "Aktueller Fahrmodus",
                auslesewert: Format.num.format(reading.gearMode),
                sollwert: "1",
                status: reading.gearMode == nil ? .nichtFeststellbar : ((reading.gearMode ?? 1) > 1 ? .abweichend : .regelkonform),
                bewertung: reading.gearMode == nil ? "Nicht feststellbar" : ((reading.gearMode ?? 1) > 1 ? "Erweiterter Modus" : "Serienmodus"),
                erlaeuterung: "Eingestellter Fahrmodus / Gang.",
                raw: reading.gearMode.map { String($0) }
            ),
            MeasuredFact(
                id: "gear.max",
                group: .gear,
                title: "Maximaler Fahrmodus",
                auslesewert: Format.num.format(maxGear),
                sollwert: "1 (\(profile.shortLabel))",
                status: maxGear == nil ? .nichtFeststellbar : ((maxGear ?? 1) > 1 ? .erheblichAbweichend : .regelkonform),
                bewertung: maxGear == nil ? "Nicht feststellbar" : ((maxGear ?? 1) > 1 ? "Mehr als Serienmodus" : "Serienmodus"),
                erlaeuterung: "Höchster verfügbarer Fahrmodus laut Steuergerät.",
                raw: maxGear.map { String($0) }
            )
        ]
    }

    private static func buildProtocolFacts(reading: IntegrityReading) -> [MeasuredFact] {
        let gen = reading.protocolGen ?? 1
        let enc2Expected = (reading.bleStack == BleStack.ninebotEnc2.rawValue) || gen >= 2
        return [
            MeasuredFact(
                id: "protocol.gen",
                group: .proto,
                title: "Protokoll-Generation",
                auslesewert: Format.num.format(reading.protocolGen),
                sollwert: enc2Expected ? "2 (Enc2)" : "1",
                status: enc2Expected
                    ? (gen >= 2 ? .regelkonform : .abweichend)
                    : (gen > 1 ? .abweichend : .regelkonform),
                bewertung: enc2Expected
                    ? (gen >= 2 ? "Ninebot Enc2" : "Unerwartet")
                    : (gen > 1 ? "Erweitertes Protokoll" : "Standard"),
                erlaeuterung: "Version des verwendeten Ausleseprotokolls. Max G3 nutzt Enc2 (Gen 2) werkseitig.",
                raw: reading.protocolGen.map { String($0) }
            ),
            MeasuredFact(
                id: "protocol.registers",
                group: .proto,
                title: "Rohregister-Anzahl",
                auslesewert: "\(reading.rawRegisters.count)",
                sollwert: "Diagnoseauslese",
                status: .regelkonform,
                bewertung: "\(reading.rawRegisters.count) Register",
                erlaeuterung: "Anzahl ausgelesener Rohdatenregister.",
                raw: String(reading.rawRegisters.count)
            )
        ]
    }

    private static func buildIntegrityFacts(reading: IntegrityReading) -> [MeasuredFact] {
        let hashValid = reading.evidenceSha256?.count == 64
        return [
            MeasuredFact(
                id: "integrity.hash",
                group: .integrity,
                title: "Integritäts-Hash (SHA-256)",
                auslesewert: reading.evidenceSha256 ?? "—",
                sollwert: "64 Zeichen Hex",
                status: reading.evidenceSha256 == nil ? .nichtFeststellbar : (hashValid ? .regelkonform : .abweichend),
                bewertung: hashValid ? "Hash vorhanden" : "Kein gültiger Hash",
                erlaeuterung: "Kryptographischer Fingerabdruck der Auslesedaten.",
                raw: reading.evidenceSha256
            )
        ]
    }

    private static func buildBoardFacts(reading: IntegrityReading) -> [MeasuredFact] {
        [
            MeasuredFact(
                id: "boards.live",
                group: .boards,
                title: "Ausgelesene Steuergeräte",
                auslesewert: reading.liveBoards.isEmpty ? "—" : reading.liveBoards.joined(separator: ", "),
                sollwert: "MCU, BMS",
                status: reading.liveBoards.count > 4 ? .abweichend : .regelkonform,
                bewertung: "\(reading.liveBoards.count) Board(s)",
                erlaeuterung: "Liste der erfolgreich angebundenen Steuergeräte.",
                raw: reading.liveBoards.joined(separator: ",")
            )
        ]
    }

    private static func buildHistoryFacts(reading: IntegrityReading) -> [MeasuredFact] {
        [
            MeasuredFact(
                id: "history.ride",
                group: .history,
                title: "Gesamtfahrzeit",
                auslesewert: Format.minutes.format(reading.totalRideTimeMinutes),
                sollwert: "—",
                status: reading.totalRideTimeMinutes == nil ? .nichtFeststellbar : .regelkonform,
                bewertung: "Dokumentiert",
                erlaeuterung: "Kumulierte Betriebszeit laut Steuergerät.",
                raw: reading.totalRideTimeMinutes.map { String($0) }
            ),
            MeasuredFact(
                id: "history.peak.power",
                group: .history,
                title: "Spitzenleistung",
                auslesewert: reading.peakPowerW.map { String(format: "%.0f W", $0) } ?? "—",
                sollwert: "≤ 500 W (typ.)",
                status: (reading.peakPowerW ?? 0) > 700 ? .erheblichAbweichend : ((reading.peakPowerW ?? 0) > 500 ? .abweichend : .regelkonform),
                bewertung: (reading.peakPowerW ?? 0) > 500 ? "Erhöht" : "Im Bereich",
                erlaeuterung: "Historisch gespeicherte maximale Antriebsleistung.",
                raw: reading.peakPowerW.map { String($0) }
            )
        ]
    }

    private static func buildPhysicalFacts(reading: IntegrityReading) -> [MeasuredFact] {
        [
            MeasuredFact(
                id: "physical.marks",
                group: .physical,
                title: "Physische Merkmale / Beschädigungen",
                auslesewert: reading.physicalMarks.isEmpty ? "keine dokumentiert" : reading.physicalMarks.joined(separator: "; "),
                sollwert: "—",
                status: reading.physicalMarks.isEmpty ? .regelkonform : .abweichend,
                bewertung: reading.physicalMarks.isEmpty ? "Keine Einträge" : "\(reading.physicalMarks.count) Merkmal(e)",
                erlaeuterung: "Vom Prüfer dokumentierte äußere Merkmale (nur Beobachtung, keine Auslesung).",
                raw: reading.physicalMarks.joined(separator: ";")
            )
        ]
    }

    // MARK: - Findings

    private static func buildFindings(facts: [MeasuredFact], trackMatch: TrackMatch) -> [Finding] {
        var findings: [Finding] = []

        let critical = facts.filter { $0.status == .erheblichAbweichend }
        for fact in critical {
            findings.append(Finding(
                id: "finding.\(fact.id)",
                severity: fact.status,
                title: fact.title,
                detail: fact.erlaeuterung + " " + fact.bewertung,
                relatedFactIds: [fact.id],
                trackHint: trackMatch.trackId
            ))
        }

        if trackMatch.trackId == .webapp || trackMatch.trackId == .shu || trackMatch.trackId == .shuDump {
            findings.append(Finding(
                id: "finding.track.\(trackMatch.trackId.rawValue)",
                severity: trackMatch.confidence > 0.6 ? .erheblichAbweichend : .abweichend,
                title: "Musterzuordnung: \(trackMatch.trackId.label)",
                detail: trackMatch.explanation,
                relatedFactIds: facts.filter { $0.status != .regelkonform }.map(\.id),
                trackHint: trackMatch.trackId
            ))
        }

        let snMismatch = facts.first { $0.id == "serial.display" && $0.status == .erheblichAbweichend }
        if let snMismatch {
            findings.append(Finding(
                id: "finding.sn.mismatch",
                severity: .erheblichAbweichend,
                title: "Seriennummer-Inkonsistenz",
                detail: "Angezeigte und erwartete Seriennummer stimmen nicht überein — typisches Merkmal parameterändernder Web-Apps.",
                relatedFactIds: [snMismatch.id],
                trackHint: .webapp
            ))
        }

        return findings
    }

    // MARK: - Scoring

    private static func computeScore(facts: [MeasuredFact], trackMatch: TrackMatch) -> Int {
        var score = 100
        for fact in facts {
            switch fact.status {
            case .regelkonform, .nichtFeststellbar:
                break
            case .abweichend:
                score -= 8
            case .erheblichAbweichend:
                score -= 18
            }
        }

        switch trackMatch.trackId {
        case .stock:
            score = min(100, score + 5)
        case .webapp:
            score -= 15
        case .shu:
            score -= 25
        case .shuDump:
            score -= 30
        case .unknown:
            score -= 5
        }

        return min(100, max(0, score))
    }

    private static func verdictFor(score: Int, facts: [MeasuredFact], trackMatch: TrackMatch) -> VerdictLevel {
        let severeCount = facts.filter { $0.status == .erheblichAbweichend }.count
        if score >= 80 && severeCount == 0 && (trackMatch.trackId == .stock || trackMatch.trackId == .unknown) {
            return .stock
        }
        if score < 50 || severeCount >= 3 || trackMatch.trackId == .shu || trackMatch.trackId == .shuDump {
            return .tuned
        }
        return .watch
    }

    // MARK: - Demo Registers

    private static func demoStockRegisters() -> [RawRegister] {
        [
            RawRegister(address: "0x20A0", name: "SpeedLimit", valueHex: "0x0014", valueDecoded: "20 km/h"),
            RawRegister(address: "0x20A2", name: "MaxSpeed", valueHex: "0x0014", valueDecoded: "20 km/h"),
            RawRegister(address: "0x2100", name: "SafeLock", valueHex: "0x01", valueDecoded: "enabled")
        ]
    }

    private static func demoWebappRegisters() -> [RawRegister] {
        demoStockRegisters() + [
            RawRegister(address: "0x20A0", index: 1, name: "SpeedLimitOverride", valueHex: "0x001F", valueDecoded: "31 km/h"),
            RawRegister(address: "0x3001", name: "DisplaySN", valueHex: "—", valueDecoded: "N4GSD2412XXXXXX"),
            RawRegister(address: "0x3002", name: "InternalSN", valueHex: "—", valueDecoded: "N4GSD9999YYYYYY", note: "SN-Mismatch")
        ]
    }

    private static func demoShuRegisters() -> [RawRegister] {
        [
            RawRegister(address: "0x20A0", name: "SpeedLimit", valueHex: "0x0023", valueDecoded: "35 km/h"),
            RawRegister(address: "0x20B0", name: "HiddenTuneFlag", valueHex: "0x01", valueDecoded: "1"),
            RawRegister(address: "0x20C0", name: "PanicMode", valueHex: "0x01", valueDecoded: "active"),
            RawRegister(address: "0x3100", name: "MCUSerial", valueHex: "—", valueDecoded: "N4GSU2301ZZZZZZ"),
            RawRegister(address: "0x3101", name: "UnboundRebound", valueHex: "0x01", valueDecoded: "true")
        ]
    }

    private static func demoShuDumpRegisters() -> [RawRegister] {
        var regs = demoShuRegisters()
        for i in 0..<20 {
            regs.append(RawRegister(
                address: String(format: "0x%04X", 0x4000 + i),
                index: i,
                name: "DumpReg_\(i)",
                valueHex: String(format: "0x%04X", i * 17),
                valueDecoded: "raw"
            ))
        }
        return regs
    }

    private static func sha256Hex(of string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

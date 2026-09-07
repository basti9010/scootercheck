import Foundation
import CryptoKit

// MARK: - Integrity Analyzer

enum IntegrityAnalyzer {

    // MARK: - Public API

    static func analyze(
        reading: IntegrityReading,
        profile: ScooterProfile,
        sessionId: UUID = UUID(),
        priorUnlock: PriorUnlockEvidence? = nil,
        priorReading: IntegrityReading? = nil,
        priorProtocolNumber: String? = nil,
        powerCycle: PowerCycleReport? = nil
    ) -> IntegrityResult {
        var reading = reading
        normalizeSpeedUnlockFlag(&reading)

        let trackMatch = TrackClassifier.classify(reading: reading, profile: profile)
        let evidence = EvidenceEngine.evaluate(
            reading: reading,
            profile: profile,
            priorUnlock: priorUnlock,
            priorReading: priorReading,
            priorProtocolNumber: priorProtocolNumber,
            powerCycle: powerCycle
        )

        var facts: [MeasuredFact] = []

        facts += buildSerialFacts(reading: reading, profile: profile)
        facts += buildSpeedFacts(reading: reading, profile: profile)
        facts += buildFirmwareFacts(reading: reading, profile: profile)
        facts += CustomFirmwareDiff.buildFacts(reading: reading, profile: profile)
        facts += buildOdometerFacts(reading: reading)
        facts += buildBatteryFacts(reading: reading)
        facts += buildTemperatureFacts(reading: reading)
        facts += buildErrorFacts(reading: reading)
        facts += buildFlagFacts(reading: reading, profile: profile, priorUnlock: priorUnlock)
        facts += buildGearFacts(reading: reading, profile: profile)
        facts += buildProtocolFacts(reading: reading)
        facts += buildIntegrityFacts(reading: reading)
        facts += buildBoardFacts(reading: reading)
        facts += buildHistoryFacts(reading: reading)
        facts += buildPhysicalFacts(reading: reading)
        // Nur Engine-Ausgabe — keine Neubewertung in Analyzer/UI.
        facts += EvidenceEngine.buildFacts(evidence, reading: reading, profile: profile)
        facts = enrichFactsWithRawCitations(facts, reading: reading, profile: profile)

        var findings = buildFindings(facts: facts, trackMatch: trackMatch)
        findings += evidenceFindings(evidence)

        return IntegrityResult(
            sessionId: sessionId,
            profile: profile,
            reading: reading,
            facts: facts,
            findings: findings,
            trackMatch: trackMatch,
            score: evidence.score,
            verdict: evidence.verdict,
            evidence: evidence
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

    /// Soft-Unlock-Flag nur aus Tempo-Limit ableiten (nicht aus Gängen).
    private static func normalizeSpeedUnlockFlag(_ reading: inout IntegrityReading) {
        guard SoftUnlockSettings.isEnabledSnapshot() else { return }
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let lim = reading.speedLimitKmh ?? reading.speedMaxKmh ?? 0
        let peak = reading.peakSpeedKmh ?? 0
        if lim >= threshold || peak >= threshold {
            reading.hiddenTuningDetected = true
        } else if reading.hiddenTuningDetected == nil {
            reading.hiddenTuningDetected = false
        }
    }

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
            ("speed.peak", "Trip-Spitzengeschwindigkeit (Peak)", reading.peakSpeedKmh, Format.kmh),
            ("speed.rated", "Bauartbedingte Höchstgeschwindigkeit", reading.speedRatedKmh, Format.kmh)
        ] as [(String, String, Double?, Format)] {
            let status = speedStatus(value: value, profile: profile)
            let peakNote = id == "speed.peak"
                ? "Höchstwert der aktuellen/letzten Fahrt (rSigMaxSpeed), nicht das konfigurierte Limit."
                : "Vergleich mit typgenehmigter Höchstgeschwindigkeit (\(profile.shortLabel))."
            facts.append(MeasuredFact(
                id: id,
                group: .speed,
                title: title,
                auslesewert: fmt.format(value),
                sollwert: fmt.format(rated),
                status: status,
                bewertung: speedBewertung(value: value, profile: profile),
                erlaeuterung: peakNote,
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
        let analysis = StockFirmwareCatalog.analyze(reading: reading, profile: profile)
        let stockHint = analysis.hasCatalog
            ? "Bekannte Serie (\(profile.shortLabel))"
            : "Werkseitiges Muster (z. B. x.y.z_DE)"

        facts.append(MeasuredFact(
            id: "fw.analysis",
            group: .firmware,
            title: "Firmware-Analyse (Gesamt)",
            auslesewert: analysis.summaryLine.isEmpty ? "—" : analysis.summaryLine,
            sollwert: analysis.hasCatalog ? "Alle Module im Serienkatalog" : "Dokumentierte Serienversionen",
            status: analysis.overallStatus,
            bewertung: analysis.overallBewertung,
            erlaeuterung: "Lesende Auswertung der Modul-Firmware (MCU/BLE/BMS/VCU) inkl. Rohwert und Abgleich mit öffentlich bekannten Serienständen. Kein Flash/Dump der Binary — nur Versionsregister. Custom-FW kann Versionen fälschen; dann zählen persistente Marker.",
            raw: [
                "read=\(analysis.readCount)",
                "stock=\(analysis.stockCount)",
                "miss=\(analysis.notInCatalogCount)",
                "custom=\(analysis.customCount)"
            ].joined(separator: ";")
        ))

        for component in analysis.components {
            let value = component.version
            let webapp = value.map { TrackClassifier.matchesFwRegex($0, regex: TrackClassifier.webappFwRegex) } ?? false

            let status: FactStatus = {
                if value == nil { return .nichtFeststellbar }
                switch component.match {
                case .customMarked: return .erheblichAbweichend
                case .notInCatalog: return .abweichend
                case .listedStock, .documentedOnly: return .regelkonform
                case .unknownComponent:
                    return webapp ? .abweichend : .regelkonform
                }
            }()

            var bewertung = component.match.label.prefix(1).uppercased() + component.match.label.dropFirst()
            if webapp && component.match != .customMarked { bewertung = "Web-App-Kennung" }

            let hexNote = component.rawHex.map { " Rohhex \($0)." } ?? ""
            let catalogNote: String = {
                guard let listed = component.listed, !listed.isEmpty else {
                    return "Kein Modul-Katalog hinterlegt — Version nur dokumentiert."
                }
                let sample = listed.sorted().prefix(4).joined(separator: ", ")
                return "Serienkatalog u. a.: \(sample)\(listed.count > 4 ? ", …" : "")."
            }()

            facts.append(MeasuredFact(
                id: component.id,
                group: .firmware,
                title: component.title,
                auslesewert: value ?? "—",
                sollwert: stockHint,
                status: status,
                bewertung: bewertung,
                erlaeuterung: "Versionsregister ausgelesen und mit Serienkatalog verglichen.\(hexNote) \(catalogNote)",
                raw: [value, component.rawHex].compactMap { $0 }.joined(separator: "|")
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
            let ok = (30...52).contains(v)
            facts.append(MeasuredFact(
                id: "bat.voltage",
                group: .battery,
                title: "Batteriespannung",
                auslesewert: String(format: "%.1f V", v),
                sollwert: "36–50 V (typ. 10s / Max G3)",
                status: ok ? .regelkonform : .abweichend,
                bewertung: ok ? "Plausibel" : "Unplausibel",
                erlaeuterung: "Packspannung; Max G3 liegt werkseitig oft bei ca. 36–50 V.",
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
        let errorZero = isInactiveDiagCode(reading.errorCode)
        let alarmZero = isInactiveDiagCode(reading.alarmCode)
        let hasError = reading.errorActive == true || (reading.errorCode != nil && !errorZero)
        let hasAlarm = reading.alarmCode != nil && !alarmZero
        return [
            MeasuredFact(
                id: "error.code",
                group: .error,
                title: "Fehlercode",
                auslesewert: reading.errorCode ?? "—",
                sollwert: "0 / 0x0000",
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
                sollwert: "0 / 0x0000",
                status: hasAlarm ? .abweichend : (reading.alarmCode == nil ? .nichtFeststellbar : .regelkonform),
                bewertung: hasAlarm ? "Alarm gesetzt" : "Kein Alarm",
                erlaeuterung: "Alarmzustand des Batterie- oder Antriebssystems.",
                raw: reading.alarmCode
            )
        ]
    }

    /// `0`, `0x0000`, `0x0` usw. gelten als inaktiv.
    private static func isInactiveDiagCode(_ code: String?) -> Bool {
        guard var s = code?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s != "—" else {
            return true
        }
        if s.lowercased().hasPrefix("0x") { s = String(s.dropFirst(2)) }
        return s.allSatisfy { $0 == "0" }
    }

    private static func buildFlagFacts(
        reading: IntegrityReading,
        profile: ScooterProfile,
        priorUnlock: PriorUnlockEvidence?
    ) -> [MeasuredFact] {
        [
            flagFact(id: "flag.safelock", title: "SafeLock", value: reading.safeLockActive, soll: true, inverted: true),
            flagFact(id: "flag.panic", title: "Panic-Modus", value: reading.panicModeActive, soll: false, inverted: false),
            MeasuredFact(
                id: "flag.hidden",
                group: .flags,
                title: "Soft-Unlock (Tempo, aktuelle Session)",
                auslesewert: {
                    if reading.hiddenTuningDetected == true {
                        let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
                        let peak = reading.peakSpeedKmh
                        if let limit, limit > 0 {
                            return "Limit \(Format.kmh.format(Optional(limit)))"
                        }
                        if let peak, peak > 0 {
                            return "Trip-Peak \(Format.kmh.format(Optional(peak)))"
                        }
                        return "Tempo über Schwelle"
                    }
                    if reading.hiddenTuningDetected == false { return "inaktiv / zurückgesetzt" }
                    return "—"
                }(),
                sollwert: "inaktiv (≤ Typ \(Format.kmh.format(Optional(profile.ratedMaxKmh))))",
                status: {
                    if !SoftUnlockSettings.isEnabledSnapshot() { return .nichtFeststellbar }
                    if reading.hiddenTuningDetected == true { return .erheblichAbweichend }
                    if reading.hiddenTuningDetected == false { return .regelkonform }
                    // Kein Flag gesetzt, aber Limit/Peak klar über Typ → trotzdem auffällig.
                    let lim = reading.speedLimitKmh ?? reading.speedMaxKmh ?? 0
                    let peak = reading.peakSpeedKmh ?? 0
                    if max(lim, peak) >= SoftUnlockSettings.thresholdKmhSnapshot() {
                        return .erheblichAbweichend
                    }
                    return .nichtFeststellbar
                }(),
                bewertung: {
                    let gesture = SoftUnlockSettings.gestureSummarySnapshot()
                    if !SoftUnlockSettings.isEnabledSnapshot() {
                        return "Erkennung aus (Geste: \(gesture))"
                    }
                    let lim = reading.speedLimitKmh ?? reading.speedMaxKmh
                    let peak = reading.peakSpeedKmh
                    if reading.hiddenTuningDetected == true
                        || (lim ?? 0) >= SoftUnlockSettings.thresholdKmhSnapshot()
                        || (peak ?? 0) >= SoftUnlockSettings.thresholdKmhSnapshot() {
                        return "Freigeschaltetes Tempo — Geste: \(gesture)"
                    }
                    if reading.hiddenTuningDetected == false {
                        return "Kein Session-Unlock — nach Ausschalten oft unsichtbar"
                    }
                    return "Nicht feststellbar"
                }(),
                erlaeuterung: SoftUnlockSettings.isEnabledSnapshot()
                    ? "Session-Unlock (Wirkung Limit/Peak ≥ \(Int(SoftUnlockSettings.thresholdKmhSnapshot())) km/h). Nach Ausschalten/Panic oft weg — dann zählen persistente Marker und frühere Protokolle."
                    : "Soft-Unlock-Erkennung ist in den Einstellungen ausgeschaltet.",
                raw: reading.hiddenTuningDetected.map { $0 ? "1" : "0" }
            ),
            sessionResetFact(reading: reading, profile: profile, priorUnlock: priorUnlock),
            persistentTuningFact(reading: reading, profile: profile),
            flagFact(id: "flag.unbound", title: "Unbound Rebound", value: reading.unboundRebound, soll: false, inverted: false)
        ]
    }

    /// Vergleicht aktuelle Session mit früherer Auslese derselben SN (ohne Unlock-Geste).
    private static func sessionResetFact(
        reading: IntegrityReading,
        profile: ScooterProfile,
        priorUnlock: PriorUnlockEvidence?
    ) -> MeasuredFact {
        let threshold = SoftUnlockSettings.thresholdKmhSnapshot()
        let currentTempo = max(
            reading.speedLimitKmh ?? 0,
            reading.speedMaxKmh ?? 0,
            reading.peakSpeedKmh ?? 0
        )
        let sessionActive = reading.hiddenTuningDetected == true || currentTempo >= threshold

        guard let prior = priorUnlock, prior.showsUnlock(threshold: threshold) else {
            return MeasuredFact(
                id: "flag.session.reset",
                group: .flags,
                title: "Session nach Ausschalten",
                auslesewert: sessionActive ? "Unlock aktiv" : "kein früherer Unlock-Nachweis",
                sollwert: "persistente Marker / Vorher-Auslese",
                status: .nichtFeststellbar,
                bewertung: sessionActive
                    ? "Aktuelles Session-Unlock sichtbar — Protokoll speichern, bevor ausgeschaltet wird"
                    : "Kein Vergleichsprotokoll mit erhöhtem Tempo für diese SN",
                erlaeuterung: """
                Soft-Unlock verschwindet oft nach Ausschalten. Lösung ohne Tastenkombination: \
                während freigeschaltetem Tempo auslesen und speichern; danach beweisen persistente Marker \
                (gespeichertes Max-Limit, FW, Region, Gänge) bzw. das gespeicherte Protokoll den Zustand.
                """,
                raw: nil
            )
        }

        if sessionActive {
            return MeasuredFact(
                id: "flag.session.reset",
                group: .flags,
                title: "Session nach Ausschalten",
                auslesewert: "Unlock aktiv · früher \(Format.kmh.format(Optional(prior.observedTempoKmh))) (\(prior.protocolNumber))",
                sollwert: "persistente Marker / Vorher-Auslese",
                status: .erheblichAbweichend,
                bewertung: "Aktuell und früher erhöhtes Tempo — Protokoll \(prior.protocolNumber)",
                erlaeuterung: "Frühere Auslese derselben Seriennummer zeigte bereits freigeschaltetes Tempo.",
                raw: prior.protocolNumber
            )
        }

        // Aktuell seriennah, früher Unlock → typisches Ausschalten/Panic.
        let priorPeak = Format.kmh.format(prior.peakSpeedKmh)
        let priorLimit = Format.kmh.format(prior.speedLimitKmh ?? prior.speedMaxKmh)
        return MeasuredFact(
            id: "flag.session.reset",
            group: .flags,
            title: "Session nach Ausschalten",
            auslesewert: "zurückgesetzt · früher Peak \(priorPeak) / Limit \(priorLimit)",
            sollwert: "persistente Marker / Vorher-Auslese",
            status: prior.observedTempoKmh >= profile.tuningClearKmh
                ? .erheblichAbweichend
                : .abweichend,
            bewertung: "Session-Unlock vermutlich nach Ausschalten weg — Nachweis in Protokoll \(prior.protocolNumber)",
            erlaeuterung: """
            Aktuelle Limits wirken seriennah, frühere Auslese derselben SN (\(prior.protocolNumber)) zeigte \
            jedoch erhöhtes Tempo. Das ist typisch für Soft-Unlock nach Power-Off — ohne erneute Freischaltung. \
            Gerichtstauglich bleibt das gespeicherte Vorher-Protokoll plus persistente Marker dieser Auslese.
            """,
            raw: prior.protocolNumber
        )
    }

    /// Marker, die ein Panic-/Soft-Reset typischerweise nicht löscht.
    private static func persistentTuningFact(reading: IntegrityReading, profile: ScooterProfile) -> MeasuredFact {
        var markers: [String] = []
        let custom = CustomFirmwareDiff.analyze(reading: reading, profile: profile)
        if custom.level == .confirmed {
            markers.append("Custom-FW")
        } else if custom.level == .suspected {
            markers.append("FW/Parameter verdächtig")
        }
        for item in custom.diffs.prefix(6) {
            // Kurzformen ohne Duplikat zu Custom-FW
            if item.id.hasPrefix("diff.fw.") { continue }
            if item.id == "diff.softunlock" { continue }
            markers.append(item.title)
        }
        // Dedup
        var seen = Set<String>()
        markers = markers.filter { seen.insert($0).inserted }

        let status: FactStatus
        let bewertung: String
        if markers.isEmpty {
            let limit = reading.speedLimitKmh ?? reading.speedMaxKmh
            status = (limit == nil && reading.gearMax == nil && reading.fwMcu == nil && reading.peakSpeedKmh == nil)
                ? .nichtFeststellbar : .regelkonform
            bewertung = status == .nichtFeststellbar ? "Nicht feststellbar" : "Keine persistenten Tuning-Marker"
        } else if custom.level == .confirmed || custom.severeDiffCount > 0 {
            status = .erheblichAbweichend
            bewertung = "Panic-resistent: \(markers.joined(separator: ", "))"
        } else {
            status = .abweichend
            bewertung = "Verdächtig: \(markers.joined(separator: ", "))"
        }

        return MeasuredFact(
            id: "flag.persistent",
            group: .flags,
            title: "Persistente Tuning-Marker",
            auslesewert: markers.isEmpty ? "—" : markers.joined(separator: ", "),
            sollwert: "keine",
            status: status,
            bewertung: bewertung,
            erlaeuterung: "Hinweise, die Soft-Unlock/Panic typischerweise nicht zurücksetzen: Region-SN, gespeicherte Max-Limits, freigeschaltete Gänge, Custom-FW. Reines Session-Unlock ohne diese Marker ist nach Panic oft unsichtbar.",
            raw: markers.joined(separator: "|")
        )
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
                status: maxGear == nil ? .nichtFeststellbar : ((maxGear ?? 1) > 1 ? .abweichend : .regelkonform),
                bewertung: maxGear == nil ? "Nicht feststellbar" : ((maxGear ?? 1) > 1 ? "Mehr als Serienmodus" : "Serienmodus"),
                erlaeuterung: "Höchster verfügbarer Fahrmodus. Zusatzgänge sind ein persistenter Hinweis, aber allein noch kein Nachweis für Tempo > Typ.",
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

        if let persistent = facts.first(where: { $0.id == "flag.persistent" && $0.status == .erheblichAbweichend }) {
            findings.append(Finding(
                id: "finding.persistent.tuning",
                severity: .erheblichAbweichend,
                title: "Persistente Tuning-Marker (Panic-resistent)",
                detail: persistent.bewertung + " — Soft-Unlock/Panic allein reicht zum Verstecken nicht.",
                relatedFactIds: [persistent.id],
                trackHint: .shu
            ))
        }

        if let reset = facts.first(where: {
            $0.id == "flag.session.reset" && ($0.status == .abweichend || $0.status == .erheblichAbweichend)
        }) {
            findings.append(Finding(
                id: "finding.session.reset",
                severity: reset.status,
                title: "Session-Unlock nach Ausschalten",
                detail: reset.bewertung + " " + reset.erlaeuterung,
                relatedFactIds: [reset.id, "flag.hidden", "flag.persistent"],
                trackHint: .shu
            ))
        }

        if let fw = facts.first(where: {
            $0.id == "fw.analysis" && ($0.status == .abweichend || $0.status == .erheblichAbweichend)
        }) {
            let related = facts.filter { $0.group == .firmware && $0.status != .regelkonform }.map(\.id)
            findings.append(Finding(
                id: "finding.firmware.analysis",
                severity: fw.status,
                title: "Firmware-Analyse auffällig",
                detail: fw.bewertung + " — Modulversionen und Katalogabgleich sind im Protokoll dokumentiert.",
                relatedFactIds: related.isEmpty ? [fw.id] : related,
                trackHint: trackMatch.trackId
            ))
        }

        if let custom = facts.first(where: {
            $0.id == "fw.custom.detect" && ($0.status == .abweichend || $0.status == .erheblichAbweichend)
        }) {
            let related = facts.filter {
                $0.id == "fw.custom.detect" || $0.id == "fw.custom.diff" || $0.id.hasPrefix("diff.")
            }.map(\.id)
            let diffFact = facts.first { $0.id == "fw.custom.diff" }
            findings.append(Finding(
                id: "finding.firmware.custom",
                severity: custom.status,
                title: custom.bewertung,
                detail: (diffFact?.bewertung ?? custom.erlaeuterung)
                    + " Gegenüberstellung: Auslese vs. Hersteller-Serie.",
                relatedFactIds: related,
                trackHint: trackMatch.trackId == .stock ? .webapp : trackMatch.trackId
            ))
        }

        return findings
    }

    // MARK: - EvidenceEngine findings (Anzeige der Engine-Ausgabe)

    private static func evidenceFindings(_ evidence: EvidenceAssessment) -> [Finding] {
        var findings: [Finding] = []
        findings.append(Finding(
            id: "finding.evidence.verdict",
            severity: evidence.verdict == .stock ? .regelkonform
                : (evidence.verdict == .auffaellig ? .abweichend : .erheblichAbweichend),
            title: "Kurzurteil: \(evidence.verdict.label)",
            detail: "Katalog v\(evidence.catalogVersion). \(evidence.shortVerdictText)",
            relatedFactIds: ["evidence.summary"]
        ))
        for line in evidence.decisiveEvidence.prefix(6) {
            findings.append(Finding(
                id: "finding.evidence.decisive.\(findings.count)",
                severity: .abweichend,
                title: "Wesentliche Feststellung",
                detail: line,
                relatedFactIds: ["evidence.summary"]
            ))
        }
        for r in evidence.justifyingMarkers.prefix(6) {
            findings.append(Finding(
                id: "finding.evidence.marker.\(r.fact.markerID)",
                severity: r.classification == .starkerHinweis ? .erheblichAbweichend : .abweichend,
                title: r.plainLanguage.title,
                detail: r.plainLanguage.summary,
                relatedFactIds: ["evidence.\(r.fact.markerID)"]
            ))
        }
        if let attr = evidence.attribution {
            findings.append(Finding(
                id: "finding.evidence.attribution",
                severity: attr.isDeterminate ? .abweichend : .nichtFeststellbar,
                title: "Vermutete Manipulationsart",
                detail: EvidenceExplanationEngine.attributionPlain(attr),
                relatedFactIds: ["evidence.attribution"]
            ))
        }
        for n in evidence.results.flatMap(\.neutralizations).prefix(4) {
            findings.append(Finding(
                id: "finding.evidence.neutral.\(n.ruleId)",
                severity: .regelkonform,
                title: "Neutralisierung \(n.ruleId)",
                detail: "\(n.classBefore.label) → \(n.classAfter.label): \(n.reason)",
                relatedFactIds: ["evidence.summary"]
            ))
        }
        return findings
    }

    private static func enrichFactsWithRawCitations(
        _ facts: [MeasuredFact],
        reading: IntegrityReading,
        profile: ScooterProfile
    ) -> [MeasuredFact] {
        facts.map { fact in
            switch fact.id {
            case "serial.region":
                let sn = reading.serialDisplay ?? reading.serialVcu ?? "—"
                let raw = reading.rawRegisters.last(where: {
                    ["vcu_g3_sn", "dis_sn", "vcu_sn"].contains($0.name)
                })
                let citation: String
                if let raw {
                    citation = "\(raw.name) \(raw.address): Rohwert \(raw.valueHex); interpretiert als \(sn); Typ-Soll: \(profile.market == .de20 ? "DE 1CGB…" : "EU")"
                } else {
                    citation = "SN-Quelle: \(sn); Typ-Soll: \(profile.market == .de20 ? "DE 1CGB…" : "EU")"
                }
                return MeasuredFact(
                    id: fact.id,
                    group: fact.group,
                    title: fact.title,
                    auslesewert: fact.auslesewert,
                    sollwert: fact.sollwert,
                    status: fact.status,
                    bewertung: fact.bewertung,
                    erlaeuterung: citation,
                    raw: citation,
                    volatility: .persistent,
                    evidenceClass: fact.status == .erheblichAbweichend ? .indiz : .abweichung,
                    sourceBoard: raw.map { _ in "VCU/DIS" } ?? "SN",
                    sourceRegister: "0x10",
                    rawHex: raw?.valueHex,
                    resetsOnPowerOff: false
                )
            case "speed.limit", "speed.max", "speed.peak":
                let names: [String]
                switch fact.id {
                case "speed.peak": names = ["dis_trip_max", "vcu_g3_trip_max", "tft_trip_max"]
                case "speed.max": names = ["vcu_g3_maxspd", "vcu_g3_edmax"]
                default: names = ["vcu_g3_maxspd", "dis_limit", "vcu_g3_edmax"]
                }
                let raw = names.compactMap { name in reading.rawRegisters.last(where: { $0.name == name }) }.first
                let vol: MarkerVolatility = fact.id == "speed.peak" ? .semiPersistent : .persistent
                let citation: String
                if let raw {
                    citation = "\(raw.name) \(raw.address): Rohwert \(raw.valueHex)"
                        + (raw.valueDecoded.map { "; interpretiert als \($0)" } ?? "")
                        + "; Typ-Soll: \(fact.sollwert)"
                } else {
                    citation = fact.erlaeuterung
                }
                return MeasuredFact(
                    id: fact.id,
                    group: fact.group,
                    title: fact.title,
                    auslesewert: fact.auslesewert,
                    sollwert: fact.sollwert,
                    status: fact.status,
                    bewertung: fact.bewertung,
                    erlaeuterung: citation,
                    raw: citation,
                    volatility: vol,
                    evidenceClass: fact.status == .erheblichAbweichend ? .indiz : .abweichung,
                    sourceBoard: raw?.name.split(separator: "_").first.map(String.init) ?? "VCU",
                    sourceRegister: raw?.address ?? "—",
                    rawHex: raw?.valueHex,
                    resetsOnPowerOff: vol != .persistent
                )
            default:
                return fact
            }
        }
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

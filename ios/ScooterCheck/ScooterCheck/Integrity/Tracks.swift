import Foundation

// MARK: - Track Pattern

struct TrackPattern: Sendable {
    let id: String
    let trackId: TrackId
    let weight: Double
    let description: String
    let matches: (IntegrityReading, ScooterProfile) -> Bool
}

// MARK: - Track Classifier

enum TrackClassifier {

    // MARK: Firmware Regex

    /// Werkseitige MCU-Firmware (Beispielmuster Ninebot ZT3 Pro).
    static let stockFwRegex = try! NSRegularExpression(
        pattern: #"^(v?)(\d+\.\d+\.\d+)(_[A-Z]{2})?$"#,
        options: [.caseInsensitive]
    )

    /// Web-App-Tuning: modifizierte Suffixe / Build-Kennungen.
    static let webappFwRegex = try! NSRegularExpression(
        pattern: #"^(v?)(\d+\.\d+\.\d+)[-_]?(WEB|WA|MOD|TUNE|CUSTOM|X)([_\-.].*)?$"#,
        options: [.caseInsensitive]
    )

    /// SHU-Tool: charakteristische Build-Strings und Dump-Marker.
    static let shuFwRegex = try! NSRegularExpression(
        pattern: #"^(v?)(\d+\.\d+\.\d+)[-_]?(SHU|SH|DUMP|RAW|PATCH)([_\-.].*)?$"#,
        options: [.caseInsensitive]
    )

    /// Generische Custom-Firmware-Erkennung.
    static let customFwRegex = try! NSRegularExpression(
        pattern: #"^(?!v?\d+\.\d+\.\d+(_[A-Z]{2})?$).*(CUSTOM|MOD|TUNE|SHU|WEB|PATCH|HACK|UNL|XFW).*$"#,
        options: [.caseInsensitive]
    )

    // MARK: Serial Helpers

    static let usSerialPrefixes = ["N2U", "N2GT", "N2UT", "US", "N4GSU"]
    static let euSerialPrefixes = [
        "N2DT", "N2ET", "N2D", "N2E", "N2FS", "N2F", "N2DS",
        "N4GSD", "N4GSE", "N4GS", "DE", "EU"
    ]

    /// SN für Regionserkennung: Fahrzeug-/DIS-SN vor VCU-Board-SN (F3: 1EFH… vor 1EFC…).
    static func preferredRegionSerial(from reading: IntegrityReading) -> String? {
        let candidates = [
            reading.serialDisplay,
            reading.serialBle,
            reading.serialExpected,
            reading.serialVcu,
            reading.serialMcu
        ]
        if let vehicle = candidates.compactMap({ normalizedSerial($0) }).first(where: {
            $0.hasPrefix("1EFJ") || $0.hasPrefix("1EFK") || $0.hasPrefix("1EFH")
                || $0.hasPrefix("1EFG") || $0.hasPrefix("1EFF")
                || $0.hasPrefix("1K1") || $0.hasPrefix("1CG")
                || $0.hasPrefix("N2") || $0.hasPrefix("N4G")
        }) {
            return vehicle
        }
        return candidates.compactMap { normalizedSerial($0) }.first
    }

    static func serialRegion(for serial: String?) -> SerialRegion {
        resolveRegionProfile(for: serial)?.region ?? .unknown
    }

    static func serialRegion(for reading: IntegrityReading) -> SerialRegion {
        resolveRegionProfile(for: reading)?.region ?? .unknown
    }

    static func resolveRegionProfile(for reading: IntegrityReading) -> SerialRegionProfile? {
        resolveRegionProfile(for: preferredRegionSerial(from: reading))
    }

    /// SHU-kompatible Regions-/Marktzuordnung aus dem SN-Präfix (4. Stelle bei F3/G3).
    static func resolveRegionProfile(for serial: String?) -> SerialRegionProfile? {
        guard let serial = normalizedSerial(serial) else { return nil }

        // F3 Pro (Fahrzeug/DIS): 1EFJ=DE, 1EFK=EU, 1EFH=Global 35, 1EFG=US 32, 1EFF=CN.
        if serial.hasPrefix("1EFJ") {
            return .init(region: .de, prefix: "1EFJ", familyLabel: "F3 Pro", marketName: "DE", ratedLimitKmh: 22)
        }
        if serial.hasPrefix("1EFK") {
            return .init(region: .eu, prefix: "1EFK", familyLabel: "F3 Pro", marketName: "EU", ratedLimitKmh: 25)
        }
        if serial.hasPrefix("1EFH") {
            return .init(region: .us, prefix: "1EFH", familyLabel: "F3 Pro", marketName: "Global", ratedLimitKmh: 35)
        }
        if serial.hasPrefix("1EFG") {
            return .init(region: .us, prefix: "1EFG", familyLabel: "F3 Pro", marketName: "US", ratedLimitKmh: 32)
        }
        if serial.hasPrefix("1EFF") {
            return .init(region: .cn, prefix: "1EFF", familyLabel: "F3 Pro", marketName: "CN", ratedLimitKmh: 32)
        }
        // F3 / VCU-Board-Präfixe: 1EFD=DE, 1EFE=EU, 1EFC=Global 35, 1EFB=US 32, 1EFA=CN.
        if serial.hasPrefix("1EFD") {
            return .init(region: .de, prefix: "1EFD", familyLabel: "F3", marketName: "DE", ratedLimitKmh: 22)
        }
        if serial.hasPrefix("1EFE") {
            return .init(region: .eu, prefix: "1EFE", familyLabel: "F3", marketName: "EU", ratedLimitKmh: 25)
        }
        if serial.hasPrefix("1EFC") {
            return .init(region: .us, prefix: "1EFC", familyLabel: "F3", marketName: "Global", ratedLimitKmh: 35)
        }
        if serial.hasPrefix("1EFB") {
            return .init(region: .us, prefix: "1EFB", familyLabel: "F3", marketName: "US", ratedLimitKmh: 32)
        }
        if serial.hasPrefix("1EFA") {
            return .init(region: .cn, prefix: "1EFA", familyLabel: "F3", marketName: "CN", ratedLimitKmh: 32)
        }
        if serial.hasPrefix("1EF") {
            return .init(region: .unknown, prefix: String(serial.prefix(4)), familyLabel: "F3", marketName: "unbekannt", ratedLimitKmh: nil)
        }

        // ZT3 Pro: 1K1D… = DE, 1K1E… = EU.
        if serial.hasPrefix("1K1D") {
            return .init(region: .de, prefix: "1K1D", familyLabel: "ZT3 Pro", marketName: "DE", ratedLimitKmh: 22)
        }
        if serial.hasPrefix("1K1E") {
            return .init(region: .eu, prefix: "1K1E", familyLabel: "ZT3 Pro", marketName: "EU", ratedLimitKmh: 25)
        }

        // Max G3: 1CGB=DE, 1CGE=EU, 1CGC=US, 1CGD=RU.
        if serial.hasPrefix("1CGB") {
            return .init(region: .de, prefix: "1CGB", familyLabel: "Max G3", marketName: "DE", ratedLimitKmh: 22)
        }
        if serial.hasPrefix("1CGE") {
            return .init(region: .eu, prefix: "1CGE", familyLabel: "Max G3", marketName: "EU", ratedLimitKmh: 25)
        }
        if serial.hasPrefix("1CGC") {
            return .init(region: .us, prefix: "1CGC", familyLabel: "Max G3", marketName: "US", ratedLimitKmh: 40)
        }
        if serial.hasPrefix("1CGD") {
            return .init(region: .us, prefix: "1CGD", familyLabel: "Max G3", marketName: "RU", ratedLimitKmh: 40)
        }
        if serial.hasPrefix("1CG") {
            return .init(region: .eu, prefix: String(serial.prefix(4)), familyLabel: "Max G3", marketName: "EU", ratedLimitKmh: 25)
        }

        if usSerialPrefixes.contains(where: { serial.hasPrefix($0) }) {
            return .init(region: .us, prefix: String(serial.prefix(4)), familyLabel: "Ninebot", marketName: "US", ratedLimitKmh: nil)
        }
        if euSerialPrefixes.contains(where: { serial.hasPrefix($0) }) {
            let deLike = serial.hasPrefix("N2DT") || serial.hasPrefix("N2D") || serial.hasPrefix("N4GSD") || serial.hasPrefix("DE")
            return .init(
                region: deLike ? .de : .eu,
                prefix: String(serial.prefix(min(4, serial.count))),
                familyLabel: "Ninebot",
                marketName: deLike ? "DE" : "EU",
                ratedLimitKmh: deLike ? 22 : 25
            )
        }
        if serial.hasPrefix("N4GS") {
            return .init(region: .eu, prefix: "N4GS", familyLabel: "Ninebot", marketName: "EU", ratedLimitKmh: 25)
        }
        if serial.hasPrefix("CN") || serial.hasPrefix("N4GSCN") {
            return .init(region: .cn, prefix: String(serial.prefix(min(4, serial.count))), familyLabel: "Ninebot", marketName: "CN", ratedLimitKmh: nil)
        }
        return nil
    }

    static func serialsMismatch(_ a: String?, _ b: String?) -> Bool {
        guard let a = normalizedSerial(a), let b = normalizedSerial(b) else { return false }
        if a == b { return false }
        // F3 Pro: DIS 1EFH… und VCU 1EFC… teilen denselben Fahrzeug-Suffix.
        if sameEnc2VehicleBody(a, b) { return false }
        return true
    }

    /// Enc2-Board-Präfixe derselben Fahrzeug-SN (z. B. 1EFH… ↔ 1EFC…).
    static func sameEnc2VehicleBody(_ a: String, _ b: String) -> Bool {
        guard a.count >= 10, b.count >= 10 else { return false }
        if a.hasPrefix("1EF"), b.hasPrefix("1EF"), a.dropFirst(4) == b.dropFirst(4) {
            return true
        }
        return false
    }

    static func normalizedSerial(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// MCU-Hardware-SN (z. B. Z07…) weicht auf Max G3 werkseitig von der Fahrzeug-SN ab.
    static func looksLikeModuleSerial(_ value: String?) -> Bool {
        guard let sn = normalizedSerial(value) else { return false }
        if sn.hasPrefix("1CG") || sn.hasPrefix("1EF") || sn.hasPrefix("N4G") || sn.hasPrefix("N2") {
            return false
        }
        // Hex-/MAC-artig oder eigenes MCU-Muster (Z07XB…)
        if sn.hasPrefix("Z07") || sn.hasPrefix("Z0") { return true }
        let hexLike = sn.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789ABCDEF").contains($0) }
        return hexLike && sn.count >= 12
    }

    static func mcuSerialMismatch(reading: IntegrityReading) -> Bool {
        guard let mcu = normalizedSerial(reading.serialMcu) else { return false }
        // Max G3 / x3: MCU-SN ist eine eigene Board-ID, kein Tuning-Marker.
        if looksLikeModuleSerial(mcu) { return false }
        if let vcu = normalizedSerial(reading.serialVcu),
           vcu.hasPrefix("1CG") || vcu.hasPrefix("1EF") {
            return false
        }
        let references = [
            normalizedSerial(reading.serialDisplay),
            normalizedSerial(reading.serialExpected),
            normalizedSerial(reading.serialBle),
            normalizedSerial(reading.serialVcu)
        ].compactMap { $0 }.filter { !looksLikeModuleSerial($0) }
        guard !references.isEmpty else { return false }
        return !references.contains(where: { mcu.hasPrefix(String($0.prefix(10))) || $0.hasPrefix(String(mcu.prefix(10))) })
    }

    static func matchesFwRegex(_ value: String?, regex: NSRegularExpression) -> Bool {
        guard let value, !value.isEmpty else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }

    static func hasCustomFirmware(_ reading: IntegrityReading) -> Bool {
        if reading.fwAppCustom == true { return true }
        if !CfwHardwareForensics.suspiciousMarkers(from: reading).isEmpty { return true }
        let candidates = [reading.fwMcu, reading.fwBle, reading.fwBms, reading.fwVcu, reading.fwEsc]
        return candidates.contains { matchesFwRegex($0, regex: customFwRegex) }
    }

    static func hasHiddenTuningRegister(_ reading: IntegrityReading) -> Bool {
        if reading.hiddenTuningDetected == true { return true }
        return reading.rawRegisters.contains { reg in
            let name = reg.name.uppercased()
            let decoded = (reg.valueDecoded ?? "").uppercased()
            return name.contains("HIDDEN") || name.contains("TUNE") || name.contains("UNLOCK")
                || decoded.contains("TUNED") || decoded == "1" && name.contains("FLAG")
        }
    }

    // MARK: Patterns

    static let patterns: [TrackPattern] = [
        // --- Stock ---
        TrackPattern(
            id: "stock.fw.mcu",
            trackId: .stock,
            weight: 0.15,
            description: "Werkseitige MCU-Firmware erkannt"
        ) { reading, _ in
            matchesFwRegex(reading.fwMcu, regex: stockFwRegex) && !hasCustomFirmware(reading)
        },
        TrackPattern(
            id: "stock.speed.limit",
            trackId: .stock,
            weight: 0.2,
            description: "Geschwindigkeitslimit entspricht Typ"
        ) { reading, profile in
            guard let limit = reading.speedLimitKmh ?? reading.speedRatedKmh else { return false }
            return abs(limit - profile.ratedMaxKmh) <= 1.0
        },
        TrackPattern(
            id: "stock.serial.consistent",
            trackId: .stock,
            weight: 0.15,
            description: "Seriennummern konsistent"
        ) { reading, _ in
            !serialsMismatch(reading.serialDisplay, reading.serialExpected)
                && !mcuSerialMismatch(reading: reading)
        },
        TrackPattern(
            id: "stock.no.flags",
            trackId: .stock,
            weight: 0.1,
            description: "Keine Tuning-Flags gesetzt"
        ) { reading, _ in
            reading.panicModeActive != true
                && reading.hiddenTuningDetected != true
                && reading.unboundRebound != true
        },

        // --- Web-App ---
        TrackPattern(
            id: "webapp.sn.mismatch",
            trackId: .webapp,
            weight: 0.35,
            description: "Angezeigte und erwartete Seriennummer weichen ab"
        ) { reading, _ in
            serialsMismatch(reading.serialDisplay, reading.serialExpected)
        },
        TrackPattern(
            id: "webapp.fw.web",
            trackId: .webapp,
            weight: 0.4,
            description: "Web-App-Firmware-Kennung erkannt"
        ) { reading, _ in
            let candidates = [reading.fwMcu, reading.fwBle, reading.fwVcu]
            return candidates.contains { matchesFwRegex($0, regex: webappFwRegex) }
        },
        TrackPattern(
            id: "webapp.speed.elevated",
            trackId: .webapp,
            weight: 0.3,
            description: "Erhöhtes Geschwindigkeitslimit ohne SHU-Marker"
        ) { reading, profile in
            let limit = reading.speedLimitKmh ?? reading.speedMaxKmh ?? 0
            return limit > profile.tuningSuspectKmh
                && !matchesFwRegex(reading.fwMcu, regex: shuFwRegex)
        },
        TrackPattern(
            id: "webapp.fw.custom",
            trackId: .webapp,
            weight: 0.25,
            description: "Custom-Firmware ohne SHU-Präfix"
        ) { reading, _ in
            hasCustomFirmware(reading)
                && !matchesFwRegex(reading.fwMcu, regex: shuFwRegex)
        },
        TrackPattern(
            id: "webapp.fw.custom.diff",
            trackId: .webapp,
            weight: 0.4,
            description: "Custom-Firmware-Diff zur Hersteller-Serie"
        ) { reading, profile in
            let result = CustomFirmwareDiff.analyze(reading: reading, profile: profile)
            return result.level == .confirmed || (result.level == .suspected && result.severeDiffCount >= 2)
        },

        // --- SHU ---
        TrackPattern(
            id: "shu.fw.shu",
            trackId: .shu,
            weight: 0.45,
            description: "SHU-Firmware-Kennung erkannt"
        ) { reading, _ in
            let candidates = [reading.fwMcu, reading.fwBle, reading.fwVcu, reading.fwEsc]
            return candidates.contains { matchesFwRegex($0, regex: shuFwRegex) }
        },
        TrackPattern(
            id: "shu.mcu.sn.mismatch",
            trackId: .shu,
            weight: 0.4,
            description: "MCU-Seriennummer weicht von Fahrzeug-SN ab"
        ) { reading, _ in
            // Max G3: MCU-Board-SN ≠ Fahrzeug-SN ist normal — kein SHU-Marker.
            mcuSerialMismatch(reading: reading)
        },
        TrackPattern(
            id: "shu.region.us.on.de",
            trackId: .shu,
            weight: 0.45,
            description: "US-/Global-Region-SN auf DE-Sollprofil (Region-Unlock)"
        ) { reading, profile in
            guard profile.market == .de20 else { return false }
            guard profile.family == .maxG3 || profile.family == .ninebotF3 || profile.family == .zt3Pro else {
                return false
            }
            return serialRegion(for: reading).isForeignToGermanStock
        },
        TrackPattern(
            id: "shu.soft.unlock.speed",
            trackId: .shu,
            weight: 0.5,
            description: "Geschwindigkeitslimit über Soft-Unlock-Schwelle"
        ) { reading, profile in
            guard SoftUnlockSettings.isEnabledSnapshot() else { return false }
            guard profile.market == .de20 || profile.usesNinebotEnc2 else { return false }
            let limit = reading.speedLimitKmh ?? reading.speedRatedKmh ?? reading.speedMaxKmh ?? 0
            return limit >= SoftUnlockSettings.thresholdKmhSnapshot()
        },
        TrackPattern(
            id: "shu.persistent.limit",
            trackId: .shu,
            weight: 0.45,
            description: "Persistentes Max-Limit über Schwelle (Panic-resistent)"
        ) { reading, profile in
            guard SoftUnlockSettings.isEnabledSnapshot() else { return false }
            let limit = reading.speedLimitKmh ?? reading.speedMaxKmh ?? 0
            return limit >= SoftUnlockSettings.thresholdKmhSnapshot()
                && (profile.market == .de20 || profile.usesNinebotEnc2)
        },
        TrackPattern(
            id: "shu.trip.peak",
            trackId: .shu,
            weight: 0.55,
            description: "Trip-Spitze über Soft-Unlock-Schwelle"
        ) { reading, profile in
            guard SoftUnlockSettings.isEnabledSnapshot() else { return false }
            let peak = reading.peakSpeedKmh ?? 0
            return peak >= SoftUnlockSettings.thresholdKmhSnapshot()
                && (profile.market == .de20 || profile.usesNinebotEnc2)
        },
        TrackPattern(
            id: "shu.persistent.gears",
            trackId: .shu,
            weight: 0.35,
            description: "Zusatzgänge freigeschaltet (oft panic-resistent)"
        ) { reading, profile in
            (reading.gearMax ?? 0) > profile.stockMaxGear
        },
        TrackPattern(
            id: "shu.persistent.zero.start",
            trackId: .shu,
            weight: 0.4,
            description: "Zero Start — nicht serienmäßig (Manipulationsindiz)"
        ) { reading, profile in
            guard profile.market != .us37 else { return false }
            return (reading.startSpeedKmh ?? -1) < 0.5 && reading.startSpeedKmh != nil
        },
        TrackPattern(
            id: "shu.fw.catalog.miss",
            trackId: .webapp,
            weight: 0.2,
            description: "Firmware nicht im Serienkatalog"
        ) { reading, profile in
            guard StockFirmwareCatalog.entry(for: profile) != nil else { return false }
            let matches = StockFirmwareCatalog.analyze(reading: reading, profile: profile)
                .components.map(\.match)
            return matches.contains(.notInCatalog) || matches.contains(.customMarked)
        },
        TrackPattern(
            id: "shu.hidden.tuning",
            trackId: .shu,
            weight: 0.5,
            description: "Verstecktes Tuning-Flag oder Register"
        ) { reading, _ in
            hasHiddenTuningRegister(reading)
        },
        TrackPattern(
            id: "shu.panic",
            trackId: .shu,
            weight: 0.35,
            description: "Panic-Modus aktiv"
        ) { reading, _ in
            reading.panicModeActive == true
        },
        TrackPattern(
            id: "shu.unbound.rebound",
            trackId: .shu,
            weight: 0.3,
            description: "Unbound-Rebound-Merkmal"
        ) { reading, _ in
            reading.unboundRebound == true
        },
        TrackPattern(
            id: "shu.foreign.us",
            trackId: .shu,
            weight: 0.25,
            description: "US-Seriennummernpräfix bei EU-Typ"
        ) { reading, profile in
            let region = serialRegion(for: reading)
            return region.isForeignToGermanStock && profile.market == .de20
        },

        // --- SHU Dump ---
        // Hinweis: reine Enc2-Auslese (Gen≥2, Hash, viele Register) ist bei Max G3 normal —
        // shu_dump nur bei echten Tuning-Markern oder sehr großem Dump mit SHU-Hinweisen.
        TrackPattern(
            id: "shu_dump.raw.registers",
            trackId: .shuDump,
            weight: 0.2,
            description: "Sehr umfangreiche Rohregister-Auslese"
        ) { reading, _ in
            reading.rawRegisters.count >= 40
                && (hasHiddenTuningRegister(reading) || mcuSerialMismatch(reading: reading)
                    || (reading.speedLimitKmh ?? 0) >= SoftUnlockSettings.thresholdKmhSnapshot())
        },
        TrackPattern(
            id: "shu_dump.live.boards",
            trackId: .shuDump,
            weight: 0.15,
            description: "Viele Live-Boards ausgelesen"
        ) { reading, _ in
            reading.liveBoards.count >= 5
        },
        TrackPattern(
            id: "shu_dump.evidence.hash",
            trackId: .shuDump,
            weight: 0.05,
            description: "Integritäts-Hash vorhanden"
        ) { reading, _ in
            // Hash allein ist kein Tuning — nur leichte Stütze wenn andere Marker da sind.
            guard let hash = reading.evidenceSha256, hash.count == 64 else { return false }
            return hasHiddenTuningRegister(reading)
                || (reading.speedLimitKmh ?? reading.speedRatedKmh ?? 0) >= SoftUnlockSettings.thresholdKmhSnapshot()
        },
        TrackPattern(
            id: "shu_dump.protocol.gen",
            trackId: .shuDump,
            weight: 0.05,
            description: "Erweitertes Protokoll nur mit Tuning-Marker"
        ) { reading, _ in
            // Enc2 Gen2 ist auf Max G3 Standard — nicht als Dump-Marker.
            guard (reading.protocolGen ?? 0) >= 3 else { return false }
            return hasHiddenTuningRegister(reading)
        }
    ]

    // MARK: Classification

    static func classify(reading: IntegrityReading, profile: ScooterProfile) -> TrackMatch {
        var scores: [TrackId: Double] = [:]
        var matchesByTrack: [TrackId: [String]] = [:]

        for pattern in patterns where pattern.matches(reading, profile) {
            scores[pattern.trackId, default: 0] += pattern.weight
            matchesByTrack[pattern.trackId, default: []].append(pattern.description)
        }

        // SHU-Dump erbt SHU-Muster und addiert Dump-Gewicht
        if let shuScore = scores[.shu], let dumpScore = scores[.shuDump], dumpScore > 0 {
            scores[.shuDump] = shuScore * 0.5 + dumpScore
            matchesByTrack[.shuDump, default: []] += matchesByTrack[.shu] ?? []
        }

        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value > 0.15 else {
            return TrackMatch(
                trackId: .unknown,
                confidence: 0,
                matchedPatterns: [],
                explanation: "Es konnten keine hinreichenden Muster für eine Zuordnung ermittelt werden."
            )
        }

        let confidence = min(1.0, best.value / maxScore(for: best.key))
        let explanation = makeExplanation(trackId: best.key, patterns: matchesByTrack[best.key] ?? [])

        return TrackMatch(
            trackId: best.key,
            confidence: confidence,
            matchedPatterns: matchesByTrack[best.key] ?? [],
            explanation: explanation
        )
    }

    private static func maxScore(for trackId: TrackId) -> Double {
        patterns.filter { $0.trackId == trackId }.map(\.weight).reduce(0, +)
    }

    private static func makeExplanation(trackId: TrackId, patterns: [String]) -> String {
        let joined = patterns.prefix(5).joined(separator: "; ")
        switch trackId {
        case .stock:
            return "Die Auslesewerte entsprechen überwiegend einem werkseitigen Konfigurationsprofil. \(joined)"
        case .webapp:
            return "Merkmale einer parameterändernden Web-App wurden erkannt (z. B. SN-Inkonsistenz oder Web-Firmware). \(joined)"
        case .shu:
            return "Merkmale des SHU-Tuning-Werkzeugs wurden erkannt (z. B. MCU-SN-Abweichung, Hidden-Flags, Panic). \(joined)"
        case .shuDump:
            return "Vollständige SHU-Auslese mit Rohregistern und Integritätsnachweis. \(joined)"
        case .unknown:
            return joined
        }
    }
}

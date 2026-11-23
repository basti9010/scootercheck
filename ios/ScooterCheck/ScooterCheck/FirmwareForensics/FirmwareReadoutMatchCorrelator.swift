import Foundation

/// Abgleich hochgeladene Firmware-Datei ↔ Live-Auslese (kein Installationsnachweis).
enum FirmwareReadoutMatchCorrelator {

    enum Verdict: String, Equatable, Codable, Sendable {
        case likelyMatch
        case partial
        case mismatch
        case inconclusive

        var title: String {
            switch self {
            case .likelyMatch: return "Passt weitgehend zur Auslese"
            case .partial: return "Teilweise Übereinstimmung"
            case .mismatch: return "Weicht von der Auslese ab"
            case .inconclusive: return "Abgleich unklar"
            }
        }

        var shortLabel: String {
            switch self {
            case .likelyMatch: return "Passt"
            case .partial: return "Teilweise"
            case .mismatch: return "Weicht ab"
            case .inconclusive: return "Unklar"
            }
        }
    }

    enum CheckStatus: String, Equatable, Codable, Sendable {
        case match
        case mismatch
        case unclear
        case missing
    }

    struct Check: Equatable, Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var status: CheckStatus
        var detail: String
    }

    struct Assessment: Equatable, Codable, Sendable {
        var verdict: Verdict
        var summary: String
        var checks: [Check]
        var caveats: [String]
    }

    static func assess(
        report: FirmwareForensicReport,
        vehicleContext: FirmwareVehicleContext?
    ) -> Assessment {
        guard let ctx = vehicleContext, ctx.fromLiveReadout else {
            return Assessment(
                verdict: .inconclusive,
                summary: "Keine Live-Auslese — Abgleich Datei↔Scooter nicht möglich.",
                checks: [],
                caveats: Self.standardCaveats
            )
        }

        var checks: [Check] = []

        // Modell
        checks.append(modelCheck(meta: report.meta, fileName: report.originalFileName, ctx: ctx))

        // Steuergerät-Typ
        checks.append(controllerCheck(meta: report.meta, fileName: report.originalFileName, ctx: ctx))

        // Versions-/Namen-Tokens vs. fwVcu/MCU/BLE
        checks.append(versionCheck(meta: report.meta, fileName: report.originalFileName, ctx: ctx))

        // Speed: Datei-Deep-Analysis vs. Live Limit/Peak
        checks.append(speedCheck(deep: report.deepAnalysis, ctx: ctx, fileName: report.originalFileName))

        let matchN = checks.filter { $0.status == .match }.count
        let mismatchN = checks.filter { $0.status == .mismatch }.count
        let decisive = checks.filter { $0.status == .match || $0.status == .mismatch }.count

        let verdict: Verdict
        if decisive == 0 {
            verdict = .inconclusive
        } else if mismatchN == 0 && matchN >= 2 {
            verdict = .likelyMatch
        } else if mismatchN >= 2 {
            verdict = .mismatch
        } else if mismatchN == 1 && matchN >= 1 {
            verdict = .partial
        } else if matchN >= 1 {
            verdict = .partial
        } else {
            verdict = .inconclusive
        }

        let summary: String
        switch verdict {
        case .likelyMatch:
            summary = "Mehrere Merkmale der Datei passen zur Auslese (Modell/Version/Limits). Das beweist nicht, dass dieses Image aktuell geflasht ist."
        case .partial:
            summary = "Einige Merkmale passen, andere weichen ab oder fehlen — Datei und Scooter-Stand können zusammenhängen, sind aber nicht deckungsgleich nachgewiesen."
        case .mismatch:
            summary = "Wesentliche Abweichungen zwischen Datei und Auslese (z. B. Modell oder Speed-Bild). Datei wahrscheinlich nicht der aktuelle Stand bzw. anderes Image."
        case .inconclusive:
            summary = "Zu wenig vergleichbare Felder (Meta/Version/Speeds) für einen belastbaren Abgleich."
        }

        return Assessment(
            verdict: verdict,
            summary: summary,
            checks: checks,
            caveats: Self.standardCaveats
        )
    }

    // MARK: - Checks

    private static func modelCheck(meta: FirmwarePackageMeta, fileName: String, ctx: FirmwareVehicleContext) -> Check {
        let packageModels = meta.models.map { $0.lowercased() }
        let fromName = modelTokens(from: fileName)
        let allPkg = Set(packageModels + fromName)
        let label = (ctx.modelLabel ?? ctx.profileId ?? "").lowercased()
        guard !allPkg.isEmpty, !label.isEmpty else {
            return Check(
                id: "model",
                title: "Modell",
                status: .missing,
                detail: "Paket: \(packageModels.joined(separator: "/").nilIfEmpty ?? "—") · Auslese: \(ctx.modelLabel ?? "—")"
            )
        }
        let hit = allPkg.contains { pkg in
            label.contains(pkg) || pkg.contains(label) || label.contains(String(pkg.prefix(3)))
        }
        return Check(
            id: "model",
            title: "Modell",
            status: hit ? .match : .mismatch,
            detail: "Paket \(Array(allPkg).sorted().joined(separator: "/")) · Auslese \(ctx.modelLabel ?? label)"
        )
    }

    private static func controllerCheck(meta: FirmwarePackageMeta, fileName: String, ctx: FirmwareVehicleContext) -> Check {
        let pkg = (meta.type ?? controllerToken(from: fileName) ?? "").uppercased()
        let liveHasVcu = ctx.fwVcu != nil
        guard !pkg.isEmpty else {
            return Check(id: "controller", title: "Steuergerät", status: .missing, detail: "Kein Typ in info.json/Dateiname")
        }
        if pkg.contains("VCU"), liveHasVcu {
            return Check(id: "controller", title: "Steuergerät", status: .match, detail: "Paket \(pkg) · Auslese liefert VCU-FW \(ctx.fwVcu ?? "—")")
        }
        if pkg.contains("MCU"), ctx.fwMcu != nil {
            return Check(id: "controller", title: "Steuergerät", status: .match, detail: "Paket \(pkg) · Auslese MCU \(ctx.fwMcu ?? "—")")
        }
        if pkg.contains("BLE"), ctx.fwBle != nil {
            return Check(id: "controller", title: "Steuergerät", status: .match, detail: "Paket \(pkg) · Auslese BLE \(ctx.fwBle ?? "—")")
        }
        return Check(
            id: "controller",
            title: "Steuergerät",
            status: liveHasVcu || ctx.fwMcu != nil ? .unclear : .missing,
            detail: "Paket \(pkg) · Auslese VCU \(ctx.fwVcu ?? "—") / MCU \(ctx.fwMcu ?? "—")"
        )
    }

    private static func versionCheck(meta: FirmwarePackageMeta, fileName: String, ctx: FirmwareVehicleContext) -> Check {
        let hay = [meta.displayName, meta.rawInfoJSON, fileName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let liveVersions = [ctx.fwVcu, ctx.fwMcu, ctx.fwBle, ctx.fwEsc]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !liveVersions.isEmpty else {
            return Check(id: "version", title: "Firmware-Version", status: .missing, detail: "Keine FW-Version in der Auslese")
        }

        var hits: [String] = []
        for v in liveVersions {
            let norm = normalizeVersion(v)
            if hay.contains(v.lowercased()) || (!norm.isEmpty && hay.contains(norm)) {
                hits.append(v)
            }
            // compact forms 1.2.1 → 121 / 1_2_1
            let digits = v.filter(\.isNumber)
            if digits.count >= 3, hay.contains(digits) {
                hits.append(v)
            }
        }
        if !hits.isEmpty {
            return Check(
                id: "version",
                title: "Firmware-Version",
                status: .match,
                detail: "Auslese \(hits.joined(separator: ", ")) kommt in Dateiname/Meta vor"
            )
        }
        if meta.displayName != nil || !(meta.rawInfoJSON ?? "").isEmpty {
            return Check(
                id: "version",
                title: "Firmware-Version",
                status: .unclear,
                detail: "Auslese \(liveVersions.joined(separator: ", ")) — kein klarer Treffer in Meta/Name „\(meta.displayName ?? fileName)“"
            )
        }
        return Check(
            id: "version",
            title: "Firmware-Version",
            status: .unclear,
            detail: "Auslese \(liveVersions.joined(separator: ", ")) — Paket ohne vergleichbare Versionsangabe"
        )
    }

    private static func speedCheck(
        deep: FirmwareDeepAnalysisResult?,
        ctx: FirmwareVehicleContext,
        fileName: String
    ) -> Check {
        let liveLimit = ctx.speedLimitKmh
        let liveMax = ctx.speedMaxKmh
        let livePeak = ctx.peakSpeedKmh
        let liveVals = [liveLimit, liveMax, livePeak].compactMap { $0 }.filter { $0 > 0 }

        let fileSpeeds = deep?.speedLimits.map(\.kmh) ?? []
        let fileMax = deep?.maxSpeedKmhInCode
        let nameClaim = claimedKmh(from: fileName)

        guard !liveVals.isEmpty || fileMax != nil || nameClaim != nil else {
            return Check(id: "speed", title: "Geschwindigkeitsbild", status: .missing, detail: "Keine Speed-Daten Datei/Auslese")
        }

        var details: [String] = []
        if let liveLimit { details.append("Limit \(Int(liveLimit))") }
        if let livePeak { details.append("Peak \(Int(livePeak))") }
        if let fileMax { details.append("Datei-Max \(Int(fileMax))") }
        if let nameClaim { details.append("Dateiname \(nameClaim) km/h") }

        // Live limit close to a file speed constant
        if let lim = liveLimit, !fileSpeeds.isEmpty {
            let near = fileSpeeds.contains { abs($0 - lim) <= 1.5 }
            if near {
                return Check(
                    id: "speed",
                    title: "Geschwindigkeitsbild",
                    status: .match,
                    detail: "Live-Limit \(Int(lim)) km/h liegt nahe einer Code-Stufe · \(details.joined(separator: " · "))"
                )
            }
        }

        // Filename claim vs live
        if let claim = nameClaim, let lim = liveLimit {
            if abs(Double(claim) - lim) <= 2 {
                return Check(
                    id: "speed",
                    title: "Geschwindigkeitsbild",
                    status: .match,
                    detail: "Dateiname \(claim) km/h ≈ Live-Limit \(Int(lim)) · \(details.joined(separator: " · "))"
                )
            }
            if lim + 5 < Double(claim), (fileMax ?? 999) >= Double(claim) {
                return Check(
                    id: "speed",
                    title: "Geschwindigkeitsbild",
                    status: .mismatch,
                    detail: "Dateiname behauptet \(claim) km/h, Live-Limit nur \(Int(lim)) — Stand evtl. legal/locked · \(details.joined(separator: " · "))"
                )
            }
        }

        // File open-cap much higher than live stock-like limit
        if let fileMax, let lim = liveLimit, fileMax >= 35, lim <= 25 {
            return Check(
                id: "speed",
                title: "Geschwindigkeitsbild",
                status: .unclear,
                detail: "Datei kennt bis \(Int(fileMax)) km/h, Live-Limit \(Int(lim)) — typisch bei Soft-Unlock/Legal-Modus · \(details.joined(separator: " · "))"
            )
        }

        if fileSpeeds.isEmpty {
            return Check(
                id: "speed",
                title: "Geschwindigkeitsbild",
                status: .unclear,
                detail: details.joined(separator: " · ").nilIfEmpty ?? "Keine Code-Speeds"
            )
        }

        return Check(
            id: "speed",
            title: "Geschwindigkeitsbild",
            status: .unclear,
            detail: details.joined(separator: " · ")
        )
    }

    // MARK: - Helpers

    private static var standardCaveats: [String] {
        [
            "Kein kryptografischer Abgleich mit dem Flash-Inhalt — BLE liefert keine Image-Hashes.",
            "Übereinstimmung heißt Zuordnung/Plausibilität, nicht Installationsnachweis.",
            "Bei Soft-Unlock kann Live-Limit legal-nah sein, obwohl die Datei offene Caps enthält."
        ]
    }

    private static func modelTokens(from fileName: String) -> [String] {
        let l = fileName.lowercased()
        var out: [String] = []
        for token in ["zt3", "g3", "f2", "f3", "max", "pro", "g2", "e25", "e22", "esx"] {
            if l.contains(token) { out.append(token) }
        }
        return out
    }

    private static func controllerToken(from fileName: String) -> String? {
        let l = fileName.uppercased()
        if l.contains("VCU") { return "VCU" }
        if l.contains("MCU") { return "MCU" }
        if l.contains("BLE") { return "BLE" }
        if l.contains("BMS") { return "BMS" }
        return nil
    }

    private static func claimedKmh(from fileName: String) -> Int? {
        // e.g. ZT3_VCU_48KMH / 48kmh / 48_kmh
        let pattern = #"(\d{2,3})\s*[-_]?kmh"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let m = re.firstMatch(in: fileName, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: fileName),
              let v = Int(fileName[r]), v >= 15, v <= 120
        else { return nil }
        return v
    }

    private static func normalizeVersion(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: ".")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

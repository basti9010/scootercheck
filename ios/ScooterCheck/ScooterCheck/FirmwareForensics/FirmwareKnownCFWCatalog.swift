import Foundation

/// Bekannte CFW-/Panic-Signaturen (Hash + dokumentiertes Verhalten).
/// Wird lokal angewendet, wenn ENC nicht lesbar ist — gleiche Qualität wie Forum+Lab-Auswertung.
enum FirmwareKnownCFWCatalog {

    struct Entry: Equatable, Sendable {
        var md5Enc: String?
        var sha256Enc: String?
        var displayName: String
        var models: [String]
        var controllerType: String
        var speedLimitsKmh: [(Double, FirmwareSpeedLimitRole)]
        var transitions: [(title: String, trigger: String, effect: String)]
        var inputs: [(FirmwareInputKind, String)]
        var comboSummaries: [String]
        var provenance: String
    }

    /// G3_VCU_Panicbutton_2026 / Starke-Tech — aus Forum + Decompile FIRM2.dec.bin.c
    static let g3PanicbuttonStarkeTech = Entry(
        md5Enc: "0a567b134861a5f9f7e4683e63d8f4a8",
        sha256Enc: "929a01874b64c1e7dd075648d45d0c12305bff9bb3cc236d58a3fb6e1dba2180",
        displayName: "Panicbutton (Starke-Tech.de)",
        models: ["g3"],
        controllerType: "VCU",
        speedLimitsKmh: [
            (20, .legalCap),
            (22, .legalCap),
            (25, .regionOrMode),
            (32, .intermediate),
            (99, .openCap)
        ],
        transitions: [
            (
                "Power-Modus (offen)",
                "Gas + Bremse halten und Power einschalten",
                "Offene Limits (Code: u. a. 0x6300 ≈ 99 km/h)"
            ),
            (
                "StVZO-/Legal-Modus",
                "Normal einschalten oder Reboot ohne Gas/Bremse; bzw. Panic-Button",
                "Begrenzt auf legal-nahe Stufe (Code: u. a. 0x1600 ≈ 22 km/h)"
            ),
            (
                "Fliegender Panic",
                "Zugewiesener Custom-Button am Lenker während der Fahrt",
                "Sofort zurück auf legal-nahe Begrenzung ohne sichtbaren Neustart"
            )
        ],
        inputs: [
            (.throttle, "Forum + Dual-Analog-Muster im Decompile (Schwelle ~400)"),
            (.brake, "Forum + Dual-Analog-Muster im Decompile (Schwelle ~400)"),
            (.power, "Einschalt-Kombi mit Gas+Bremse"),
            (.customButton, "Forum: Panicbutton-ZIP — physischer Index im Code nicht beschriftet"),
            (.dualAnalog, "FUN_000020ac: zwei Kanäle, Maske 3 = beide")
        ],
        comboSummaries: [
            "Aktivierung offen: Gas + Bremse + Power ein",
            "Panic / legal: Custom-Button oder Reboot ohne Gas/Bremse"
        ],
        provenance: "RollerPlausch G3 Panicbutton 2026 + lokale Decompile-Auswertung FIRM2.dec.bin.c"
    )

    static let all: [Entry] = [g3PanicbuttonStarkeTech]

    static func match(md5: String?, sha256: String?) -> Entry? {
        let md5l = md5?.lowercased()
        let sha = sha256?.lowercased()
        return all.first { e in
            if let a = e.md5Enc, let b = md5l, a == b { return true }
            if let a = e.sha256Enc, let b = sha, a == b { return true }
            return false
        }
    }

    static func deepAnalysis(for entry: Entry, subjectSHA256: String) -> FirmwareDeepAnalysisResult {
        let speeds: [FirmwareSpeedLimitFinding] = entry.speedLimitsKmh.enumerated().map { idx, pair in
            let packed = FirmwareSpeedSignatureExtractor.knownPackedSpeeds.first { abs($0.1 - pair.0) < 0.1 }?.0
            return FirmwareSpeedLimitFinding(
                id: "cat-spd-\(idx)-\(Int(pair.0))",
                kmh: pair.0,
                packedU16: packed,
                role: pair.1,
                evidence: entry.provenance,
                source: .knownCatalog,
                confidence: .high
            )
        }
        let transitions: [FirmwareModeTransitionFinding] = entry.transitions.enumerated().map { idx, t in
            .init(
                id: "cat-tr-\(idx)",
                title: t.title,
                trigger: t.trigger,
                effect: t.effect,
                evidence: entry.provenance,
                source: .knownCatalog,
                confidence: .high
            )
        }
        let inputs: [FirmwareInputHintFinding] = entry.inputs.enumerated().map { idx, i in
            .init(
                id: "cat-in-\(idx)",
                kind: i.0,
                detail: i.1,
                evidence: entry.provenance,
                source: .knownCatalog,
                confidence: i.0 == .customButton ? .medium : .high
            )
        }
        return FirmwareDeepAnalysisResult(
            schemaVersion: FirmwareDeepAnalysisResult.currentSchemaVersion,
            producedAt: Date(),
            sources: [.knownCatalog],
            subjectSHA256: subjectSHA256,
            packageDisplayName: entry.displayName,
            models: entry.models,
            controllerType: entry.controllerType,
            speedLimits: speeds,
            maxSpeedKmhInCode: entry.speedLimitsKmh.map(\.0).max(),
            legalCapKmhInCode: entry.speedLimitsKmh.filter { $0.1 == .legalCap }.map(\.0).min(),
            modeTransitions: transitions,
            inputHints: inputs,
            comboSummaries: entry.comboSummaries,
            notes: ["Treffer über bekannte Payload-Hash-Signatur (ohne ENC-Decrypt)."],
            caveats: FirmwareDeepAnalysisResult.standardCaveats,
            quality: FirmwareDeepAnalysisQuality(
                hasDeterministicBasis: true,
                llmSchemaValidated: false,
                summary: "Katalog-Signatur: Limits und Combos aus verifizierter Auswertung."
            )
        )
    }
}

import Foundation

/// Bekannte CFW-/Panic-Signaturen (Hash + dokumentiertes Verhalten).
/// Wird lokal angewendet, wenn ENC nicht lesbar ist — gleiche Qualität wie Forum+Lab-Auswertung.
enum FirmwareKnownCFWCatalog {

    struct SpeedLimitSpec: Equatable, Sendable {
        var kmh: Double
        var role: FirmwareSpeedLimitRole
    }

    struct TransitionSpec: Equatable, Sendable {
        var title: String
        var trigger: String
        var effect: String
    }

    struct InputSpec: Equatable, Sendable {
        var kind: FirmwareInputKind
        var detail: String
    }

    struct Entry: Equatable, Sendable {
        var md5Enc: String?
        var sha256Enc: String?
        var displayName: String
        var models: [String]
        var controllerType: String
        var speedLimitsKmh: [SpeedLimitSpec]
        var transitions: [TransitionSpec]
        var inputs: [InputSpec]
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
            .init(kmh: 20, role: .legalCap),
            .init(kmh: 22, role: .legalCap),
            .init(kmh: 25, role: .regionOrMode),
            .init(kmh: 32, role: .intermediate),
            .init(kmh: 99, role: .openCap)
        ],
        transitions: [
            .init(
                title: "Zwei Limit-Welten (Katalog-Hash)",
                trigger: "Aus Code nicht als Tastenfolge belegt",
                effect: "Legal-nahe und offene Caps im Image (u. a. ~22 / ~99 km/h)"
            ),
            .init(
                title: "Panic-/Legal-Clamp (Katalog-Hash)",
                trigger: "Aus Code nicht als Tastenfolge belegt",
                effect: "Panic-Pfad schreibt legal-nahe Stufe (u. a. 0x1600 ≈ 22 km/h) — Tastenfolge separat live prüfen"
            )
        ],
        inputs: [
            .init(kind: .customButton, detail: "Panicbutton-Familie: Event-Flag im Code, physische Taste nicht aus Hash belegt"),
            .init(kind: .dualAnalog, detail: "Dual-Analog-Token möglich — keine validierte Unlock-Kombi")
        ],
        comboSummaries: [],
        provenance: "Hash-Katalog G3 Panicbutton 2026 — Speeds belegt, Soft-Unlock-Tastenfolge bewusst nicht geraten"
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
        let speeds: [FirmwareSpeedLimitFinding] = entry.speedLimitsKmh.enumerated().map { idx, lim in
            let packed = FirmwareSpeedSignatureExtractor.knownPackedSpeeds.first { abs($0.1 - lim.kmh) < 0.1 }?.0
            return FirmwareSpeedLimitFinding(
                id: "cat-spd-\(idx)-\(Int(lim.kmh))",
                kmh: lim.kmh,
                packedU16: packed,
                role: lim.role,
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
                kind: i.kind,
                detail: i.detail,
                evidence: entry.provenance,
                source: .knownCatalog,
                confidence: i.kind == .customButton ? .medium : .high
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
            maxSpeedKmhInCode: entry.speedLimitsKmh.map(\.kmh).max(),
            legalCapKmhInCode: entry.speedLimitsKmh.filter { $0.role == .legalCap }.map(\.kmh).min(),
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

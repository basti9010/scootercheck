import Foundation

/// Deterministische Modus-/Eingabe-Hinweise aus Speed-Paaren und optionalem Decompile-Text.
/// Erfindet keine physischen Unlock-Tastenfolgen — die gehören nur in validierte Live-/Belegt-Zeilen.
enum FirmwareComboExtractor {

    struct Pack: Equatable, Sendable {
        var transitions: [FirmwareModeTransitionFinding]
        var inputs: [FirmwareInputHintFinding]
        var comboSummaries: [String]
    }

    static func extract(
        speeds: [FirmwareSpeedLimitFinding],
        decompiledText: String?,
        source: FirmwareDeepAnalysisSource
    ) -> Pack {
        var transitions: [FirmwareModeTransitionFinding] = []
        var inputs: [FirmwareInputHintFinding] = []
        // Absichtlich leer: spekulative Gas/Bremse/Power-Texte sind verboten.
        let combos: [String] = []

        let legal = speeds.filter { $0.role == .legalCap }
        let openCaps = speeds.filter { $0.role == .openCap }

        if let legalKmh = legal.map(\.kmh).min(), let openKmh = openCaps.map(\.kmh).max() {
            transitions.append(.init(
                id: "tr-dual-mode",
                title: "Zwei Limit-Welten im Code",
                trigger: FirmwareComboPolicy.unbelegtTrigger,
                effect: "Umschalten zwischen ~\(Int(legalKmh)) km/h (legal-nah) und ~\(Int(openKmh)) km/h (offen)",
                evidence: "Speed-Paar legalCap + openCap",
                source: source,
                confidence: .medium
            ))
        }

        let text = (decompiledText ?? "").lowercased()
        guard !text.isEmpty else {
            return Pack(transitions: transitions, inputs: inputs, comboSummaries: combos)
        }

        let dual = text.contains("dual")
            || text.contains("both channel")
            || text.contains("two channel")
            || (text.contains("mask") && text.contains("3"))
            || text.range(of: #"&\s*3\b"#, options: .regularExpression) != nil
        let throttleish = (text.contains("throttle") || text.contains("gas") || text.contains("accel") || text.contains("adc"))
            && (text.contains("400") || text.contains("brake") || text.contains("bremse") || text.contains("lever"))
        let brakeish = text.contains("brake") || text.contains("bremse") || text.contains("lever")
        let powerish = text.contains("power") || text.contains("boot") || text.contains("startup") || text.contains("ignition")
        let panicish = text.contains("panic") || text.contains("softunlock") || text.contains("soft_unlock")
            || text.contains("custombutton") || text.contains("custom button")

        if dual || (throttleish && brakeish) {
            inputs.append(.init(
                id: "in-dual",
                kind: .dualAnalog,
                detail: "Decompile: zwei Analog-/Eingangskanäle (Token-Muster)",
                evidence: "Textmuster dual/mask&3 / throttle+brake",
                source: source,
                confidence: .low
            ))
            if throttleish {
                inputs.append(.init(
                    id: "in-throttle",
                    kind: .throttle,
                    detail: "Gas-/Throttle-Token im Decompile",
                    evidence: "Decompile-Token",
                    source: source,
                    confidence: .low
                ))
            }
            if brakeish {
                inputs.append(.init(
                    id: "in-brake",
                    kind: .brake,
                    detail: "Brems-/Hebel-Token im Decompile",
                    evidence: "Decompile-Token",
                    source: source,
                    confidence: .low
                ))
            }
            if powerish {
                inputs.append(.init(
                    id: "in-power",
                    kind: .power,
                    detail: "Power/Boot-Token im Decompile",
                    evidence: "Decompile-Token power/boot/startup",
                    source: source,
                    confidence: .low
                ))
            }
        }

        if panicish {
            inputs.append(.init(
                id: "in-custom",
                kind: .customButton,
                detail: "Panic/Custom-Token im Decompile/String",
                evidence: "Token panic/softunlock/custom",
                source: source,
                confidence: .low
            ))
            transitions.append(.init(
                id: "tr-panic",
                title: "Panic-/Legal-Pfad (Token)",
                trigger: FirmwareComboPolicy.unbelegtTrigger,
                effect: "Hinweis auf Legal-Rückfall-Pfad — Tastenfolge nicht belegt",
                evidence: "Panic/SoftUnlock-Token im Decompile",
                source: source,
                confidence: .low
            ))
        }

        return Pack(transitions: transitions, inputs: inputs, comboSummaries: combos)
    }
}

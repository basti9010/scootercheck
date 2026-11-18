import Foundation

/// Deterministische Combo-/Modus-Hinweise aus Speed-Paaren und optionalem Decompile-Text.
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
        var combos: [String] = []

        let legal = speeds.filter { $0.role == .legalCap }
        let openCaps = speeds.filter { $0.role == .openCap }
        let region = speeds.filter { $0.role == .regionOrMode }

        if let legalKmh = legal.map(\.kmh).min(), let openKmh = openCaps.map(\.kmh).max() {
            transitions.append(.init(
                id: "tr-dual-mode",
                title: "Zwei Limit-Welten im Code",
                trigger: "Einschalt-/Tastenkombi oder Panic (modellabhängig)",
                effect: "Umschalten zwischen ~\(Int(legalKmh)) km/h (legal-nah) und ~\(Int(openKmh)) km/h (offen)",
                evidence: "Speed-Paar legalCap + openCap",
                source: source,
                confidence: .medium
            ))
            combos.append(
                "Vermutete Soft-/Power-Kombi: Umschalten \(Int(legalKmh)) ↔ \(Int(openKmh)) km/h (häufig Gas + Bremse + Power — Live-Test nötig)"
            )
            combos.append(
                "Panic/Legal-Rückfall: oft Reboot ohne Gas/Bremse oder Extra-Taste → ~\(Int(legalKmh)) km/h"
            )
        } else if let legalKmh = legal.map(\.kmh).min(), !region.isEmpty {
            let regionLabel = region.map { "\(Int($0.kmh))" }.joined(separator: "/")
            combos.append("Regions-/Modusstufen neben Legal-Kappe (\(Int(legalKmh)) / \(regionLabel) km/h)")
        }

        let text = (decompiledText ?? "").lowercased()
        guard !text.isEmpty else {
            return Pack(transitions: transitions, inputs: inputs, comboSummaries: uniq(combos))
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
                detail: "Decompile: zwei Analog-/Eingangskanäle (Gas/Bremse-Muster)",
                evidence: "Textmuster dual/mask&3 / throttle+brake",
                source: source,
                confidence: .medium
            ))
            inputs.append(.init(
                id: "in-throttle",
                kind: .throttle,
                detail: "Gas-/Throttle-Kanal im Decompile angedeutet",
                evidence: "Decompile-Token",
                source: source,
                confidence: .low
            ))
            inputs.append(.init(
                id: "in-brake",
                kind: .brake,
                detail: "Brems-/Hebel-Kanal im Decompile angedeutet",
                evidence: "Decompile-Token",
                source: source,
                confidence: .low
            ))
            combos.append("Decompile: Gas + Bremse als gemeinsame Bedingung wahrscheinlich")
            if powerish {
                inputs.append(.init(
                    id: "in-power",
                    kind: .power,
                    detail: "Power/Boot-Kontext neben Eingangsprüfung",
                    evidence: "Decompile-Token power/boot/startup",
                    source: source,
                    confidence: .medium
                ))
                transitions.append(.init(
                    id: "tr-power-combo",
                    title: "Einschalt-Kombi (vermutet)",
                    trigger: "Gas + Bremse halten und Power einschalten",
                    effect: "Offene Limits aktivieren (wenn openCap im Code)",
                    evidence: "Dual-Eingang + Power/Boot im Decompile",
                    source: source,
                    confidence: .medium
                ))
                combos.append("Aktivierung offen (vermutet): Gas + Bremse + Power ein")
            }
        }

        if panicish {
            inputs.append(.init(
                id: "in-custom",
                kind: .customButton,
                detail: "Panic/Custom-Button-Hinweis im Decompile/String",
                evidence: "Token panic/softunlock/custom",
                source: source,
                confidence: .medium
            ))
            transitions.append(.init(
                id: "tr-panic",
                title: "Panic / Legal-Rückfall (vermutet)",
                trigger: "Extra-Taste oder Reboot ohne Gas/Bremse",
                effect: "Sofort oder nach Neustart zurück auf legal-nahe Begrenzung",
                evidence: "Panic/SoftUnlock-Token im Decompile",
                source: source,
                confidence: .medium
            ))
            combos.append("Panic/Legal: Custom-Button oder Reboot ohne Gas/Bremse (vermutet)")
        }

        return Pack(transitions: transitions, inputs: inputs, comboSummaries: uniq(combos))
    }

    private static func uniq(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

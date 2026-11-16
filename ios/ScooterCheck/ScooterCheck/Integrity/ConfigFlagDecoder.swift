import Foundation

/// Bekannte Bitlabels für VCU-Config-Flags (NootNooot Command Reference).
/// Nur Lesen — Fun2/Fun3 und Custom Key ohne öffentliche Bittabelle bleiben Roh-Hex.
enum ConfigFlagDecoder {

    struct BitLabel: Equatable, Sendable {
        let mask: UInt16
        let label: String
    }

    /// rBool 0x1C — dokumentierte Toggle-Bits.
    static let boolBits: [BitLabel] = [
        BitLabel(mask: 0x0040, label: "Entsperr-PIN aktiv"),
    ]

    /// rFunBool 0x1D — dokumentierte Toggle-Bits (manche Flags können modellabhängig invertiert sein).
    static let funBoolBits: [BitLabel] = [
        BitLabel(mask: 0x0002, label: "Always-on / Assist-Modus"),
        BitLabel(mask: 0x0004, label: "Auto-Key-Lock / Walk-away-Lock"),
        BitLabel(mask: 0x0080, label: "Erweiterte Reichweite bei niedrigem Akku"),
        BitLabel(mask: 0x0100, label: "Park-Erkennung"),
        BitLabel(mask: 0x0200, label: "Sitz-Erkennung"),
        BitLabel(mask: 0x0400, label: "Streamline-Rücklicht"),
        BitLabel(mask: 0x0800, label: "Blinker Auto-Aus"),
        BitLabel(mask: 0x2000, label: "Rückwärtsfahrt"),
        BitLabel(mask: 0x4000, label: "Restreichweite anzeigen"),
    ]

    struct DecodeResult: Equatable, Sendable {
        let hex: String
        let raw: UInt16
        let activeLabels: [String]
        let unknownMask: UInt16

        var displayValue: String {
            if activeLabels.isEmpty {
                if unknownMask == 0 {
                    return hex
                }
                return "\(hex) — unbekannte Bits 0x\(String(format: "%04X", unknownMask))"
            }
            var parts = ["\(hex) — \(activeLabels.joined(separator: "; "))"]
            if unknownMask != 0 {
                parts.append("Rest 0x\(String(format: "%04X", unknownMask))")
            }
            return parts.joined(separator: "; ")
        }

        var explanationSuffix: String {
            if activeLabels.isEmpty, unknownMask == 0 {
                return "Keine gesetzten bekannten Bits."
            }
            if !activeLabels.isEmpty, unknownMask == 0 {
                return "Bekannte Bits laut NootNooot Command Reference (modellabhängig, ggf. invertiert)."
            }
            if !activeLabels.isEmpty {
                return "Teilweise dekodiert; Restbits ohne öffentliche Labels."
            }
            return "Nur unbekannte Bits — keine öffentlichen Labels für dieses Muster."
        }
    }

    static func parseHex(_ hex: String) -> UInt16? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        guard !s.isEmpty, let value = UInt16(s, radix: 16) else { return nil }
        return value
    }

    static func decode(hex: String, knownBits: [BitLabel]) -> DecodeResult? {
        guard let raw = parseHex(hex) else { return nil }
        var matched: UInt16 = 0
        var labels: [String] = []
        for bit in knownBits where (raw & bit.mask) == bit.mask {
            matched |= bit.mask
            labels.append(bit.label)
        }
        let formatted = "0x\(String(format: "%04X", raw))"
        return DecodeResult(
            hex: formatted,
            raw: raw,
            activeLabels: labels,
            unknownMask: raw & ~matched
        )
    }

    static func decodeBool(hex: String) -> DecodeResult? {
        decode(hex: hex, knownBits: boolBits)
    }

    static func decodeFunBool(hex: String) -> DecodeResult? {
        decode(hex: hex, knownBits: funBoolBits)
    }
}

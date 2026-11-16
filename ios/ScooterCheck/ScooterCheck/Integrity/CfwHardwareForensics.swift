import Foundation

/// SHU-Hardware-Details: Random-Register-Marker, Chip-UIDs, abgeleitete Board-Typen.
enum CfwHardwareForensics {

    /// Bekannte Custom-/SHU-Marker in rRand / rMCURand (ASCII).
    static let knownMarkers: [String] = [
        "cfw.sh",
        "cjssgk", // Screenshot: cjsSgk
        "scooterhacking",
        "shfw",
        "vesc"
    ]

    static func printableAscii(from data: Data) -> String? {
        let chars = data.compactMap { byte -> Character? in
            guard byte >= 0x20, byte <= 0x7E else { return nil }
            return Character(UnicodeScalar(byte))
        }
        let text = String(chars).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func spacedHexUID(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let pairs = data.map { String(format: "%02X", $0) }
        var groups: [String] = []
        var i = 0
        while i < pairs.count {
            if i + 1 < pairs.count {
                groups.append(pairs[i] + pairs[i + 1])
                i += 2
            } else {
                groups.append(pairs[i])
                i += 1
            }
        }
        return groups.joined(separator: " ")
    }

    static func isSuspiciousMarker(_ text: String?) -> Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return false
        }
        let lower = text.lowercased()
        if knownMarkers.contains(where: { lower.contains($0) }) { return true }
        // Generische CFW-/Tool-Domains in kurzen ASCII-Blöcken.
        if lower.contains("cfw") || lower.hasSuffix(".sh") || lower.contains("shu") {
            return true
        }
        return false
    }

    static func collectedMarkers(from reading: IntegrityReading) -> [String] {
        var out: [String] = []
        for candidate in [reading.mcuRandMarker, reading.vcuRandMarker] {
            guard let candidate, !candidate.isEmpty else { continue }
            if !out.contains(candidate) { out.append(candidate) }
        }
        // Rohregister-Backfill (ältere Dumps / nur Hex).
        for reg in reading.rawRegisters where reg.name == "vcu_g3_mcu_rand" || reg.name == "vcu_g3_rand" {
            if let decoded = reg.valueDecoded, !decoded.isEmpty, !out.contains(decoded) {
                out.append(decoded)
            } else if let ascii = asciiFromHex(reg.valueHex), !out.contains(ascii) {
                out.append(ascii)
            }
        }
        return out
    }

    static func suspiciousMarkers(from reading: IntegrityReading) -> [String] {
        collectedMarkers(from: reading).filter { isSuspiciousMarker($0) }
    }

    static func asciiFromHex(_ hex: String) -> String? {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 2, cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let b = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return printableAscii(from: Data(bytes))
    }

    /// Board-Typen wie in SHU (ZIPv3-Referenz) — modellabgeleitet, kein Registerstring.
    static func inferredBoardTypes(for profile: ScooterProfile) -> [(label: String, value: String)] {
        switch profile.family {
        case .ninebotF3:
            return [
                ("VCU", "f3_VCU_AT32"),
                ("MCU", "x3_MCU_AT32"),
                ("BLE", "f3_BLE"),
                ("BMS", "x3_BMS")
            ]
        case .maxG3:
            return [
                ("VCU", "g3_VCU_AT32"),
                ("MCU", "x3_MCU_AT32"),
                ("BLE", "g3_BLE"),
                ("BMS", "x3_BMS")
            ]
        case .zt3Pro:
            return [
                ("VCU", "zt3_VCU_AT32"),
                ("MCU", "x3_MCU_AT32"),
                ("BLE", "zt3_BLE"),
                ("BMS", "x3_BMS")
            ]
        case .gt3:
            return [
                ("VCU", "gt3_VCU_AT32"),
                ("MCU", "x3_MCU_AT32"),
                ("BLE", "gt3_BLE"),
                ("BMS", "x3_BMS")
            ]
        default:
            return []
        }
    }
}

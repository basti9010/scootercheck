import Foundation

/// Read-only Navee BLE frame helpers (pepperonas/navee-st3-pro PROTOCOL.md).
///
/// Deckt nur Lesebefehle (SN / Firmware / Status). Keine Limit-, Lock-, Region-
/// oder DFU-Writes — auch wenn das Quellprotokoll sie beschreibt.
enum NaveeProtocol {
    static let serviceUUID = "0000D0FF-3C17-D293-8E48-14FE2E4DA212"
    static let writeUUID = "0000B002-0000-1000-8000-00805F9B34FB"
    static let notifyUUID = "0000B003-0000-1000-8000-00805F9B34FB"

    /// Nur freigegebene Lesebefehle.
    enum ReadCommand: UInt8 {
        case auth = 0x30
        case vehicleStatus = 0x70
        case firmware = 0x73
        case serialNumber = 0x74
    }

    /// Bekannte Schreib-/Aktionsbefehle — werden bewusst nicht gebaut.
    enum ForbiddenWriteCommand: UInt8 {
        case unbind = 0x50
        case lock = 0x51
        case cruise = 0x52
        case energyRecovery = 0x53
        case lights = 0x54
        case restoreVehicle = 0x59
        case customSpeedLimit = 0x6B
        case setSpeedOrMode = 0x6E
        case setParams = 0x6F
    }

    /// Factory-Default-Key-Index 0 laut PROTOCOL (`A0…AF`). Nur für Auth-Lesepfad.
    static let factoryAuthKey: [UInt8] = [
        0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
        0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF
    ]

    /// READ-Frame: `[55 AA][encFlag][cmd]` + checksum + `[FE FD]`.
    static func buildReadFrame(command: ReadCommand, encrypted: Bool = false) -> Data {
        var body: [UInt8] = [0x55, 0xAA, encrypted ? 1 : 0, command.rawValue]
        let sum = body.reduce(0) { ($0 &+ Int($1)) } & 0xFF
        body.append(UInt8(sum))
        body.append(contentsOf: [0xFE, 0xFD])
        return Data(body)
    }

    static func parseFrame(_ data: Data) -> (command: UInt8, payload: Data)? {
        guard data.count >= 6 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x55, bytes[1] == 0xAA else { return nil }
        guard bytes[bytes.count - 2] == 0xFE, bytes[bytes.count - 1] == 0xFD else { return nil }
        let cmd = bytes[3]
        // [55 AA][enc][cmd][len?][data…][sum][FE FD] — len optional bei kurzen Frames
        if data.count == 6 {
            return (cmd, Data())
        }
        let payloadEnd = bytes.count - 2
        guard payloadEnd > 4 else { return (cmd, Data()) }
        // Ohne feste Längenangabe: alles zwischen cmd und checksum
        let payload = Data(bytes[4..<(payloadEnd - 1)])
        return (cmd, payload)
    }

    static func decodeSerial(_ payload: Data) -> String? {
        guard !payload.isEmpty else { return nil }
        let trimmed = String(bytes: payload, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines))
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Vier × 4-Byte-ASCII: meter / bldc / bms / screen.
    static func decodeFirmwareBlocks(_ payload: Data) -> [String: String] {
        var out: [String: String] = [:]
        let labels = ["meter", "bldc", "bms", "screen"]
        for (i, label) in labels.enumerated() {
            let start = i * 4
            let end = start + 4
            guard payload.count >= end else { break }
            let slice = payload.subdata(in: start..<end)
            if let s = String(bytes: slice, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)),
               !s.isEmpty {
                out[label] = s
            }
        }
        return out
    }

    static func isForbiddenWrite(_ command: UInt8) -> Bool {
        ForbiddenWriteCommand(rawValue: command) != nil
    }
}

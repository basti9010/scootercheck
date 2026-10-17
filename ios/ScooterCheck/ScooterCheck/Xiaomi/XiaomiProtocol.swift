import Foundation
import CoreBluetooth

// MARK: - Xiaomi classic BLE (Nordic UART, unencrypted 55 AA)
//
// Read-only diagnostic framing for Xiaomi M365 / Pro 2 and similar.
// Newer Xiaomi 3/4 may speak encrypted 55 AB — those frames are detected
// and reported without attempting decrypt/unlock.

enum XiaomiUUID {
    /// Nordic UART Service used by Xiaomi classic scooters.
    static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let write = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let notify = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
}

enum Xiaomi {
    static let sync1: UInt8 = 0x55
    static let sync2: UInt8 = 0xAA
    /// Encrypted Xiaomi frames (not supported — diagnosis only on plaintext).
    static let sync2Encrypted: UInt8 = 0xAB
    static let appId: UInt8 = 0x3E

    enum Board: UInt8, CaseIterable {
        case esc = 0x20
        case ble = 0x21
        case bms = 0x22
    }

    enum Cmd: UInt8 {
        case read = 0x01
        case readResp = 0x04
    }

    /// Common ESC / BLE / BMS register indices (Xiaomi classic layout).
    enum Register {
        static let serialNumber: UInt8 = 0x10
        static let firmware: UInt8 = 0x1A
        static let error: UInt8 = 0x1B
        static let batteryPercent: UInt8 = 0x22
        static let remainingRange: UInt8 = 0x25
        static let currentSpeed: UInt8 = 0x26
        static let averageSpeed: UInt8 = 0x27
        static let tripDistance: UInt8 = 0x29
        static let tripMaxSpeed: UInt8 = 0x2A
        static let frameTemp: UInt8 = 0x3E
        static let motorTemp: UInt8 = 0x35
        static let totalMileage: UInt8 = 0xB4
        static let tripTime: UInt8 = 0x3A
        static let voltage: UInt8 = 0x34
        static let cycleCount: UInt8 = 0x17
        static let designCapacity: UInt8 = 0x18
        static let remainCapacity: UInt8 = 0x19
        static let bmsFirmware: UInt8 = 0x17
        static let speedLimit: UInt8 = 0x72
        static let lockStatus: UInt8 = 0x70
    }

    struct ParsedFrame {
        let length: Int
        let source: UInt8
        let destination: UInt8
        let cmd: UInt8
        let index: UInt8
        let data: Data
    }

    // MARK: - Frame builders (plaintext 55 AA only)

    /// Ninebot-compatible plaintext layout with Xiaomi sync + checksum.
    /// `55 AA | len | src(app) | dst | cmd | index | data[len] | cksum16`
    static func frame(
        target: Board,
        cmd: Cmd,
        index: UInt8,
        data: Data = Data()
    ) -> Data {
        var body = Data()
        body.append(UInt8(data.count))
        body.append(appId)
        body.append(target.rawValue)
        body.append(cmd.rawValue)
        body.append(index)
        body.append(data)

        var out = Data([sync1, sync2])
        out.append(body)
        out.append(checksum(of: body))
        return out
    }

    static func read(board: Board, register: UInt8, length: Int) -> Data {
        frame(target: board, cmd: .read, index: register, data: Data([UInt8(length)]))
    }

    static func checksum(of body: Data) -> Data {
        var sum: UInt32 = 0
        for b in body { sum += UInt32(b) }
        let ck = UInt16((~sum) & 0xFFFF)
        return Data([UInt8(ck & 0xFF), UInt8((ck >> 8) & 0xFF)])
    }

    static func parse(_ raw: Data) -> ParsedFrame? {
        guard raw.count >= 9 else { return nil }
        guard raw[0] == sync1, raw[1] == sync2 else { return nil }

        let length = Int(raw[2])
        let total = length + 9 // header(2)+len+src+dst+cmd+idx + data + cksum(2)
        guard raw.count >= total else { return nil }

        let body = raw.subdata(in: 2..<(total - 2))
        let expected = checksum(of: body)
        let actual = raw.subdata(in: (total - 2)..<total)
        guard expected == actual else { return nil }

        let source = raw[3]
        let destination = raw[4]
        let cmd = raw[5]
        let index = raw[6]
        let dataEnd = 7 + length
        let data = raw.subdata(in: 7..<min(dataEnd, total - 2))

        return ParsedFrame(
            length: length,
            source: source,
            destination: destination,
            cmd: cmd,
            index: index,
            data: data
        )
    }

    static func looksEncrypted(_ chunk: Data) -> Bool {
        chunk.count >= 2 && chunk[0] == sync1 && chunk[1] == sync2Encrypted
    }

    static func boardLabel(_ board: Board) -> String {
        switch board {
        case .esc: return "ESC"
        case .ble: return "BLE"
        case .bms: return "BMS"
        }
    }
}

// MARK: - Xiaomi frame assembler

final class XiaomiFrameAssembler {
    private var buffer = Data()
    private(set) var sawEncryptedHint = false

    func append(_ chunk: Data) -> [Data] {
        if Xiaomi.looksEncrypted(chunk) {
            sawEncryptedHint = true
        }
        buffer.append(chunk)
        return extractFrames()
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        sawEncryptedHint = false
    }

    private func extractFrames() -> [Data] {
        var frames: [Data] = []
        while true {
            guard let start = findSync(in: buffer) else {
                if let last = buffer.last, last == Xiaomi.sync1 {
                    buffer = Data([last])
                } else {
                    buffer.removeAll(keepingCapacity: true)
                }
                break
            }

            if start > 0 {
                buffer.removeSubrange(0..<start)
            }

            guard buffer.count >= 3 else { break }

            // Encrypted 55 AB — skip one byte and keep scanning; do not decrypt.
            if buffer.count >= 2, buffer[1] == Xiaomi.sync2Encrypted {
                sawEncryptedHint = true
                buffer.removeFirst()
                continue
            }

            let length = Int(buffer[2])
            let total = length + 9
            guard buffer.count >= total else { break }

            frames.append(Data(buffer.prefix(total)))
            buffer.removeSubrange(0..<total)
        }
        return frames
    }

    private func findSync(in data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        for i in 0..<(data.count - 1) {
            if data[i] == Xiaomi.sync1,
               data[i + 1] == Xiaomi.sync2 || data[i + 1] == Xiaomi.sync2Encrypted {
                return i
            }
        }
        return nil
    }
}

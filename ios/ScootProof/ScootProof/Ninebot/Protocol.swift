import Foundation

// MARK: - Ninebot Encryption2 protocol framing and helpers

enum Nb {
    static let sync1: UInt8 = 0x5A
    static let sync2Gen2: UInt8 = 0xA5
    static let sync2Gen3: UInt8 = 0xB5
    static let btId: UInt8 = 0x3E

    enum Board: UInt8, CaseIterable {
        case dis = 0x01
        case ble = 0x04
        case vcu = 0x09
        case mcu = 0x20
        case bms = 0x22
    }

    enum Register: UInt8 {
        case serialNumber = 0x10
        case error = 0x01
        case alarm = 0x02
        case disVersion = 0x1A
        case tripMaxSpeed = 0x24
        case averageSpeed = 0x27
        case mcuVersion = 0x28
        case gearTopSpeed = 0x31
        case ratedSpeed = 0x48
        case ecuVersion = 0x4C
        case mcuMaxSpeed = 0x09
        case speedSafeLock = 0x53
        case speedLimit = 0x93
        case bleVersion = 0x68
        case odometer = 0xB7
        case tripDistance = 0xB9
        case batteryPercent = 0xB5
        case currentSpeed = 0x26
        case remainingRange = 0x25
        case tripTime = 0xBA
        case power = 0xBD
        case bmsVoltage = 0x1A
        case cycleCount = 0x1B
        case bmsSoc = 0x32
        case remainCapacity = 0x26
        case designCapacity = 0x27
        case motorTemp = 0x35
        case controllerTemp = 0x36
    }

    enum Cmd: UInt8 {
        case read = 0x01
        case readResp = 0x04
        case preComm = 0x5B
        case setPwd = 0x5C
        case auth = 0x5D
    }

    struct ParsedFrame {
        let length: Int
        let boardId: UInt8
        let cmd: UInt8
        let index: UInt8
        let data: Data
    }

    // MARK: - Frame builders

    static func sync2(for gen: ProtocolGen) -> UInt8 {
        gen == .gen2 ? sync2Gen2 : sync2Gen3
    }

    static func frame(
        target: Board,
        cmd: Cmd,
        index: UInt8,
        data: Data = Data(),
        gen: ProtocolGen = .gen2
    ) -> Data {
        var out = Data()
        out.append(sync1)
        out.append(sync2(for: gen))
        out.append(UInt8(data.count))
        out.append(btId)
        out.append(target.rawValue)
        out.append(cmd.rawValue)
        out.append(index)
        out.append(data)
        return out
    }

    static func preComm(gen: ProtocolGen = .gen2) -> Data {
        frame(target: .ble, cmd: .preComm, index: 0x00, gen: gen)
    }

    static func setPwd(_ password: Data, gen: ProtocolGen = .gen2) -> Data {
        frame(target: .ble, cmd: .setPwd, index: 0x00, data: password.prefix(16), gen: gen)
    }

    static func auth(serialNumber: Data, gen: ProtocolGen = .gen2) -> Data {
        frame(target: .ble, cmd: .auth, index: 0x00, data: serialNumber.prefix(14), gen: gen)
    }

    static func read(
        board: Board,
        register: Register,
        length: Int,
        gen: ProtocolGen = .gen2
    ) -> Data {
        frame(target: board, cmd: .read, index: register.rawValue, data: Data([UInt8(length)]), gen: gen)
    }

    static func read(
        board: Board,
        register: UInt8,
        length: Int,
        gen: ProtocolGen = .gen2
    ) -> Data {
        frame(target: board, cmd: .read, index: register, data: Data([UInt8(length)]), gen: gen)
    }

    // MARK: - Parsing

    static func parse(_ decrypted: Data) -> ParsedFrame? {
        guard decrypted.count >= 7 else { return nil }
        guard decrypted[0] == sync1 else { return nil }
        let sync2 = decrypted[1]
        guard sync2 == sync2Gen2 || sync2 == sync2Gen3 else { return nil }
        guard decrypted[4] == btId else { return nil }

        let length = Int(decrypted[2])
        let boardId = decrypted[3]
        let cmd = decrypted[5]
        let index = decrypted[6]
        let end = min(7 + length, decrypted.count)
        let data = decrypted.subdata(in: 7..<end)

        return ParsedFrame(length: length, boardId: boardId, cmd: cmd, index: index, data: data)
    }

    // MARK: - Value decoders

    static func u16(_ data: Data, offset: Int = 0) -> UInt16? {
        guard data.count >= offset + 2 else { return nil }
        return UInt16(data[data.startIndex + offset])
            | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    static func u32(_ data: Data, offset: Int = 0) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        return UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }

    static func i16(_ data: Data, offset: Int = 0) -> Int16? {
        guard let raw = u16(data, offset: offset) else { return nil }
        return Int16(bitPattern: raw)
    }

    /// Speed stored as 0.1 km/h (little-endian u16).
    static func speed(_ data: Data) -> Double? {
        guard let raw = u16(data) else { return nil }
        return Double(raw) / 10.0
    }

    /// Odometer stored as millimetres (little-endian u32) → km.
    static func milliKm(_ data: Data) -> Double? {
        guard let raw = u32(data) else { return nil }
        return Double(raw) / 1000.0
    }

    /// Trip distance stored as 10 m units (little-endian u16) → km.
    static func tripKm(_ data: Data) -> Double? {
        guard let raw = u16(data) else { return nil }
        return Double(raw) / 100.0
    }

    /// Firmware version packed in u16: major.minor.patch nibble layout.
    static func ver(_ data: Data) -> String? {
        guard let raw = u16(data) else { return nil }
        let major = (raw >> 8) & 0xFF
        let minor = (raw >> 4) & 0xF
        let patch = raw & 0xF
        return "\(major).\(minor).\(patch)"
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    /// Voltage in 0.01 V units.
    static func voltage(_ data: Data) -> Double? {
        guard let raw = u16(data) else { return nil }
        return Double(raw) / 100.0
    }

    /// Signed current in 0.01 A units (or raw mA depending on register).
    static func current(_ data: Data) -> Double? {
        guard let raw = i16(data) else { return nil }
        return Double(raw) / 100.0
    }

    static func percent(_ data: Data) -> Double? {
        guard let raw = u16(data) else { return nil }
        return Double(raw)
    }

    /// Temperature in 0.1 °C units.
    static func celsius(_ data: Data) -> Double? {
        guard let raw = i16(data) else { return nil }
        return Double(raw) / 10.0
    }

    static func asciiString(_ data: Data) -> String {
        String(data: data, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: CharacterSet(["\0"])) ?? hex(data)
    }
}

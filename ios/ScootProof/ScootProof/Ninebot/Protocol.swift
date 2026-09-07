import Foundation

// MARK: - Ninebot Encryption2 protocol framing and helpers

enum Nb {
    static let sync1: UInt8 = 0x5A
    /// BLE Encryption2/3 uses 0xA5. 0xB5 is WiFi v2 only — never for BLE.
    static let sync2BLE: UInt8 = 0xA5
    static let sync2Gen2: UInt8 = 0xA5
    static let sync2Gen3: UInt8 = 0xA5
    static let btId: UInt8 = 0x3E

    enum Board: UInt8, CaseIterable {
        case dis = 0x01
        /// Max G3 / neuere Controller oft unter 0x02 (Flasher: MCU).
        case mcuG3 = 0x02
        case ble = 0x04
        /// Max G3 BMS (Flasher ADDR_BMS = 7).
        case bmsG3 = 0x07
        case vcu = 0x09
        /// Max G3 VCU / Versions-Proxy (Flasher: Destination 0x16).
        case vcuG3 = 0x16
        case mcu = 0x20
        /// BLE-Legacy-Adresse (NinebotCrypto/SHU oft 0x21 in Pairing-Antworten).
        case bleLegacy = 0x21
        /// Ältere Ninebot-BMS-Adresse (G30 o. ä.); auf Max G3 oft tot / fl-apl.
        case bms = 0x22
        /// Max G3 TFT-/Display-Board (Aggregat für Mileage o. ä.).
        case tft = 0x23
    }

    /// G3-spezifische Version-Register (Ninebot-Max-G3-Flasher).
    enum G3Register {
        static let bleVersion: UInt8 = 0x01
        static let vcuVersion: UInt8 = 0x17
        static let mcuVersion: UInt8 = 0x19
        static let mcuVersionFallback: UInt8 = 0x18
        static let bmsVersion: UInt8 = 0x19
        // Segway-Config Max G3 (Server-ID 10258) — VCU-Telemetrie (nicht DIS 0xB7!).
        static let batteryPercent: UInt8 = 0x55
        static let currentSpeed: UInt8 = 0x57
        static let errorCode: UInt8 = 0x58
        static let warnCode: UInt8 = 0x59
        static let gearMode: UInt8 = 0x5A
        static let preciseMileage: UInt8 = 0x5E
        static let remainingMileage: UInt8 = 0x5F
        static let totalMileage: UInt8 = 0x62
        static let runtime: UInt8 = 0x64
        static let rideTime: UInt8 = 0x66
        static let singleMileage: UInt8 = 0x68
        static let maxSpeed: UInt8 = 0x46
        static let startSpeed: UInt8 = 0x42
    }

    /// Register addresses are board-scoped; the same byte may mean different
    /// fields on DIS vs BMS, so these are constants rather than a raw UInt8 enum.
    enum Register {
        static let serialNumber: UInt8 = 0x10
        static let error: UInt8 = 0x01
        static let alarm: UInt8 = 0x02
        static let disVersion: UInt8 = 0x1A
        static let tripMaxSpeed: UInt8 = 0x24
        static let averageSpeed: UInt8 = 0x27
        static let mcuVersion: UInt8 = 0x28
        static let gearTopSpeed: UInt8 = 0x31
        static let ratedSpeed: UInt8 = 0x48
        static let ecuVersion: UInt8 = 0x4C
        static let mcuMaxSpeed: UInt8 = 0x09
        static let speedSafeLock: UInt8 = 0x53
        static let speedLimit: UInt8 = 0x93
        static let bleVersion: UInt8 = 0x68
        static let odometer: UInt8 = 0xB7
        static let tripDistance: UInt8 = 0xB9
        static let batteryPercent: UInt8 = 0xB5
        static let currentSpeed: UInt8 = 0x26
        static let remainingRange: UInt8 = 0x25
        static let tripTime: UInt8 = 0xBA
        static let power: UInt8 = 0xBD
        static let bmsVoltage: UInt8 = 0x1A
        static let cycleCount: UInt8 = 0x1B
        static let bmsSoc: UInt8 = 0x32
        static let remainCapacity: UInt8 = 0x26
        static let designCapacity: UInt8 = 0x27
        static let motorTemp: UInt8 = 0x35
        static let controllerTemp: UInt8 = 0x36
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
        // Gen2/Gen3 unterscheiden nur die Crypto-ECB-Eingabe, nicht den BLE-Sync.
        _ = gen
        return sync2BLE
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

    static func preComm(target: Board = .ble, gen: ProtocolGen = .gen2) -> Data {
        frame(target: target, cmd: .preComm, index: 0x00, gen: gen)
    }

    static func setPwd(_ password: Data, target: Board = .ble, gen: ProtocolGen = .gen2) -> Data {
        frame(target: target, cmd: .setPwd, index: 0x00, data: password.prefix(16), gen: gen)
    }

    static func auth(serialNumber: Data, target: Board = .ble, gen: ProtocolGen = .gen2) -> Data {
        frame(target: target, cmd: .auth, index: 0x00, data: serialNumber.prefix(14), gen: gen)
    }

    static func read(
        board: Board,
        register: UInt8,
        length: Int,
        gen: ProtocolGen = .gen2
    ) -> Data {
        // Max-G3-/Enc2-Apps und Flasher senden die Länge als u16 LE (z. B. 04 00).
        let len = max(0, min(length, 0xFFFF))
        let lenBytes = Data([UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF)])
        return frame(target: board, cmd: .read, index: register, data: lenBytes, gen: gen)
    }

    // MARK: - Parsing

    static func parse(_ decrypted: Data) -> ParsedFrame? {
        guard decrypted.count >= 7 else { return nil }
        guard decrypted[0] == sync1 else { return nil }
        let sync2 = decrypted[1]
        guard sync2 == sync2Gen2 || sync2 == sync2Gen3 else { return nil }

        // Antwort: src=Board, dst=0x3E. Manche Paths spiegeln 0x3E an anderer Stelle —
        // akzeptiere, wenn eines der Adressfelder die App-ID trägt.
        let src = decrypted[3]
        let dst = decrypted[4]
        guard src == btId || dst == btId else { return nil }

        let length = Int(decrypted[2])
        // Bei Antwort ist Board die Gegenstelle (src), außer src ist die App selbst.
        let boardId = (dst == btId) ? src : dst
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

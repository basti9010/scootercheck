import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE UUIDs

private enum NbUUID {
    static let service = CBUUID(string: "6E400001-0000-0000-006E-696E65626F74")
    static let write = CBUUID(string: "6E400002-0000-0000-006E-696E65626F74")
    static let notify = CBUUID(string: "6E400004-0000-0000-006E-696E65626F74")
}

// MARK: - Frame assembler

final class FrameAssembler {
    private var buffer = Data()

    func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        return extractFrames()
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    private func extractFrames() -> [Data] {
        var frames: [Data] = []
        while true {
            guard let start = findSync(in: buffer) else {
                if let last = buffer.last, last == Nb.sync1 {
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

            let length = Int(buffer[2])
            let total = length + 13
            guard buffer.count >= total else { break }

            frames.append(buffer.prefix(total))
            buffer.removeSubrange(0..<total)
        }
        return frames
    }

    private func findSync(in data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        for i in 0..<(data.count - 1) {
            if data[i] == Nb.sync1 && (data[i + 1] == Nb.sync2Gen2 || data[i + 1] == Nb.sync2Gen3) {
                return i
            }
        }
        return nil
    }
}

// MARK: - Data helpers

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - Scanned device

struct ScannedDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    static func == (lhs: ScannedDevice, rhs: ScannedDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BleClient

@MainActor
final class BleClient: NSObject, ObservableObject {
    enum Phase: String {
        case idle
        case scanning
        case connecting
        case handshake
        case waitingButton
        case dumping
        case done
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusMessage = "Bereit"
    @Published private(set) var devices: [ScannedDevice] = []
    @Published private(set) var reading = IntegrityReading()
    @Published private(set) var lastError: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private var crypto: NbCrypto?
    private var protocolGen: ProtocolGen = .gen3
    private var authParam = Data()
    private var serialNumber = Data()
    private var sessionPassword = Data()
    private var btName = ""

    private let assembler = FrameAssembler()
    private var pendingContinuation: CheckedContinuation<Data, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    private static let passwordKeyPrefix = "ninebot_password_"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else {
            lastError = "Bluetooth ist aus"
            phase = .failed
            return
        }
        devices.removeAll()
        phase = .scanning
        statusMessage = "Suche Ninebot-Geräte…"
        central.scanForPeripherals(
            withServices: [NbUUID.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        central.stopScan()
        if phase == .scanning {
            phase = .idle
            statusMessage = "Scan beendet"
        }
    }

    func connect(to device: ScannedDevice) async throws {
        stopScan()
        phase = .connecting
        statusMessage = "Verbinde mit \(device.name)…"
        peripheral = device.peripheral
        btName = device.name
        peripheral?.delegate = self
        assembler.reset()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuation = continuation
            central.connect(device.peripheral, options: nil)
        }
    }

    func handshakeAndDump() async {
        guard peripheral != nil else {
            fail("Kein Gerät verbunden")
            return
        }

        phase = .handshake
        statusMessage = "Handshake…"

        do {
            for gen in [ProtocolGen.gen3, ProtocolGen.gen2] {
                do {
                    try await runHandshake(gen: gen)
                    protocolGen = gen
                    reading.protocolGen = gen
                    break
                } catch {
                    if gen == .gen2 {
                        throw error
                    }
                    statusMessage = "Gen3 fehlgeschlagen, versuche Gen2…"
                }
            }

            await dump()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func disconnect() {
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetSession()
        phase = .idle
        statusMessage = "Getrennt"
    }

    // MARK: - Handshake

    private func runHandshake(gen: ProtocolGen) async throws {
        crypto = NbCrypto(gen: gen)
        guard let crypto else { throw BleError.encryptionFailed }

        // Phase 1: PRE_COMM
        crypto.resetSN()
        let initialKey2: Data? = gen == .gen2 ? Data(NbCryptoConstants.fwData) : nil
        crypto.setKey(Data(btName.utf8), initialKey2)

        let prePlain = Nb.preComm(gen: gen)
        let preResp = try await sendReceive(plain: prePlain, crypto: crypto, timeout: 5)

        if preResp == prePlain {
            throw BleError.handshakeFailed("Gerät hat PRE_COMM zurückgespiegelt")
        }

        guard let parsed = Nb.parse(preResp), parsed.cmd == Nb.Cmd.preComm.rawValue else {
            throw BleError.handshakeFailed("Ungültige PRE_COMM-Antwort")
        }
        guard parsed.data.count >= 30 else {
            throw BleError.handshakeFailed("PRE_COMM-Daten zu kurz")
        }

        authParam = parsed.data.prefix(16)
        serialNumber = parsed.data.subdata(in: 16..<30)
        let hasStoredPwd = parsed.index != 0

        crypto.setAuthParam(authParam)
        crypto.startSN()

        // Phase 2: SET_PWD (if needed)
        var password = loadPassword()

        if password == nil && hasStoredPwd {
            statusMessage = "Gespeichertes Passwort fehlt — neues Pairing nötig"
        }

        if password == nil {
            crypto.setKey(Data(btName.utf8), authParam)
            password = generatePassword(auth: authParam)

            let setPlain = Nb.setPwd(password!, gen: gen)
            let setResp = try await sendReceive(plain: setPlain, crypto: crypto, timeout: 10)
            guard let setParsed = Nb.parse(setResp), setParsed.cmd == Nb.Cmd.setPwd.rawValue else {
                throw BleError.handshakeFailed("Ungültige SET_PWD-Antwort")
            }

            if setParsed.index == 0 {
                phase = .waitingButton
                statusMessage = "Bitte Power-Taste am Scooter drücken…"
                let retryResp = try await waitForButtonPress(crypto: crypto, gen: gen, timeout: 60)
                guard let retryParsed = Nb.parse(retryResp),
                      retryParsed.cmd == Nb.Cmd.setPwd.rawValue,
                      retryParsed.index == 1 else {
                    throw BleError.handshakeFailed("SET_PWD abgelehnt (Taste nicht gedrückt?)")
                }
            } else if setParsed.index != 1 {
                throw BleError.handshakeFailed("SET_PWD abgelehnt")
            }
        }

        sessionPassword = password!
        savePassword(sessionPassword)

        // Phase 3: AUTH
        crypto.setKey(sessionPassword, authParam)
        let authPlain = Nb.auth(serialNumber: serialNumber, gen: gen)
        let authResp = try await sendReceive(plain: authPlain, crypto: crypto, timeout: 5)

        guard let authParsed = Nb.parse(authResp), authParsed.cmd == Nb.Cmd.auth.rawValue else {
            throw BleError.handshakeFailed("Ungültige AUTH-Antwort")
        }

        if authParsed.index != 1 {
            clearPassword()
            throw BleError.handshakeFailed("AUTH abgelehnt — Passwort gelöscht")
        }

        statusMessage = "Authentifiziert (\(gen.rawValue))"
    }

    private func waitForButtonPress(crypto: NbCrypto, gen: ProtocolGen, timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let frame = try await receiveEncrypted(crypto: crypto, timeout: 2)
                return frame
            } catch {
                continue
            }
        }
        throw BleError.handshakeFailed("Timeout beim Warten auf Power-Taste")
    }

    // MARK: - Diagnostic dump

    func dump() async {
        guard let crypto else {
            fail("Nicht authentifiziert")
            return
        }

        phase = .dumping
        statusMessage = "Lese Register…"
        reading = IntegrityReading()
        reading.protocolGen = protocolGen

        var evidence = Data()
        var liveBoards = Set<String>()

        // Probe boards
        for board in Nb.Board.allCases {
            let probe = Nb.read(board: board, register: .error, length: 2, gen: protocolGen)
            do {
                let resp = try await sendReceive(plain: probe, crypto: crypto, timeout: 2)
                if let parsed = Nb.parse(resp), parsed.cmd == Nb.Cmd.readResp.rawValue {
                    liveBoards.insert(boardLabel(board))
                }
            } catch {
                continue
            }
        }
        reading.liveBoards = liveBoards.sorted()

        // Read all diagnostic fields
        let total = DiagnosticMap.fields.count
        for (index, spec) in DiagnosticMap.fields.enumerated() {
            statusMessage = "Lese \(spec.id) (\(index + 1)/\(total))…"

            let request = Nb.read(board: spec.board, register: spec.register, length: spec.readLen, gen: protocolGen)
            do {
                let resp = try await sendReceive(plain: request, crypto: crypto, timeout: 3)
                guard let parsed = Nb.parse(resp),
                      parsed.cmd == Nb.Cmd.readResp.rawValue,
                      parsed.index == spec.register else {
                    continue
                }

                evidence.append(spec.key.data(using: .utf8) ?? Data())
                evidence.append(parsed.data)

                DiagnosticMap.apply(spec: spec, data: parsed.data, into: &reading)
                _ = DiagnosticMap.decode(spec: spec, data: parsed.data)
            } catch {
                continue
            }

            // Small gap to avoid flooding the BLE module
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        reading.evidenceSha256 = NbCrypto.sha256(evidence).map { String(format: "%02x", $0) }.joined()
        phase = .done
        statusMessage = "Diagnose abgeschlossen"
    }

    // MARK: - Transport

    private func sendReceive(plain: Data, crypto: NbCrypto, timeout: TimeInterval) async throws -> Data {
        let encrypted = try crypto.encrypt(plain)
        try await write(encrypted)
        return try await receiveEncrypted(crypto: crypto, timeout: timeout)
    }

    private func write(_ data: Data) async throws {
        guard let peripheral, let writeChar else { throw BleError.notConnected }

        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let chunkSize = max(mtu, 20)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            peripheral.writeValue(chunk, for: writeChar, type: .withoutResponse)
            offset = end
            if offset < data.count {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func receiveEncrypted(crypto: NbCrypto, timeout: TimeInterval) async throws -> Data {
        let encrypted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.pendingContinuation {
                    self.pendingContinuation = nil
                    pending.resume(throwing: BleError.timeout)
                }
            }
        }

        return try crypto.decrypt(encrypted)
    }

    private func deliverFrame(_ encrypted: Data) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        continuation.resume(returning: encrypted)
    }

    // MARK: - Password persistence

    private var passwordDefaultsKey: String {
        guard let id = peripheral?.identifier.uuidString else { return Self.passwordKeyPrefix + "unknown" }
        return Self.passwordKeyPrefix + id
    }

    private func loadPassword() -> Data? {
        guard let stored = UserDefaults.standard.data(forKey: passwordDefaultsKey), stored.count == 16 else {
            return nil
        }
        return stored
    }

    private func savePassword(_ password: Data) {
        UserDefaults.standard.set(password, forKey: passwordDefaultsKey)
    }

    private func clearPassword() {
        UserDefaults.standard.removeObject(forKey: passwordDefaultsKey)
    }

    // MARK: - Helpers

    private func boardLabel(_ board: Nb.Board) -> String {
        switch board {
        case .dis: return "DIS"
        case .ble: return "BLE"
        case .vcu: return "VCU"
        case .mcu: return "MCU"
        case .bms: return "BMS"
        }
    }

    private func fail(_ message: String) {
        lastError = message
        phase = .failed
        statusMessage = message
    }

    private func resetSession() {
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        crypto = nil
        assembler.reset()
        pendingContinuation = nil
        connectContinuation = nil
    }

    private static func isNinebotDevice(name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let upper = name.uppercased()
        if upper.contains("NINEBOT") || upper.contains("SEGWAY") || upper.contains("ZT3") {
            return true
        }
        if upper.hasPrefix("N2") {
            return true
        }
        return false
    }
}

// MARK: - CBCentralManagerDelegate

extension BleClient: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state != .poweredOn, phase == .scanning {
                fail("Bluetooth nicht verfügbar")
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? ""
        guard Self.isNinebotDevice(name: name) else { return }

        Task { @MainActor in
            let device = ScannedDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
            if !devices.contains(where: { $0.id == device.id }) {
                devices.append(device)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices([NbUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectContinuation?.resume(throwing: error ?? BleError.notConnected)
            connectContinuation = nil
            fail(error?.localizedDescription ?? "Verbindung fehlgeschlagen")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            resetSession()
            if let error {
                fail(error.localizedDescription)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BleClient: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                connectContinuation?.resume(throwing: error)
                connectContinuation = nil
                fail(error.localizedDescription)
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == NbUUID.service }) else {
                connectContinuation?.resume(throwing: BleError.notConnected)
                connectContinuation = nil
                fail("Ninebot-Service nicht gefunden")
                return
            }
            peripheral.discoverCharacteristics([NbUUID.write, NbUUID.notify], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                connectContinuation?.resume(throwing: error)
                connectContinuation = nil
                fail(error.localizedDescription)
                return
            }

            for char in service.characteristics ?? [] {
                if char.uuid == NbUUID.write { writeChar = char }
                if char.uuid == NbUUID.notify { notifyChar = char }
            }

            guard let notifyChar else {
                connectContinuation?.resume(throwing: BleError.notConnected)
                connectContinuation = nil
                fail("Notify-Characteristic nicht gefunden")
                return
            }

            peripheral.setNotifyValue(true, for: notifyChar)
            statusMessage = "Verbunden"
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == NbUUID.notify, let data = characteristic.value else { return }
        Task { @MainActor in
            let frames = assembler.append(data)
            for frame in frames {
                deliverFrame(frame)
            }
        }
    }
}

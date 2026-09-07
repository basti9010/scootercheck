import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE UUIDs

private enum NbUUID {
    static let service = CBUUID(string: "6E400001-0000-0000-006E-696E65626F74")
    static let write = CBUUID(string: "6E400002-0000-0000-006E-696E65626F74")
    static let notify = CBUUID(string: "6E400004-0000-0000-006E-696E65626F74")
}

/// Erkanntes BLE-Diagnose-Protokoll (Stack) am Scooter.
enum BleStack: String, Codable, CaseIterable, Sendable {
    case unknown
    case ninebotEnc2
    case xiaomiPlain
    case xiaomiEncrypted

    var label: String {
        switch self {
        case .unknown: return "Unbekannt"
        case .ninebotEnc2: return "Ninebot Enc2"
        case .xiaomiPlain: return "Xiaomi Klartext (55 AA)"
        case .xiaomiEncrypted: return "Xiaomi verschlüsselt (55 AB)"
        }
    }

    var shortLabel: String {
        switch self {
        case .unknown: return "—"
        case .ninebotEnc2: return "Enc2"
        case .xiaomiPlain: return "Xiaomi AA"
        case .xiaomiEncrypted: return "Xiaomi AB"
        }
    }

    var isReadable: Bool {
        switch self {
        case .ninebotEnc2, .xiaomiPlain: return true
        case .unknown, .xiaomiEncrypted: return false
        }
    }
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
    /// Anzeigename (kann „Ohne Namen (…)“ sein).
    let name: String
    /// Roher BLE-Advertisement-Name für Enc2-Key-Material (leer wenn unbekannt).
    let cryptoName: String
    let rssi: Int
    let peripheral: CBPeripheral
    /// Heuristik anhand BLE-Name (nur Anzeige/Filter, kein Hard-Block beim Scan).
    let looksLikeScooter: Bool

    static func == (lhs: ScannedDevice, rhs: ScannedDevice) -> Bool {
        lhs.id == rhs.id
            && lhs.rssi == rhs.rssi
            && lhs.name == rhs.name
            && lhs.cryptoName == rhs.cryptoName
            && lhs.looksLikeScooter == rhs.looksLikeScooter
    }

    /// 0…4 Balken für die UI
    var signalBars: Int {
        switch rssi {
        case -50...0: return 4
        case -65 ..< -50: return 3
        case -80 ..< -65: return 2
        default: return 1
        }
    }

    var signalLabel: String {
        switch signalBars {
        case 4: return "Sehr nah"
        case 3: return "Nah"
        case 2: return "Mittel"
        default: return "Weit"
        }
    }
}

// MARK: - BleClient

@MainActor
final class BleClient: NSObject, ObservableObject {
    enum Phase: String {
        case idle
        case scanning
        case connecting
        case detecting
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
    @Published private(set) var detectedStack: BleStack = .unknown
    /// Wenn true: Liste nur mit Namen, die nach Scooter aussehen. Sonst alle BLE-Geräte.
    @Published var showOnlyLikelyScooters = false

    private static let maxTrackedDevices = 50

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private var ninebotWrite: CBCharacteristic?
    private var ninebotNotify: CBCharacteristic?
    private var xiaomiWrite: CBCharacteristic?
    private var xiaomiNotify: CBCharacteristic?
    private var pendingCharDiscoveries = 0
    private var hasNinebotPipe: Bool { ninebotWrite != nil && ninebotNotify != nil }
    private var hasXiaomiPipe: Bool { xiaomiWrite != nil && xiaomiNotify != nil }

    private var crypto: NbCrypto?
    private var protocolGen: ProtocolGen = .gen3
    private var authParam = Data()
    private var serialNumber = Data()
    private var sessionPassword = Data()
    private var btName = ""
    /// Name für Enc2-Key (Advertisement Local Name), nie der UI-Platzhalter.
    private var cryptoName = ""
    private var activeStack: BleStack = .unknown
    private var enc2PipeIsNordic = false

    private let assembler = FrameAssembler()
    private let xiaomiAssembler = XiaomiFrameAssembler()
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
        statusMessage = showOnlyLikelyScooters
            ? "Suche vermutete Scooter…"
            : "Suche alle BLE-Geräte in der Nähe…"
        // AllowDuplicates: RSSI live aktualisieren, um bei mehreren Geräten das nähere zu erkennen.
        // withServices: nil — wie SHU alle BLE-Advertiser erfassen (nicht nur bekannte Service-UUIDs).
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    /// Gefilterte Ansicht für die UI (alle Geräte oder nur Scooter-Heuristik).
    var visibleDevices: [ScannedDevice] {
        if showOnlyLikelyScooters {
            return devices.filter(\.looksLikeScooter)
        }
        return devices
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
        lastError = nil
        detectedStack = .unknown
        activeStack = .unknown
        enc2PipeIsNordic = false
        peripheral = device.peripheral
        btName = device.name
        // Enc2 leitet den Session-Key aus dem echten BLE-Namen ab.
        cryptoName = device.cryptoName.isEmpty ? device.name : device.cryptoName
        if cryptoName.hasPrefix("Ohne Namen") {
            // Fallback: Peripheral-Name aus CoreBluetooth, sonst leerer Key (wird scheitern).
            cryptoName = device.peripheral.name ?? ""
        }
        peripheral?.delegate = self
        assembler.reset()
        xiaomiAssembler.reset()
        ninebotWrite = nil
        ninebotNotify = nil
        xiaomiWrite = nil
        xiaomiNotify = nil
        writeChar = nil
        notifyChar = nil
        pendingCharDiscoveries = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connectContinuation = continuation
            central.connect(device.peripheral, options: nil)
        }

        // iOS: CCCD/Notify neu setzen, sonst bleiben Antworten oft aus.
        await prepareNotifyChannel()
    }

    private func prepareNotifyChannel() async {
        guard let peripheral else { return }
        let notifies = [ninebotNotify, xiaomiNotify].compactMap { $0 }
        for char in notifies {
            peripheral.setNotifyValue(false, for: char)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        for char in notifies {
            peripheral.setNotifyValue(true, for: char)
        }
        // Stale Notifications ablaufen lassen
        try? await Task.sleep(nanoseconds: 200_000_000)
        assembler.reset()
        xiaomiAssembler.reset()
        pendingContinuation = nil
    }

    /// Erkennt den BLE-Stack automatisch und startet die passende Read-only-Auslese.
    /// `profile` steuert nur die Reihenfolge der Versuche (Hint), nicht das Ergebnis.
    func handshakeAndDump(profile: ScooterProfile) async {
        guard peripheral != nil else {
            fail("Kein Gerät verbunden")
            return
        }

        phase = .detecting
        statusMessage = "Erkenne BLE-Protokoll…"
        detectedStack = .unknown

        let order = detectionOrder(profileHint: profile, name: cryptoName.isEmpty ? btName : cryptoName)
        var sawEncryptedXiaomi = false
        var lastFailure: String?

        for candidate in order {
            switch candidate {
            case .xiaomiPlain:
                guard hasXiaomiPipe else { continue }
                phase = .detecting
                statusMessage = "Prüfe Xiaomi-Protokoll (55 AA)…"
                activate(.xiaomiPlain)
                xiaomiAssembler.reset()
                if await probeXiaomiPlain() {
                    detectedStack = .xiaomiPlain
                    statusMessage = "Stack: \(BleStack.xiaomiPlain.label)"
                    await dumpXiaomi()
                    return
                }
                if xiaomiAssembler.sawEncryptedHint {
                    sawEncryptedXiaomi = true
                    detectedStack = .xiaomiEncrypted
                }

            case .ninebotEnc2:
                // 1) Ninebot-Custom-UART, 2) Enc2 über Nordic UART (Kompatibilität)
                let pipes: [(String, Bool)] = [
                    hasNinebotPipe ? ("Ninebot-UART", false) : nil,
                    hasXiaomiPipe ? ("Nordic-UART/Enc2", true) : nil
                ].compactMap { $0 }

                for (label, useNordic) in pipes {
                    phase = .detecting
                    statusMessage = "Prüfe Ninebot Enc2 (\(label))…"
                    activateEnc2(useNordicUART: useNordic)
                    assembler.reset()
                    do {
                        try await runNinebotHandshakeAndDump()
                        return
                    } catch {
                        lastFailure = "\(label): \(error.localizedDescription)"
                        crypto = nil
                        continue
                    }
                }

            case .xiaomiEncrypted, .unknown:
                continue
            }
        }

        if sawEncryptedXiaomi {
            fail("Stack erkannt: \(BleStack.xiaomiEncrypted.label) — Klartext-Auslese nicht möglich")
            return
        }

        let pipes: [String] = [
            hasNinebotPipe ? "Ninebot-UART" : nil,
            hasXiaomiPipe ? "Xiaomi/Nordic-NUS" : nil
        ].compactMap { $0 }
        let pipeInfo = pipes.isEmpty ? "kein UART-Service" : pipes.joined(separator: " + ")
        let nameHint = cryptoName.isEmpty ? "ohne BLE-Namen" : "BLE-Name „\(cryptoName)“"
        fail(
            "Kein unterstütztes Protokoll erkannt (\(pipeInfo), \(nameHint))"
                + (lastFailure.map { " — \($0)" } ?? "")
                + ". Scooter eingeschaltet lassen; bei Pairing Power-Taste drücken."
        )
    }

    /// Backwards-compatible entry for Ninebot Enc2 callers.
    func handshakeAndDump() async {
        await handshakeAndDump(profile: .zt3ProD)
    }

    // MARK: - Stack detection helpers

    private func detectionOrder(profileHint: ScooterProfile, name: String) -> [BleStack] {
        let nameSuggestsXiaomi = Self.nameSuggestsXiaomi(name)
        let preferXiaomi = !profileHint.usesNinebotEnc2 || nameSuggestsXiaomi

        var order: [BleStack] = []
        if preferXiaomi {
            if hasXiaomiPipe { order.append(.xiaomiPlain) }
            if hasNinebotPipe { order.append(.ninebotEnc2) }
        } else {
            if hasNinebotPipe { order.append(.ninebotEnc2) }
            if hasXiaomiPipe { order.append(.xiaomiPlain) }
        }
        // Falls Hint und verfügbare Pipes nicht zusammenpassen: alles Verfügbare versuchen.
        if order.isEmpty {
            if hasNinebotPipe { order.append(.ninebotEnc2) }
            if hasXiaomiPipe { order.append(.xiaomiPlain) }
        }
        return order
    }

    private func activate(_ stack: BleStack) {
        activeStack = stack
        enc2PipeIsNordic = false
        switch stack {
        case .xiaomiPlain, .xiaomiEncrypted:
            writeChar = xiaomiWrite
            notifyChar = xiaomiNotify
        case .ninebotEnc2:
            writeChar = ninebotWrite
            notifyChar = ninebotNotify
        case .unknown:
            writeChar = nil
            notifyChar = nil
        }
    }

    /// Enc2 kann auf Ninebot-Custom-UART oder Nordic-UART (Kompatibilität) laufen.
    private func activateEnc2(useNordicUART: Bool) {
        activeStack = .ninebotEnc2
        enc2PipeIsNordic = useNordicUART
        if useNordicUART {
            writeChar = xiaomiWrite
            notifyChar = xiaomiNotify
        } else {
            writeChar = ninebotWrite
            notifyChar = ninebotNotify
        }
    }

    private func probeXiaomiPlain() async -> Bool {
        let probe = Xiaomi.read(board: .esc, register: Xiaomi.Register.error, length: 2)
        do {
            let resp = try await sendReceiveXiaomi(probe, timeout: 2.5)
            if let parsed = Xiaomi.parse(resp), parsed.cmd == Xiaomi.Cmd.readResp.rawValue {
                return true
            }
        } catch {
            // Timeout / no frame — may still have seen 55 AB in assembler
        }
        // Zweiter Versuch über BLE-Board
        let probeBle = Xiaomi.read(board: .ble, register: Xiaomi.Register.serialNumber, length: 14)
        do {
            let resp = try await sendReceiveXiaomi(probeBle, timeout: 2)
            if let parsed = Xiaomi.parse(resp), parsed.cmd == Xiaomi.Cmd.readResp.rawValue {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    private func runNinebotHandshakeAndDump() async throws {
        phase = .handshake
        statusMessage = "Ninebot Enc2: Handshake…"

        var succeeded = false
        var lastError: Error?
        for gen in [ProtocolGen.gen3, ProtocolGen.gen2] {
            do {
                try await runHandshake(gen: gen)
                protocolGen = gen
                detectedStack = .ninebotEnc2
                activeStack = .ninebotEnc2
                succeeded = true
                break
            } catch {
                lastError = error
                crypto = nil
                if gen == .gen2 { break }
                statusMessage = "Gen3 fehlgeschlagen, versuche Gen2…"
                phase = .handshake
            }
        }

        guard succeeded else {
            throw lastError ?? BleError.handshakeFailed("Enc2 nicht erkannt")
        }

        await dump()
        if phase == .failed {
            throw BleError.handshakeFailed(statusMessage)
        }
    }

    nonisolated private static func nameSuggestsXiaomi(_ name: String) -> Bool {
        let upper = name.uppercased()
        let tokens = ["XIAOMI", "M365", "MI ELECTRIC", "MI SCOOTER", "SCOOTER 3", "SCOOTER 4", "PRO 2", "PRO2"]
        if tokens.contains(where: { upper.contains($0) }) { return true }
        if upper.hasPrefix("MI") && !upper.contains("NINEBOT") { return true }
        return false
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

        // Phase 1: PRE_COMM — key2 immer null/zeros; fw_data wirkt nur als Gen2-ECB-Input.
        crypto.resetSN()
        let nameKey = Data((cryptoName.isEmpty ? btName : cryptoName).utf8)
        crypto.setKey(nameKey, nil)

        let prePlain = Nb.preComm(gen: gen)
        let preResp = try await sendReceive(plain: prePlain, crypto: crypto, timeout: 8)

        if preResp == prePlain {
            throw BleError.handshakeFailed("Gerät hat PRE_COMM zurückgespiegelt (iOS-BLE-Echo)")
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
            crypto.setKey(nameKey, authParam)
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
        reading.protocolGen = protocolGen == .gen2 ? 2 : 3
        reading.bleStack = BleStack.ninebotEnc2.rawValue
        detectedStack = .ninebotEnc2

        var evidence = Data()
        var liveBoards = Set<String>()

        // Probe boards
        for board in Nb.Board.allCases {
            let probe = Nb.read(board: board, register: Nb.Register.error, length: 2, gen: protocolGen)
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

                let decoded = DiagnosticMap.decode(spec: spec, data: parsed.data)
                DiagnosticMap.apply(spec: spec, data: parsed.data, into: &reading)
                reading.rawRegisters.append(
                    RawRegister(
                        address: String(format: "%02X", spec.board.rawValue),
                        index: Int(spec.register),
                        name: spec.id,
                        valueHex: parsed.data.map { String(format: "%02x", $0) }.joined(),
                        valueDecoded: decoded
                    )
                )
            } catch {
                continue
            }

            // Small gap to avoid flooding the BLE module
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        reading.evidenceSha256 = NbCrypto.sha256(evidence).map { String(format: "%02x", $0) }.joined()
        phase = .done
        statusMessage = "Diagnose abgeschlossen (\(BleStack.ninebotEnc2.shortLabel))"
    }

    private func dumpXiaomi() async {
        phase = .dumping
        statusMessage = "Xiaomi-Protokoll: lese Register…"
        reading = IntegrityReading()
        reading.protocolGen = 0 // plaintext Xiaomi (kein Enc2)
        reading.bleStack = BleStack.xiaomiPlain.rawValue
        detectedStack = .xiaomiPlain
        activate(.xiaomiPlain)

        var evidence = Data()
        var liveBoards = Set<String>()
        var gotAny = false

        for board in Xiaomi.Board.allCases {
            let probe = Xiaomi.read(board: board, register: Xiaomi.Register.error, length: 2)
            do {
                let resp = try await sendReceiveXiaomi(probe, timeout: 2)
                if let parsed = Xiaomi.parse(resp), parsed.cmd == Xiaomi.Cmd.readResp.rawValue {
                    liveBoards.insert(Xiaomi.boardLabel(board))
                    gotAny = true
                }
            } catch {
                continue
            }
        }
        reading.liveBoards = liveBoards.sorted()

        let total = XiaomiDiagnosticMap.fields.count
        for (index, spec) in XiaomiDiagnosticMap.fields.enumerated() {
            statusMessage = "Xiaomi: \(spec.id) (\(index + 1)/\(total))…"
            let request = Xiaomi.read(board: spec.board, register: spec.register, length: spec.readLen)
            do {
                let resp = try await sendReceiveXiaomi(request, timeout: 3)
                guard let parsed = Xiaomi.parse(resp),
                      parsed.cmd == Xiaomi.Cmd.readResp.rawValue,
                      parsed.index == spec.register else {
                    continue
                }
                gotAny = true
                evidence.append(spec.key.data(using: .utf8) ?? Data())
                evidence.append(parsed.data)
                XiaomiDiagnosticMap.apply(spec: spec, data: parsed.data, into: &reading)
            } catch {
                continue
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if xiaomiAssembler.sawEncryptedHint && !gotAny {
            fail("Gerät nutzt verschlüsseltes Xiaomi-Protokoll (55 AB) — nur Klartext-Auslese unterstützt")
            return
        }

        if !gotAny {
            fail("Keine Xiaomi-Registerantwort — ggf. anderes BLE-Protokoll oder Scooter aus")
            return
        }

        reading.evidenceSha256 = NbCrypto.sha256(evidence).map { String(format: "%02x", $0) }.joined()
        phase = .done
        statusMessage = "Xiaomi-Diagnose abgeschlossen (\(BleStack.xiaomiPlain.shortLabel))"
    }

    // MARK: - Transport

    private func sendReceive(plain: Data, crypto: NbCrypto, timeout: TimeInterval) async throws -> Data {
        let encrypted = try crypto.encrypt(plain)
        try await write(encrypted)
        return try await receiveEncrypted(crypto: crypto, timeout: timeout)
    }

    private func sendReceiveXiaomi(_ frame: Data, timeout: TimeInterval) async throws -> Data {
        try await write(frame)
        return try await receiveRaw(timeout: timeout)
    }

    private func receiveRaw(timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let pending = self.pendingContinuation {
                    self.pendingContinuation = nil
                    pending.resume(throwing: BleError.timeout)
                }
            }
        }
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
        ninebotWrite = nil
        ninebotNotify = nil
        xiaomiWrite = nil
        xiaomiNotify = nil
        pendingCharDiscoveries = 0
        crypto = nil
        activeStack = .unknown
        detectedStack = .unknown
        enc2PipeIsNordic = false
        cryptoName = ""
        assembler.reset()
        xiaomiAssembler.reset()
        pendingContinuation = nil
        connectContinuation = nil
    }

    /// Öffentliche Heuristik für UI-Badge / optionalen Filter — blockiert den Scan nicht.
    nonisolated static func isLikelyScooterName(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let upper = name.uppercased()
        let tokens = [
            "NINEBOT", "SEGWAY", "ZT3", "G30", "G3", "MAX3", "MAX",
            "XIAOMI", "M365", "MI ELECTRIC", "MI SCOOTER",
            "SCOOTER 3", "SCOOTER 4", "PRO 2", "PRO2", "SCOOTER"
        ]
        if tokens.contains(where: { upper.contains($0) }) { return true }
        if upper.hasPrefix("NB") || upper.hasPrefix("N2") || upper.hasPrefix("N4") { return true }
        if upper.hasPrefix("S1D") || upper.hasPrefix("MI") { return true }
        // F-/D-Serie Kurzformen in BT-Namen
        if upper.range(of: #"\bF[234]?0?\b"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"\bD(18|28|38)\b"#, options: .regularExpression) != nil { return true }

        // Kompakte BLE-IDs neuer Max/G3-Modelle, z. B. „1CGBF25…“
        // (nur Buchstaben/Ziffern zählen — Bindestriche/Spaces ignorieren)
        let compact = String(upper.filter { $0.isLetter || $0.isNumber })
        if compact.count >= 6 {
            if compact.first?.isNumber == true { return true }
            if compact.range(of: #"^[A-Z0-9]{6,20}$"#, options: .regularExpression) != nil {
                // Keine typischen Handy-/TV-Prefixe
                let phoneTV = ["IPHONE", "IPAD", "WATCH", "GALAXY", "SAMSUNG", "PIXEL", "HUAWEI"]
                if !phoneTV.contains(where: { compact.contains($0) }) { return true }
            }
        }
        return false
    }

    nonisolated static func advertisementLooksLikeScooter(_ advertisementData: [String: Any]) -> Bool {
        let keys = [
            CBAdvertisementDataServiceUUIDsKey,
            CBAdvertisementDataOverflowServiceUUIDsKey
        ]
        var uuids: [CBUUID] = []
        for key in keys {
            if let list = advertisementData[key] as? [CBUUID] {
                uuids.append(contentsOf: list)
            }
        }
        let scooterServices: Set<CBUUID> = [NbUUID.service, XiaomiUUID.service]
        return uuids.contains { scooterServices.contains($0) }
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
        let rawName = (advName ?? peripheral.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shortId = String(peripheral.identifier.uuidString.prefix(8))
        let name = rawName.isEmpty ? "Ohne Namen (\(shortId))" : rawName
        let rssiValue = RSSI.intValue
        // Extrem schwache/ungültige Readings ignorieren (RSSI 127 = „nicht verfügbar“).
        guard rssiValue < 20 else { return }

        Task { @MainActor in
            let byName = Self.isLikelyScooterName(rawName.isEmpty ? nil : rawName)
            let byService = Self.advertisementLooksLikeScooter(advertisementData)
            let device = ScannedDevice(
                id: peripheral.identifier,
                name: name,
                cryptoName: rawName,
                rssi: rssiValue,
                peripheral: peripheral,
                looksLikeScooter: byName || byService
            )
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                // Badge beibehalten, sobald einmal als Scooter erkannt.
                let merged = ScannedDevice(
                    id: device.id,
                    name: device.name,
                    cryptoName: device.cryptoName.isEmpty ? devices[index].cryptoName : device.cryptoName,
                    rssi: device.rssi,
                    peripheral: device.peripheral,
                    looksLikeScooter: device.looksLikeScooter || devices[index].looksLikeScooter
                )
                devices[index] = merged
            } else {
                devices.append(device)
            }
            // Stärkstes Signal zuerst — hilft bei mehreren Geräten in Reichweite.
            devices.sort { $0.rssi > $1.rssi }
            if devices.count > Self.maxTrackedDevices {
                devices = Array(devices.prefix(Self.maxTrackedDevices))
            }
            if phase == .scanning {
                let visible = showOnlyLikelyScooters
                    ? devices.filter(\.looksLikeScooter).count
                    : devices.count
                statusMessage = "\(visible) Gerät\(visible == 1 ? "" : "e") · Signal live"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            statusMessage = "Suche Diagnose-Services…"
            peripheral.discoverServices([NbUUID.service, XiaomiUUID.service])
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

            let services = peripheral.services ?? []
            let ninebot = services.first(where: { $0.uuid == NbUUID.service })
            let xiaomi = services.first(where: { $0.uuid == XiaomiUUID.service })

            guard ninebot != nil || xiaomi != nil else {
                connectContinuation?.resume(throwing: BleError.notConnected)
                connectContinuation = nil
                fail("Weder Ninebot- noch Xiaomi-UART-Service gefunden")
                return
            }

            pendingCharDiscoveries = 0
            if let ninebot {
                pendingCharDiscoveries += 1
                peripheral.discoverCharacteristics([NbUUID.write, NbUUID.notify], for: ninebot)
            }
            if let xiaomi {
                pendingCharDiscoveries += 1
                peripheral.discoverCharacteristics([XiaomiUUID.write, XiaomiUUID.notify], for: xiaomi)
            }
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

            if service.uuid == NbUUID.service {
                for char in service.characteristics ?? [] {
                    if char.uuid == NbUUID.write { ninebotWrite = char }
                    if char.uuid == NbUUID.notify { ninebotNotify = char }
                }
                if let ninebotNotify {
                    peripheral.setNotifyValue(true, for: ninebotNotify)
                }
            } else if service.uuid == XiaomiUUID.service {
                for char in service.characteristics ?? [] {
                    if char.uuid == XiaomiUUID.write { xiaomiWrite = char }
                    if char.uuid == XiaomiUUID.notify { xiaomiNotify = char }
                }
                if let xiaomiNotify {
                    peripheral.setNotifyValue(true, for: xiaomiNotify)
                }
            }

            pendingCharDiscoveries = max(0, pendingCharDiscoveries - 1)
            guard pendingCharDiscoveries == 0 else { return }

            guard hasNinebotPipe || hasXiaomiPipe else {
                connectContinuation?.resume(throwing: BleError.notConnected)
                connectContinuation = nil
                fail("UART-Characteristics unvollständig")
                return
            }

            // Noch keinen Stack aktivieren — das macht die Erkennung.
            var parts: [String] = []
            if hasNinebotPipe { parts.append("Ninebot") }
            if hasXiaomiPipe { parts.append("Xiaomi-NUS") }
            statusMessage = "Verbunden (\(parts.joined(separator: " + ")))"
            connectContinuation?.resume()
            connectContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            if characteristic.uuid == XiaomiUUID.notify {
                // Nordic-UART kann Xiaomi-Klartext ODER Ninebot-Enc2 (Kompatibilität) tragen.
                if activeStack == .ninebotEnc2, enc2PipeIsNordic {
                    let frames = assembler.append(data)
                    for frame in frames { deliverFrame(frame) }
                } else {
                    let frames = xiaomiAssembler.append(data)
                    guard activeStack == .xiaomiPlain || activeStack == .xiaomiEncrypted else { return }
                    for frame in frames { deliverFrame(frame) }
                }
            } else if characteristic.uuid == NbUUID.notify {
                let frames = assembler.append(data)
                guard activeStack == .ninebotEnc2, !enc2PipeIsNordic else { return }
                for frame in frames {
                    deliverFrame(frame)
                }
            }
        }
    }
}

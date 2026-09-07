import Foundation
import CoreBluetooth
import Combine

// MARK: - BLE UUIDs

private enum NbUUID {
    /// Klassische Ninebot-UART-Service-UUID (ältere Modelle).
    static let service = CBUUID(string: "6E400001-0000-0000-006E-696E65626F74")
    static let write = CBUUID(string: "6E400002-0000-0000-006E-696E65626F74")
    /// Manche Firmwares nutzen 003, manche 004 als Notify.
    static let notify = CBUUID(string: "6E400004-0000-0000-006E-696E65626F74")
    static let notifyAlt = CBUUID(string: "6E400003-0000-0000-006E-696E65626F74")
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
    /// SHU-ähnliche Modellbezeichnung aus dem Advertisement (z. B. „Ninebot Max G3“).
    let modelLabel: String?
    /// Kurzes Badge (z. B. „Max G3“), falls erkannt.
    let modelBadge: String?
    let suggestedProfile: ScooterProfile?

    static func == (lhs: ScannedDevice, rhs: ScannedDevice) -> Bool {
        lhs.id == rhs.id
            && lhs.rssi == rhs.rssi
            && lhs.name == rhs.name
            && lhs.cryptoName == rhs.cryptoName
            && lhs.looksLikeScooter == rhs.looksLikeScooter
            && lhs.modelLabel == rhs.modelLabel
            && lhs.modelBadge == rhs.modelBadge
            && lhs.suggestedProfile == rhs.suggestedProfile
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
    /// Profil-Hinweis für Register-Map (z. B. Max-G3-Board-Adressen).
    private var dumpProfileHint: ScooterProfile = .maxG3D
    /// Pairing-Zielboard aus PRE_COMM-Antwort (oft 0x04 oder 0x21).
    private var pairingBoard: Nb.Board = .ble
    private var discoveredServiceSummary = ""

    private let assembler = FrameAssembler()
    private let xiaomiAssembler = XiaomiFrameAssembler()
    private var pendingContinuation: CheckedContinuation<Data, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var notifyReadyFallback: CheckedContinuation<Void, Never>?
    private var pendingNotifyEnables = 0

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
        guard !notifies.isEmpty else { return }

        for char in notifies {
            peripheral.setNotifyValue(false, for: char)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)

        pendingNotifyEnables = notifies.count
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.notifyReadyFallback = continuation
            for char in notifies {
                peripheral.setNotifyValue(true, for: char)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.finishNotifyReady()
            }
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        assembler.reset()
        xiaomiAssembler.reset()
        pendingContinuation = nil
    }

    private func finishNotifyReady() {
        guard let cont = notifyReadyFallback else { return }
        notifyReadyFallback = nil
        pendingNotifyEnables = 0
        cont.resume()
    }

    private func noteNotifyStateUpdated(enabled: Bool) {
        guard enabled, pendingNotifyEnables > 0 else { return }
        pendingNotifyEnables -= 1
        if pendingNotifyEnables <= 0 {
            finishNotifyReady()
        }
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
        dumpProfileHint = profile

        let name = cryptoName.isEmpty ? btName : cryptoName
        let isMaxG3 = profile.family == .maxG3 || name.uppercased().hasPrefix("1C")

        // Max G3 (SHU/Flasher): ausschließlich Nordic-UART — Ninebot-Custom-UART
        // timed out bisher und verdeckte den eigentlichen Nordic-Fehler.
        if isMaxG3 {
            guard hasXiaomiPipe else {
                fail(
                    "Max G3: Nordic-UART fehlt"
                        + (discoveredServiceSummary.isEmpty ? "" : " (gefunden: \(discoveredServiceSummary))")
                        + ". Scooter neu starten und erneut scannen."
                )
                return
            }

            clearPassword()
            phase = .detecting
            statusMessage = "Max G3: Enc2 über Nordic-UART…"
            activateEnc2(useNordicUART: true)
            assembler.reset()
            do {
                try await runNinebotHandshakeAndDump(preferGen2: true)
                return
            } catch {
                fail(
                    "Max G3 Enc2 fehlgeschlagen — Nordic-UART: \(error.localizedDescription)"
                        + ". Scooter eingeschaltet lassen; bei Pairing Power-Taste drücken."
                )
                return
            }
        }

        let order = detectionOrder(profileHint: profile, name: name)
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
                let pipes: [(String, Bool)] = [
                    hasNinebotPipe ? ("Ninebot-UART", false) : nil,
                    hasXiaomiPipe ? ("Nordic-UART/Enc2", true) : nil
                ].compactMap { $0 }

                for (label, useNordic) in pipes {
                    guard peripheral != nil else {
                        fail("Scooter hat die Verbindung getrennt. Erneut verbinden.")
                        return
                    }
                    phase = .detecting
                    statusMessage = "Prüfe Ninebot Enc2 (\(label))…"
                    activateEnc2(useNordicUART: useNordic)
                    assembler.reset()
                    do {
                        try await runNinebotHandshakeAndDump(preferGen2: false)
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

    private func runNinebotHandshakeAndDump(preferGen2: Bool = false) async throws {
        phase = .handshake
        statusMessage = "Ninebot Enc2: Handshake…"

        var succeeded = false
        var lastError: Error?
        // Max G3 / SHU: Gen2 (fw_data-Key) zuerst — Gen3-Nullkey scheitert und kann disconnecten.
        let gens: [ProtocolGen] = preferGen2 ? [.gen2, .gen3] : [.gen3, .gen2]
        for gen in gens {
            guard peripheral != nil else {
                throw BleError.notConnected
            }
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
                if gen == gens.last { break }
                statusMessage = "\(gen.rawValue) fehlgeschlagen, versuche Alternative…"
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

        // Phase 1: PRE_COMM — Gen2: key2/ECB = fw_data (SHU/NinebotCrypto); Gen3: Nullen.
        // Ziel 0x04 und Fallback 0x21 (BLE-Legacy), danach Pairing an Antwort-Board.
        let nameKey = Data((cryptoName.isEmpty ? btName : cryptoName).utf8)

        var preResp: Data?
        var lastPreError: Error?
        var usedTarget: Nb.Board = .ble
        let preAttempts = preferGen2StyleRetries(for: gen)

        targetLoop: for target in [Nb.Board.ble, .bleLegacy] {
            for attempt in 1...preAttempts {
                guard peripheral != nil else { throw BleError.notConnected }
                crypto.resetSN()
                crypto.setKey(nameKey, nil)
                assembler.reset()
                statusMessage = "Enc2 PRE_COMM (\(gen.rawValue), Board 0x\(String(format: "%02X", target.rawValue)), \(attempt)/\(preAttempts))…"
                let prePlain = Nb.preComm(target: target, gen: gen)
                do {
                    let resp = try await sendReceive(plain: prePlain, crypto: crypto, timeout: 2.0)
                    if resp == prePlain {
                        throw BleError.handshakeFailed("Gerät hat PRE_COMM zurückgespiegelt (iOS-BLE-Echo)")
                    }
                    preResp = resp
                    usedTarget = target
                    break targetLoop
                } catch {
                    lastPreError = error
                    if case BleError.notConnected = error { throw error }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        guard let preResp else {
            throw lastPreError ?? BleError.timeout
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

        if let peer = Nb.Board(rawValue: parsed.boardId) {
            pairingBoard = peer
        } else {
            pairingBoard = usedTarget
        }

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

            let setPlain = Nb.setPwd(password!, target: pairingBoard, gen: gen)
            let setResp = try await sendReceive(plain: setPlain, crypto: crypto, timeout: 8)
            guard let setParsed = Nb.parse(setResp), setParsed.cmd == Nb.Cmd.setPwd.rawValue else {
                throw BleError.handshakeFailed("Ungültige SET_PWD-Antwort")
            }

            if setParsed.index == 0 {
                phase = .waitingButton
                statusMessage = "Bitte Power-Taste am Scooter drücken…"
                let retryResp = try await waitForButtonPress(
                    crypto: crypto,
                    gen: gen,
                    password: password!,
                    timeout: 60
                )
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
        let authPlain = Nb.auth(serialNumber: serialNumber, target: pairingBoard, gen: gen)
        var authParsed: Nb.ParsedFrame?
        for attempt in 1...6 {
            guard peripheral != nil else { throw BleError.notConnected }
            statusMessage = "Enc2 AUTH (Versuch \(attempt)/6)…"
            do {
                let authResp = try await sendReceive(plain: authPlain, crypto: crypto, timeout: 4)
                if let parsed = Nb.parse(authResp), parsed.cmd == Nb.Cmd.auth.rawValue {
                    authParsed = parsed
                    break
                }
            } catch {
                if case BleError.notConnected = error { throw error }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        guard let authParsed else {
            throw BleError.handshakeFailed("Ungültige AUTH-Antwort")
        }

        if authParsed.index != 1 {
            clearPassword()
            throw BleError.handshakeFailed("AUTH abgelehnt — Passwort gelöscht")
        }

        statusMessage = "Authentifiziert (\(gen.rawValue), Board 0x\(String(format: "%02X", pairingBoard.rawValue)))"
    }

    private func preferGen2StyleRetries(for gen: ProtocolGen) -> Int {
        gen == .gen2 ? 4 : 2
    }

    private func waitForButtonPress(
        crypto: NbCrypto,
        gen: ProtocolGen,
        password: Data,
        timeout: TimeInterval
    ) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSend = Date.distantPast
        let setPlain = Nb.setPwd(password, target: pairingBoard, gen: gen)

        while Date() < deadline {
            guard peripheral != nil else { throw BleError.notConnected }

            // Wie SHU/Flasher: SET_PWD alle ~0,5 s erneut, bis Power-Taste OK liefert.
            if Date().timeIntervalSince(lastSend) >= 0.5 {
                lastSend = Date()
                statusMessage = "Bitte Power-Taste am Scooter drücken…"
                do {
                    let resp = try await sendReceive(plain: setPlain, crypto: crypto, timeout: 0.9)
                    if let parsed = Nb.parse(resp),
                       parsed.cmd == Nb.Cmd.setPwd.rawValue,
                       parsed.index == 1 {
                        return resp
                    }
                } catch {
                    if case BleError.notConnected = error { throw error }
                    // Timeout = Taste noch nicht gedrückt — weiter pollen.
                }
            } else {
                try? await Task.sleep(nanoseconds: 50_000_000)
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

        // Max G3: BLE-Name ist oft schon die Geräte-ID (wie in SHU).
        if let id = BleModelHint.compactScooterId(from: cryptoName.isEmpty ? btName : cryptoName) {
            reading.serialDisplay = id
            reading.serialBle = reading.serialBle ?? id
        }

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

        // Read diagnostic fields (G3 nutzt zusätzliche Board-/Versions-Adressen)
        let specs = DiagnosticMap.fields(for: dumpProfileHint)
        let total = specs.count
        for (index, spec) in specs.enumerated() {
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
            } catch {
                continue
            }

            // Small gap to avoid flooding the BLE module
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        reading.evidenceSha256 = NbCrypto.sha256(evidence).map { String(format: "%02x", $0) }.joined()
        // If serial still empty but BLE name is a compact ID, keep the scan-time ID.
        if reading.serialDisplay == nil,
           let id = BleModelHint.compactScooterId(from: cryptoName.isEmpty ? btName : cryptoName) {
            reading.serialDisplay = id
        }
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
        // Continuation VOR dem Write setzen — sonst gehen schnelle Antworten verloren.
        let encryptedResp = try await requestResponse(encrypted, timeout: timeout)
        return try crypto.decrypt(encryptedResp)
    }

    private func sendReceiveXiaomi(_ frame: Data, timeout: TimeInterval) async throws -> Data {
        try await requestResponse(frame, timeout: timeout)
    }

    private func requestResponse(_ data: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingContinuation = continuation
            Task { @MainActor in
                do {
                    try await self.write(data)
                } catch {
                    if let pending = self.pendingContinuation {
                        self.pendingContinuation = nil
                        pending.resume(throwing: error)
                    }
                    return
                }
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

        let canWithoutResponse = writeChar.properties.contains(.writeWithoutResponse)
        let canWithResponse = writeChar.properties.contains(.write)
        // Nordic-UART/Enc2: ohne Response wie SHU/Flasher — withResponse kann hängen.
        let type: CBCharacteristicWriteType =
            (enc2PipeIsNordic && canWithoutResponse) || (canWithoutResponse && !canWithResponse)
            ? .withoutResponse
            : (canWithResponse ? .withResponse : .withoutResponse)
        guard canWithoutResponse || canWithResponse else { throw BleError.notConnected }

        let mtu = peripheral.maximumWriteValueLength(for: type)
        let chunkSize = max(mtu, 20)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            peripheral.writeValue(chunk, for: writeChar, type: type)
            offset = end
            if offset < data.count {
                try await Task.sleep(nanoseconds: 15_000_000)
            }
        }
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
        case .bleLegacy: return "BLE(0x21)"
        case .vcu: return "VCU"
        case .vcuG3: return "VCU(G3)"
        case .mcu: return "MCU"
        case .mcuG3: return "MCU(G3)"
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
        pairingBoard = .ble
        discoveredServiceSummary = ""
        cryptoName = ""
        assembler.reset()
        xiaomiAssembler.reset()
        pendingContinuation = nil
        connectContinuation = nil
        notifyReadyFallback = nil
        pendingNotifyEnables = 0
    }

    /// Strikte Heuristik für „Nur Scooter“ — lieber zu wenig als Nuki/OLED/TV als Scooter.
    nonisolated static func isLikelyScooterName(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let upper = name.uppercased()
        let compact = String(upper.filter { $0.isLetter || $0.isNumber })

        // Bekannte Nicht-Scooter (Smart Home, Displays, Audio…)
        let blocklist = [
            "NUKI", "OLED", "IPHONE", "IPAD", "WATCH", "AIRPOD", "GALAXY", "SAMSUNG",
            "PIXEL", "HUAWEI", "SONOS", "BOSE", "JBL", "HEADPHONE", "SPEAKER",
            "TV", "LG ", "SONY", "XBOX", "PLAYSTATION", "SWITCH", "FITBIT",
            "GARMIN", "COROS", "WHOOP", "THERMOSTAT", "HUE ", "NEST", "RING",
            "CORE300", "Q-SERIES", "QSERIES"
        ]
        if blocklist.contains(where: { upper.contains($0) || compact.contains($0.replacingOccurrences(of: " ", with: "")) }) {
            return false
        }

        // Marken / Modellnamen
        let tokens = [
            "NINEBOT", "SEGWAY", "ZT3", "G30", "MAX3", "MAX G3", "G3 PLUS",
            "XIAOMI", "M365", "MI ELECTRIC", "MI SCOOTER",
            "SCOOTER 3", "SCOOTER 4", "PRO 2", "PRO2", "KICKSCOOTER"
        ]
        if tokens.contains(where: { upper.contains($0) }) { return true }
        // „SCOOTER“ nur als ganzes Wort (nicht in Zufallsstrings)
        if upper.range(of: #"\bSCOOTER\b"#, options: .regularExpression) != nil { return true }
        // „G3“ als Wort — nicht in beliebigen IDs
        if upper.range(of: #"\bG3\b"#, options: .regularExpression) != nil { return true }

        // Serien-/BLE-Präfixe
        if compact.hasPrefix("1C"), compact.count >= 10, compact.count <= 20 {
            // Max G3 Advertisement-IDs, z. B. 1CGBF2531C0230
            return true
        }
        if compact.hasPrefix("N2DT") || compact.hasPrefix("N2ET") || compact.hasPrefix("N2FS")
            || compact.hasPrefix("N2DS") || compact.hasPrefix("N4GS") || compact.hasPrefix("XN4B") {
            return true
        }
        if upper.hasPrefix("NB-") || upper.hasPrefix("NB_") { return true }

        // F-/D-Serie nur mit klaren Modellmustern
        if upper.range(of: #"\bF[234](\s|/|-)?(PRO|PLUS|D|E)?\b"#, options: .regularExpression) != nil {
            return true
        }
        if upper.range(of: #"\bD(18|28|38)\b"#, options: .regularExpression) != nil {
            return true
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
            let hint = BleModelHint.recognize(bleName: rawName.isEmpty ? nil : rawName)
            let device = ScannedDevice(
                id: peripheral.identifier,
                name: name,
                cryptoName: rawName,
                rssi: rssiValue,
                peripheral: peripheral,
                looksLikeScooter: byName || byService || hint != nil,
                modelLabel: hint?.title,
                modelBadge: hint?.shortBadge,
                suggestedProfile: hint?.profile
            )
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                // Badge/Modell beibehalten, sobald einmal erkannt.
                let merged = ScannedDevice(
                    id: device.id,
                    name: device.name,
                    cryptoName: device.cryptoName.isEmpty ? devices[index].cryptoName : device.cryptoName,
                    rssi: device.rssi,
                    peripheral: device.peripheral,
                    looksLikeScooter: device.looksLikeScooter || devices[index].looksLikeScooter,
                    modelLabel: device.modelLabel ?? devices[index].modelLabel,
                    modelBadge: device.modelBadge ?? devices[index].modelBadge,
                    suggestedProfile: device.suggestedProfile ?? devices[index].suggestedProfile
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
            // Alle Services: Max G3 nutzt Nordic-UART; Filter auf bekannte UUIDs kann fehlschlagen.
            peripheral.discoverServices(nil)
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
            // Pending Continuations fortsetzen — sonst hängt der Handshake ewig.
            if let pending = pendingContinuation {
                pendingContinuation = nil
                pending.resume(throwing: BleError.notConnected)
            }
            if let connect = connectContinuation {
                connectContinuation = nil
                connect.resume(throwing: BleError.notConnected)
            }
            finishNotifyReady()

            let wasActive = phase != .idle && phase != .done && phase != .failed
            resetSession()
            if wasActive {
                fail(
                    "Scooter hat die Verbindung getrennt"
                        + (error.map { " (\($0.localizedDescription))" } ?? "")
                        + ". Scooter an lassen, nah dran bleiben und erneut verbinden."
                )
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
            discoveredServiceSummary = services.map { $0.uuid.uuidString.lowercased() }.joined(separator: ", ")

            let ninebot = services.first(where: { $0.uuid == NbUUID.service })
            // Exakt Nordic-UART; nicht die Ninebot-Custom-UUID (ebenfalls 6e400001-…).
            let nordic = services.first(where: { $0.uuid == XiaomiUUID.service })
                ?? services.first(where: {
                    let u = $0.uuid.uuidString.lowercased()
                    return u.hasPrefix("6e400001-b5a3")
                })

            guard ninebot != nil || nordic != nil else {
                connectContinuation?.resume(throwing: BleError.notConnected)
                connectContinuation = nil
                fail(
                    "Kein UART-Service gefunden"
                        + (discoveredServiceSummary.isEmpty ? "" : ": \(discoveredServiceSummary)")
                )
                return
            }

            pendingCharDiscoveries = 0
            if let ninebot {
                pendingCharDiscoveries += 1
                // Alle Characteristics — Notify kann 003 oder 004 sein.
                peripheral.discoverCharacteristics(nil, for: ninebot)
            }
            if let nordic {
                pendingCharDiscoveries += 1
                peripheral.discoverCharacteristics(nil, for: nordic)
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
                    if char.uuid == NbUUID.write || char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                        if ninebotWrite == nil || char.uuid == NbUUID.write { ninebotWrite = char }
                    }
                    if char.uuid == NbUUID.notify || char.uuid == NbUUID.notifyAlt || char.properties.contains(.notify) {
                        if ninebotNotify == nil
                            || char.uuid == NbUUID.notify
                            || char.uuid == NbUUID.notifyAlt {
                            ninebotNotify = char
                        }
                    }
                }
                if let ninebotNotify {
                    peripheral.setNotifyValue(true, for: ninebotNotify)
                }
            } else if service.uuid == XiaomiUUID.service
                        || service.uuid.uuidString.lowercased().hasPrefix("6e400001-b5a3") {
                for char in service.characteristics ?? [] {
                    let u = char.uuid.uuidString.lowercased()
                    if char.uuid == XiaomiUUID.write || u.contains("6e400002")
                        || char.properties.contains(.writeWithoutResponse)
                        || char.properties.contains(.write) {
                        if xiaomiWrite == nil || char.uuid == XiaomiUUID.write || u.contains("6e400002") {
                            xiaomiWrite = char
                        }
                    }
                    if char.uuid == XiaomiUUID.notify || u.contains("6e400003") || u.contains("6e400004")
                        || char.properties.contains(.notify) {
                        if xiaomiNotify == nil || char.uuid == XiaomiUUID.notify || u.contains("6e400003") {
                            xiaomiNotify = char
                        }
                    }
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

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                // Notify-Fehler nicht hart abbrechen — Timeout in prepareNotifyChannel greift.
                statusMessage = "Notify: \(error.localizedDescription)"
            }
            noteNotifyStateUpdated(enabled: characteristic.isNotifying)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            if characteristic.uuid == XiaomiUUID.notify
                || characteristic === xiaomiNotify
                || (enc2PipeIsNordic && characteristic === notifyChar) {
                // Nordic-UART kann Xiaomi-Klartext ODER Ninebot-Enc2 (Kompatibilität) tragen.
                if activeStack == .ninebotEnc2, enc2PipeIsNordic {
                    let frames = assembler.append(data)
                    for frame in frames { deliverFrame(frame) }
                } else {
                    let frames = xiaomiAssembler.append(data)
                    guard activeStack == .xiaomiPlain || activeStack == .xiaomiEncrypted else { return }
                    for frame in frames { deliverFrame(frame) }
                }
            } else if characteristic.uuid == NbUUID.notify
                        || characteristic.uuid == NbUUID.notifyAlt
                        || characteristic === ninebotNotify {
                let frames = assembler.append(data)
                guard activeStack == .ninebotEnc2, !enc2PipeIsNordic else { return }
                for frame in frames {
                    deliverFrame(frame)
                }
            }
        }
    }
}

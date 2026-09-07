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
    @Published var showOnlyLikelyScooters = true

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
    /// Letztes Scan-Gerät für einen Reconnect-Versuch nach Abbruch.
    private var lastConnectDevice: ScannedDevice?
    private var maxG3Enc2RetryUsed = false
    /// Erwarteter Disconnect (z. B. vor „Erneut prüfen“) — kein Fehlerstatus.
    private var expectDisconnect = false
    /// Pairing-Zielboard aus PRE_COMM-Antwort (oft 0x04 oder 0x21).
    private var pairingBoard: Nb.Board = .ble
    private var discoveredServiceSummary = ""

    private let assembler = FrameAssembler()
    private let xiaomiAssembler = XiaomiFrameAssembler()
    private var pendingContinuation: CheckedContinuation<Data, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var notifyReadyFallback: CheckedContinuation<Void, Never>?
    private var pendingNotifyEnables = 0
    /// Monoton steigend — verhindert, dass abgelaufene Timeout-Tasks den nächsten Request killen.
    private var bleRequestSerial: UInt64 = 0
    private var activeBleRequestSerial: UInt64 = 0
    /// Frames, die ankommen während kein sendReceive wartet (z. B. Power-Taste).
    private var incomingEncryptedFrames: [Data] = []

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
        // Verbundene Scooter werben oft nicht — trennen und als Seed behalten,
        // sonst bleibt „Erneut prüfen“ leer, obwohl das Handy noch verbunden ist.
        let seed = disconnectForRescan()
        devices.removeAll()
        if let seed {
            devices.append(seed)
        }
        for peripheral in retrieveAlreadyConnectedScooters() {
            upsertScanned(fromConnected: peripheral)
        }
        phase = .scanning
        let seeded = !devices.isEmpty
        statusMessage = showOnlyLikelyScooters
            ? (seeded ? "Verbunden · suche weitere Scooter…" : "Suche vermutete Scooter…")
            : (seeded ? "Verbunden · suche weitere BLE-Geräte…" : "Suche alle BLE-Geräte in der Nähe…")
        // AllowDuplicates: RSSI live aktualisieren, um bei mehreren Geräten das nähere zu erkennen.
        // withServices: nil — wie SHU alle BLE-Advertiser erfassen (nicht nur bekannte Service-UUIDs).
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    /// Trennt die aktive Session, damit der Scooter wieder advertisieren kann.
    /// Gibt das zuletzt verbundene Gerät zurück, damit die UI es sofort anzeigt.
    private func disconnectForRescan() -> ScannedDevice? {
        let active = peripheral ?? lastConnectDevice?.peripheral
        guard let active else { return nil }
        let connected = active.state == .connected || active.state == .connecting
        guard connected || peripheral != nil else { return nil }

        let seed = lastConnectDevice.map { previous in
            ScannedDevice(
                id: active.identifier,
                name: previous.name,
                cryptoName: previous.cryptoName.isEmpty
                    ? (cryptoName.isEmpty ? btName : cryptoName)
                    : previous.cryptoName,
                rssi: max(previous.rssi, -55),
                peripheral: active,
                looksLikeScooter: true,
                modelLabel: previous.modelLabel,
                modelBadge: previous.modelBadge,
                suggestedProfile: previous.suggestedProfile
            )
        } ?? ScannedDevice(
            id: active.identifier,
            name: btName.isEmpty ? (active.name ?? "Verbunden") : btName,
            cryptoName: cryptoName.isEmpty ? (active.name ?? "") : cryptoName,
            rssi: -55,
            peripheral: active,
            looksLikeScooter: true,
            modelLabel: nil,
            modelBadge: nil,
            suggestedProfile: nil
        )

        central.cancelPeripheralConnection(active)
        expectDisconnect = true
        resetSession()
        return seed
    }

    private func retrieveAlreadyConnectedScooters() -> [CBPeripheral] {
        central.retrieveConnectedPeripherals(withServices: [NbUUID.service, XiaomiUUID.service])
    }

    private func upsertScanned(fromConnected peripheral: CBPeripheral) {
        let rawName = (peripheral.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shortId = String(peripheral.identifier.uuidString.prefix(8))
        let name = rawName.isEmpty ? "Verbunden (\(shortId))" : rawName
        let hint = BleModelHint.recognize(bleName: rawName.isEmpty ? nil : rawName)
        let device = ScannedDevice(
            id: peripheral.identifier,
            name: name,
            cryptoName: rawName,
            rssi: -50,
            peripheral: peripheral,
            looksLikeScooter: true,
            modelLabel: hint?.title,
            modelBadge: hint?.shortBadge,
            suggestedProfile: hint?.profile
        )
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            let existing = devices[index]
            devices[index] = ScannedDevice(
                id: device.id,
                name: existing.name.isEmpty ? device.name : existing.name,
                cryptoName: existing.cryptoName.isEmpty ? device.cryptoName : existing.cryptoName,
                rssi: existing.rssi,
                peripheral: peripheral,
                looksLikeScooter: true,
                modelLabel: existing.modelLabel ?? device.modelLabel,
                modelBadge: existing.modelBadge ?? device.modelBadge,
                suggestedProfile: existing.suggestedProfile ?? device.suggestedProfile
            )
        } else {
            devices.append(device)
        }
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
        lastConnectDevice = device
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

        // Kein Disable/Enable-Tanz wenn Notify schon aktiv — das frisst Pairing-Frames.
        let needEnable = notifies.filter { !$0.isNotifying }
        if needEnable.isEmpty {
            try? await Task.sleep(nanoseconds: 150_000_000)
            assembler.reset()
            xiaomiAssembler.reset()
            incomingEncryptedFrames.removeAll(keepingCapacity: false)
            return
        }

        pendingNotifyEnables = needEnable.count
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.notifyReadyFallback = continuation
            for char in needEnable {
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
        if let pending = pendingContinuation {
            pendingContinuation = nil
            activeBleRequestSerial = 0
            pending.resume(throwing: BleError.timeout)
        }
        incomingEncryptedFrames.removeAll(keepingCapacity: false)
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

            maxG3Enc2RetryUsed = false
            await runMaxG3Enc2WithRetry()
            return
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
        // Max G3: nur Gen2. Gen3-Nullkey scheitert und trennt oft die BLE-Verbindung.
        let gens: [ProtocolGen] = preferGen2 ? [.gen2] : [.gen3, .gen2]
        for gen in gens {
            guard peripheral != nil else {
                throw BleError.notConnected
            }
            do {
                // Max G3 / Flasher: Pairing komplett Non-SN (kein startSN nach PRE_COMM).
                try await runHandshake(gen: gen, nonSNPairing: preferGen2)
                protocolGen = gen
                detectedStack = .ninebotEnc2
                activeStack = .ninebotEnc2
                succeeded = true
                break
            } catch {
                lastError = error
                crypto = nil
                if case BleError.notConnected = error { throw error }
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

    /// Max G3 Enc2: Gen2/Non-SN, bei Abbruch einmal Passwort löschen + reconnect.
    private func runMaxG3Enc2WithRetry() async {
        phase = .detecting
        statusMessage = "Max G3: Enc2 über Nordic-UART…"
        activateEnc2(useNordicUART: true)
        assembler.reset()

        do {
            try await runNinebotHandshakeAndDump(preferGen2: true)
            return
        } catch {
            // didDisconnect hat fail() schon gesetzt — nicht mit Enc2-Text überschreiben.
            if phase == .failed { return }

            let canRetry = !maxG3Enc2RetryUsed && lastConnectDevice != nil
            if canRetry {
                maxG3Enc2RetryUsed = true
                clearPassword()
                statusMessage = "Verbindung abgebrochen — baue neu auf…"
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let device = lastConnectDevice else {
                    fail(Self.maxG3Enc2FailMessage(error))
                    return
                }
                do {
                    try await connect(to: device)
                    phase = .detecting
                    statusMessage = "Max G3: Enc2 erneut (Power-Taste bereithalten)…"
                    activateEnc2(useNordicUART: true)
                    assembler.reset()
                    try await runNinebotHandshakeAndDump(preferGen2: true)
                    return
                } catch {
                    if phase == .failed { return }
                    fail(Self.maxG3Enc2FailMessage(error))
                    return
                }
            }

            fail(Self.maxG3Enc2FailMessage(error))
        }
    }

    private static func maxG3Enc2FailMessage(_ error: Error) -> String {
        if case BleError.notConnected = error {
            return "Verbindung zum Scooter verloren. Scooter an lassen, nah bleiben und erneut verbinden; bei Pairing Power-Taste drücken."
        }
        let detail = error.localizedDescription
        if detail.localizedCaseInsensitiveContains("handshake failed:") {
            let trimmed = detail.replacingOccurrences(
                of: "Handshake failed: ",
                with: "",
                options: .caseInsensitive
            )
            return "Max G3 Enc2: \(trimmed). Scooter an lassen; bei Pairing Power-Taste drücken."
        }
        return "Max G3 Enc2 fehlgeschlagen — \(detail). Scooter an lassen; bei Pairing Power-Taste drücken."
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
            expectDisconnect = true
            central.cancelPeripheralConnection(peripheral)
        }
        resetSession()
        phase = .idle
        statusMessage = "Getrennt"
    }

    // MARK: - Handshake

    private func runHandshake(gen: ProtocolGen, nonSNPairing: Bool = false) async throws {
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
                // Verspätete Antwort vom vorherigen Versuch?
                if let early = takeQueuedPlain(crypto: crypto, expectedCmd: Nb.Cmd.preComm.rawValue) {
                    preResp = early
                    usedTarget = target
                    break targetLoop
                }
                statusMessage = "Enc2 PRE_COMM (\(gen.rawValue), Board 0x\(String(format: "%02X", target.rawValue)), \(attempt)/\(preAttempts))…"
                let prePlain = Nb.preComm(target: target, gen: gen)
                do {
                    let resp = try await sendReceive(
                        plain: prePlain,
                        crypto: crypto,
                        timeout: nonSNPairing ? 3.0 : 2.0,
                        expectedCmd: Nb.Cmd.preComm.rawValue
                    )
                    if resp == prePlain {
                        throw BleError.handshakeFailed("Gerät hat PRE_COMM zurückgespiegelt (iOS-BLE-Echo)")
                    }
                    preResp = resp
                    usedTarget = target
                    break targetLoop
                } catch {
                    lastPreError = error
                    if case BleError.notConnected = error { throw error }
                    try? await Task.sleep(nanoseconds: 250_000_000)
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
        // Max G3 (offizieller App-/Flasher-Pfad): nach PRE_COMM im Non-SN bleiben.
        // Klassisches NinebotCrypto/SHU: SN-Modus für SET_PWD/AUTH.
        if nonSNPairing {
            crypto.resetSN()
        } else {
            crypto.startSN()
        }

        // Phase 2: SET_PWD (if needed)
        var password = loadPassword()

        // Lokales Passwort, Scooter ohne Bond (index==0) → AUTH scheitert und trennt oft.
        if password != nil && !hasStoredPwd {
            clearPassword()
            password = nil
            statusMessage = "Kein Scooter-Bond — neues Pairing (Power-Taste)…"
        }

        if password == nil && hasStoredPwd {
            statusMessage = "Neues Pairing — gleich Power-Taste am Scooter drücken"
        }

        if password == nil {
            crypto.setKey(nameKey, authParam)
            // Stabiles App-Key-Material wie Max-G3-Flasher (0x00…0x0F), nicht jedes Mal neu random.
            if nonSNPairing {
                password = Data(0..<16)
            } else {
                password = generatePassword(auth: authParam)
            }

            phase = .waitingButton
            statusMessage = "Bitte jetzt die Power-Taste am Scooter drücken…"

            // Non-SN (Max G3): sofort pollen + RX-Queue — kein sendReceive-Fenster,
            // das den Tasten-ACK zwischen Timeouts verwerfen würde.
            // SN-Modus: erstes SET_PWD klassisch, dann pollend warten.
            var setAccepted = false
            if !nonSNPairing {
                let setPlain = Nb.setPwd(password!, target: pairingBoard, gen: gen)
                do {
                    let setResp = try await sendReceive(
                        plain: setPlain,
                        crypto: crypto,
                        timeout: 3,
                        expectedCmd: Nb.Cmd.setPwd.rawValue
                    )
                    if let setParsed = Nb.parse(setResp), setParsed.cmd == Nb.Cmd.setPwd.rawValue {
                        if setParsed.index == 1 {
                            setAccepted = true
                        } else if setParsed.index != 0 {
                            throw BleError.handshakeFailed("SET_PWD abgelehnt")
                        }
                    }
                } catch {
                    if case BleError.notConnected = error { throw error }
                }
            }

            if !setAccepted {
                let retryResp = try await waitForButtonPress(
                    crypto: crypto,
                    gen: gen,
                    password: password!,
                    timeout: 60,
                    preferPairingBoardOnly: nonSNPairing
                )
                guard let retryParsed = Nb.parse(retryResp),
                      retryParsed.cmd == Nb.Cmd.setPwd.rawValue,
                      retryParsed.index == 1 else {
                    throw BleError.handshakeFailed("SET_PWD abgelehnt (Taste nicht gedrückt?)")
                }
            }
        }

        sessionPassword = password!
        savePassword(sessionPassword)

        // Phase 3: AUTH — SET_PWD-Reste aus der Queue entfernen, sonst landet ACK im AUTH-Waiter.
        crypto.setKey(sessionPassword, authParam)
        if nonSNPairing {
            crypto.resetSN()
        }
        flushQueuedCommands(crypto: crypto, cmds: [Nb.Cmd.setPwd.rawValue])
        let authPlain = Nb.auth(serialNumber: serialNumber, target: pairingBoard, gen: gen)
        var authParsed: Nb.ParsedFrame?
        for attempt in 1...6 {
            guard peripheral != nil else { throw BleError.notConnected }
            statusMessage = "Enc2 AUTH (Versuch \(attempt)/6)…"
            if nonSNPairing {
                crypto.resetSN()
            }
            flushQueuedCommands(crypto: crypto, cmds: [Nb.Cmd.setPwd.rawValue])
            do {
                let authResp = try await sendReceive(
                    plain: authPlain,
                    crypto: crypto,
                    timeout: 4,
                    expectedCmd: Nb.Cmd.auth.rawValue
                )
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

        // Nach erfolgreichem Pairing: Max G3 oft weiter Non-SN; sonst SN für Register.
        if nonSNPairing {
            crypto.resetSN()
        } else {
            crypto.startSN()
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
        timeout: TimeInterval,
        preferPairingBoardOnly: Bool = false
    ) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSend = Date.distantPast
        // Max G3: nur Pairing-Board — weniger TX-Flood / Disconnects.
        // Sonst Pairing + Legacy rotieren.
        let targets: [Nb.Board] = {
            if preferPairingBoardOnly { return [pairingBoard] }
            var list = [pairingBoard]
            for board in [Nb.Board.ble, .bleLegacy] where !list.contains(board) {
                list.append(board)
            }
            return list
        }()
        var targetIndex = 0
        var sendInterval: TimeInterval = preferPairingBoardOnly ? 0.9 : 0.45
        var sendCount = 0

        statusMessage = "Bitte jetzt die Power-Taste am Scooter drücken…"
        // Queue nicht leeren: ACK kann schon zwischen erstem SET_PWD und hier angekommen sein.

        while Date() < deadline {
            guard peripheral != nil else { throw BleError.notConnected }

            // Gepufferte Frames zuerst (Antwort nach Tastendruck kann asynchron kommen).
            if let accepted = try drainSetPwdAccepted(crypto: crypto) {
                return accepted
            }

            if Date().timeIntervalSince(lastSend) >= sendInterval {
                lastSend = Date()
                sendCount += 1
                if preferPairingBoardOnly, sendCount == 4 {
                    sendInterval = 1.2
                }
                let target = targets[targetIndex % targets.count]
                targetIndex += 1
                statusMessage = "Power-Taste drücken… (Board 0x\(String(format: "%02X", target.rawValue)))"
                crypto.resetSN()
                let setPlain = Nb.setPwd(password, target: target, gen: gen)
                do {
                    let encrypted = try crypto.encrypt(setPlain)
                    try await write(encrypted)
                } catch {
                    if case BleError.notConnected = error { throw error }
                }
            }

            // Notify-Zeitfenster: Frames landen in der Queue via deliverFrame.
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        throw BleError.handshakeFailed("Timeout beim Warten auf Power-Taste — Taste länger halten oder Scooter neu starten")
    }

    private func drainSetPwdAccepted(crypto: NbCrypto) throws -> Data? {
        // Snapshot — kein defer-Overwrite, sonst gehen ACKs verloren, die währenddessen ankommen.
        let snapshot = incomingEncryptedFrames
        guard !snapshot.isEmpty else { return nil }

        var kept: [Data] = []
        var accepted: Data?
        for frame in snapshot {
            if accepted == nil,
               let plain = try? crypto.decrypt(frame),
               let parsed = Nb.parse(plain),
               parsed.cmd == Nb.Cmd.setPwd.rawValue,
               parsed.index == 1 {
                accepted = plain
                continue
            }
            // Index-0 / Noise verwerfen; unbekannte Frames behalten wir nicht (Queue-Schutz).
            if let plain = try? crypto.decrypt(frame),
               let parsed = Nb.parse(plain),
               parsed.cmd == Nb.Cmd.setPwd.rawValue {
                continue
            }
            kept.append(frame)
        }

        // Frames, die nach dem Snapshot ankamen, anhängen.
        let arrivedDuringDrain = incomingEncryptedFrames.suffix(
            max(0, incomingEncryptedFrames.count - snapshot.count)
        )
        incomingEncryptedFrames = kept + Array(arrivedDuringDrain)
        return accepted
    }

    /// Entfernt Queue-Frames bestimmter CMDs (z. B. SET_PWD vor AUTH).
    private func flushQueuedCommands(crypto: NbCrypto, cmds: Set<UInt8>) {
        let snapshot = incomingEncryptedFrames
        guard !snapshot.isEmpty else { return }
        var kept: [Data] = []
        for frame in snapshot {
            if let plain = try? crypto.decrypt(frame),
               let parsed = Nb.parse(plain),
               cmds.contains(parsed.cmd) {
                continue
            }
            kept.append(frame)
        }
        let arrived = incomingEncryptedFrames.suffix(max(0, incomingEncryptedFrames.count - snapshot.count))
        incomingEncryptedFrames = kept + Array(arrived)
    }

    /// Nimmt ein passendes Klartext-Frame aus der RX-Queue (Non-SN-sicher).
    private func takeQueuedPlain(crypto: NbCrypto, expectedCmd: UInt8) -> Data? {
        let snapshot = incomingEncryptedFrames
        guard !snapshot.isEmpty else { return nil }
        var kept: [Data] = []
        var hit: Data?
        for frame in snapshot {
            if hit == nil,
               let plain = try? crypto.decrypt(frame),
               let parsed = Nb.parse(plain),
               parsed.cmd == expectedCmd {
                hit = plain
                continue
            }
            kept.append(frame)
        }
        let arrived = incomingEncryptedFrames.suffix(max(0, incomingEncryptedFrames.count - snapshot.count))
        incomingEncryptedFrames = kept + Array(arrived)
        return hit
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

        // Probe boards — Max G3 nur bekannte Zielboards, sonst BLE-Flut/Disconnects.
        let boardsToProbe: [Nb.Board] = dumpProfileHint.usesG3RegisterMap
            ? [.ble, .bleLegacy, .vcuG3, .mcuG3, .bmsG3, .tft]
            : Array(Nb.Board.allCases)
        for board in boardsToProbe {
            let probe = Nb.read(board: board, register: Nb.Register.error, length: 2, gen: protocolGen)
            do {
                let resp = try await sendReceive(plain: probe, crypto: crypto, timeout: 2)
                if let parsed = Nb.parse(resp), parsed.cmd == Nb.Cmd.readResp.rawValue {
                    liveBoards.insert(boardLabel(board))
                }
            } catch {
                if case BleError.notConnected = error { break }
                continue
            }
        }
        reading.liveBoards = liveBoards.sorted()

        // Read diagnostic fields (G3 nutzt zusätzliche Board-/Versions-Adressen)
        let specs = DiagnosticMap.fields(for: dumpProfileHint)
        let total = specs.count
        for (index, spec) in specs.enumerated() {
            statusMessage = "Lese \(spec.id) (\(index + 1)/\(total))…"

            let request: Data
            if dumpProfileHint.usesG3RegisterMap {
                // Segway/G3-Flasher: Längenfeld als u16 LE.
                request = Nb.readU16Len(board: spec.board, register: spec.register, length: spec.readLen, gen: protocolGen)
            } else {
                request = Nb.read(board: spec.board, register: spec.register, length: spec.readLen, gen: protocolGen)
            }
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
                if case BleError.notConnected = error { break }
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

    private func sendReceive(
        plain: Data,
        crypto: NbCrypto,
        timeout: TimeInterval,
        expectedCmd: UInt8? = nil
    ) async throws -> Data {
        if let expectedCmd, let queued = takeQueuedPlain(crypto: crypto, expectedCmd: expectedCmd) {
            return queued
        }
        let encrypted = try crypto.encrypt(plain)
        // Continuation VOR dem Write setzen — sonst gehen schnelle Antworten verloren.
        let encryptedResp = try await requestResponse(encrypted, timeout: timeout)
        let decrypted = try crypto.decrypt(encryptedResp)
        if let expectedCmd,
           let parsed = Nb.parse(decrypted),
           parsed.cmd != expectedCmd {
            // Falsches CMD (z. B. SET_PWD während AUTH) → Queue, Caller retry't.
            incomingEncryptedFrames.insert(encryptedResp, at: 0)
            throw BleError.timeout
        }
        return decrypted
    }

    private func sendReceiveXiaomi(_ frame: Data, timeout: TimeInterval) async throws -> Data {
        try await requestResponse(frame, timeout: timeout)
    }

    private func requestResponse(_ data: Data, timeout: TimeInterval) async throws -> Data {
        bleRequestSerial += 1
        let requestID = bleRequestSerial
        activeBleRequestSerial = requestID

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingContinuation = continuation
            Task { @MainActor in
                do {
                    try await self.write(data)
                } catch {
                    guard self.activeBleRequestSerial == requestID,
                          let pending = self.pendingContinuation else { return }
                    self.pendingContinuation = nil
                    self.activeBleRequestSerial = 0
                    pending.resume(throwing: error)
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                // Nur eigener Request — kein Timeout auf den Nachfolger.
                guard self.activeBleRequestSerial == requestID,
                      let pending = self.pendingContinuation else { return }
                self.pendingContinuation = nil
                self.activeBleRequestSerial = 0
                pending.resume(throwing: BleError.timeout)
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
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            activeBleRequestSerial = 0
            continuation.resume(returning: encrypted)
            return
        }
        // Power-Taste / asynchrone Antworten nicht verwerfen.
        incomingEncryptedFrames.append(encrypted)
        if incomingEncryptedFrames.count > 48 {
            incomingEncryptedFrames.removeFirst(incomingEncryptedFrames.count - 48)
        }
    }

    // MARK: - Password persistence

    private var passwordDefaultsKey: String {
        let id = peripheral?.identifier.uuidString
            ?? lastConnectDevice?.peripheral.identifier.uuidString
            ?? "unknown"
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
        case .bmsG3: return "BMS(G3)"
        case .tft: return "TFT"
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
        activeBleRequestSerial = 0
        incomingEncryptedFrames.removeAll(keepingCapacity: false)
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
            "NINEBOT", "SEGWAY", "ZT3", "G30", "MAX3", "MAX G3", "G3 PLUS", "MAX G2", "MAXG2",
            "XIAOMI", "M365", "MI ELECTRIC", "MI SCOOTER",
            "SCOOTER 3", "SCOOTER 4", "PRO 2", "PRO2", "PRO 3", "PRO3", "ESSENTIAL", "KICKSCOOTER"
        ]
        if tokens.contains(where: { upper.contains($0) }) { return true }
        // „SCOOTER“ nur als ganzes Wort (nicht in Zufallsstrings)
        if upper.range(of: #"\bSCOOTER\b"#, options: .regularExpression) != nil { return true }
        // „G3“ / „G2“ als Wort — nicht in beliebigen IDs
        if upper.range(of: #"\bG3\b"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"\bG2\b"#, options: .regularExpression) != nil { return true }

        // Serien-/BLE-Präfixe
        if compact.hasPrefix("1C"), compact.count >= 10, compact.count <= 20 {
            // Max G3 Advertisement-IDs, z. B. 1CGBF2531C0230
            return true
        }
        if compact.hasPrefix("N2DT") || compact.hasPrefix("N2ET") || compact.hasPrefix("N2FS")
            || compact.hasPrefix("N2DS") || compact.hasPrefix("N2ES") || compact.hasPrefix("N4GS")
            || compact.hasPrefix("XN4B") {
            return true
        }
        if upper.hasPrefix("NB-") || upper.hasPrefix("NB_") { return true }

        // F-/D-/E-Serie nur mit klaren Modellmustern
        if upper.range(of: #"\bF[234](\s|/|-)?(PRO|PLUS|D|E)?\b"#, options: .regularExpression) != nil {
            return true
        }
        if upper.range(of: #"\bD(18|28|38)\b"#, options: .regularExpression) != nil {
            return true
        }
        if upper.range(of: #"\bE(2[0-9]|4[0-9]|5[0-9])\b"#, options: .regularExpression) != nil {
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

            if expectDisconnect {
                expectDisconnect = false
                resetSession()
                return
            }

            let wasActive = phase != .idle && phase != .done && phase != .failed && phase != .scanning
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

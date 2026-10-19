import Foundation
import CoreBluetooth

/// Kurze, nutzerausgelöste Capability-Prüfung + dokumentierte Find-/LED-Schreibbefehle.
/// Getrennt von `BleClient` (Ninebot-UART) und von der reinen Read-GATT-Analyse.
@MainActor
final class BLECapabilityService: NSObject, ObservableObject {
    @Published private(set) var phase: BLELocateActionPhase = .idle
    @Published private(set) var capabilities = BLEDeviceCapabilities()
    @Published private(set) var lastWriteNote: String?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var targetId: UUID?
    private var keepAlive = false
    private var collected: [BLECapabilityDeriver.CharProbe] = []
    private var serviceUUIDs: [String] = []
    private var pendingDiscovers = 0
    private var didFinishProbe = false
    private var alertCharacteristic: CBCharacteristic?
    private var nordicLedCharacteristic: CBCharacteristic?
    private var awaitingWriteConfirm = false
    private var connectTimeoutTask: Task<Void, Never>?

    func reset() {
        disconnect(clearCaps: true)
        phase = .idle
        lastWriteNote = nil
    }

    /// Verbindet nach Nutzeraktion und ermittelt unterstützte Schnittstellen.
    func probe(device: ScannedDevice) {
        disconnect(clearCaps: false)
        guard device.isConnectable != false else {
            phase = .failed("Gerät wirbt nicht als verbindbar.")
            return
        }
        targetId = device.id
        phase = .probing
        capabilities = BLEDeviceCapabilities()
        collected = []
        serviceUUIDs = []
        pendingDiscovers = 0
        didFinishProbe = false
        alertCharacteristic = nil
        nordicLedCharacteristic = nil
        lastWriteNote = nil
        keepAlive = true
        peripheral = device.peripheral
        peripheral?.delegate = self
        let mgr = CBCentralManager(delegate: self, queue: nil)
        central = mgr
        scheduleConnectTimeout()
        if mgr.state == .poweredOn {
            connect()
        }
    }

    func sendImmediateAlert(level: BLEImmediateAlertLevel) {
        guard capabilities.supportsImmediateAlert, let peripheral, let ch = alertCharacteristic else {
            phase = .failed("Immediate Alert nicht verfügbar.")
            return
        }
        phase = .sending
        lastWriteNote = nil
        let data = Data([level.rawValue])
        let type: CBCharacteristicWriteType =
            capabilities.alertPreferWriteWithoutResponse ? .withoutResponse : .withResponse
        awaitingWriteConfirm = (type == .withResponse)
        peripheral.writeValue(data, for: ch, type: type)
        if type == .withoutResponse {
            // Kein didWrite-Callback — Befehl abgesetzt, Ton nicht verifiziert.
            phase = .commandSent
            lastWriteNote =
                "Alert-Level \(level.rawValue) gesendet (WriteWithoutResponse). Ob das Gerät piept oder blinkt, ist nicht verifiziert."
        }
    }

    func stopImmediateAlert() {
        sendImmediateAlert(level: .none)
    }

    func setNordicLed(on: Bool) {
        guard capabilities.supportsNordicLed, let peripheral, let ch = nordicLedCharacteristic else {
            phase = .failed("Dokumentierte LED-Funktion nicht verfügbar.")
            return
        }
        phase = .sending
        lastWriteNote = nil
        let data = Data([on ? 0x01 : 0x00])
        let type: CBCharacteristicWriteType =
            ch.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        awaitingWriteConfirm = (type == .withResponse)
        peripheral.writeValue(data, for: ch, type: type)
        if type == .withoutResponse {
            phase = .commandSent
            lastWriteNote = on
                ? "LED-Befehl gesendet. Optische Reaktion nicht verifiziert."
                : "LED-Aus-Befehl gesendet."
        }
    }

    func disconnect(clearCaps: Bool) {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        keepAlive = false
        awaitingWriteConfirm = false
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
        peripheral?.delegate = nil
        peripheral = nil
        central?.delegate = nil
        central = nil
        targetId = nil
        alertCharacteristic = nil
        nordicLedCharacteristic = nil
        if clearCaps {
            capabilities = BLEDeviceCapabilities()
        }
    }

    private func scheduleConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            if phase == .probing || phase == .sending {
                finishProbe(error: "Zeitüberschreitung bei der Verbindung.")
            }
        }
    }

    private func connect() {
        guard let central, let peripheral else { return }
        central.connect(peripheral, options: nil)
    }

    private func finishProbe(error: String? = nil) {
        guard !didFinishProbe else { return }
        didFinishProbe = true
        connectTimeoutTask?.cancel()
        if let error {
            phase = .failed(error)
            if !keepAlive {
                disconnect(clearCaps: false)
            }
            return
        }
        capabilities = BLECapabilityDeriver.derive(
            services: serviceUUIDs,
            characteristics: collected
        )
        phase = .ready
        // Verbindung halten, wenn Aktionen möglich sind — sonst trennen.
        if !capabilities.hasAnyDeviceAction {
            disconnect(clearCaps: false)
        }
    }
}

extension BLECapabilityService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if self.phase == .probing, self.peripheral != nil {
                    self.connect()
                }
            case .poweredOff:
                self.phase = .failed("Bluetooth ist aus.")
                self.disconnect(clearCaps: false)
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.finishProbe(error: error?.localizedDescription ?? "Verbindung abgelehnt.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if self.phase == .probing, !self.didFinishProbe {
                self.finishProbe(error: error?.localizedDescription ?? "Verbindung getrennt.")
            }
        }
    }
}

extension BLECapabilityService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.finishProbe(error: error.localizedDescription)
                return
            }
            let services = peripheral.services ?? []
            self.serviceUUIDs = services.map(\.uuid.uuidString)
            guard !services.isEmpty else {
                self.finishProbe(error: "Keine GATT-Services gefunden.")
                return
            }
            self.pendingDiscovers = services.count
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            self.pendingDiscovers = max(0, self.pendingDiscovers - 1)
            if error == nil {
                for ch in service.characteristics ?? [] {
                    let canWrite = ch.properties.contains(.write)
                    let canWWR = ch.properties.contains(.writeWithoutResponse)
                    self.collected.append(
                        .init(
                            serviceUUID: service.uuid.uuidString,
                            uuid: ch.uuid.uuidString,
                            canWrite: canWrite,
                            canWriteWithoutResponse: canWWR
                        )
                    )
                    if BLECapabilityUUID.matches(ch.uuid.uuidString, shortOrFull: BLECapabilityUUID.alertLevel),
                       BLECapabilityUUID.matches(service.uuid.uuidString, shortOrFull: BLECapabilityUUID.immediateAlertService),
                       canWrite || canWWR {
                        self.alertCharacteristic = ch
                    }
                    if BLECapabilityUUID.matches(
                        ch.uuid.uuidString,
                        shortOrFull: BLECapabilityUUID.nordicLedCharacteristic
                    ), canWrite || canWWR {
                        self.nordicLedCharacteristic = ch
                    }
                }
            }
            if self.pendingDiscovers == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.finishProbe()
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard self.awaitingWriteConfirm else { return }
            self.awaitingWriteConfirm = false
            if let error {
                self.phase = .failed(error.localizedDescription)
                self.lastWriteNote = nil
            } else {
                self.phase = .commandSent
                self.lastWriteNote =
                    "BLE-Write bestätigt. Eine tatsächliche akustische/optische Reaktion des Geräts ist damit nicht verifiziert."
            }
        }
    }
}

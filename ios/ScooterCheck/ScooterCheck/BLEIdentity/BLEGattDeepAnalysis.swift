import Foundation
import CoreBluetooth

/// Optionale, nutzerausgelöste GATT-Analyse (nur lesen, keine Schreibbefehle).
@MainActor
final class BLEGattDeepAnalysis: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case discovering
        case reading
        case done
        case failed(String)
    }

    struct CharacteristicInfo: Identifiable, Equatable {
        var id: String { "\(serviceUUID).\(uuid)" }
        var serviceUUID: String
        var uuid: String
        var properties: String
        var valueText: String?
    }

    struct Report: Equatable {
        var services: [String]
        var characteristics: [CharacteristicInfo]
        var deviceName: String?
        var manufacturerName: String?
        var modelNumber: String?
        var firmwareRevision: String?
        var completedAt: Date
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var report: Report?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var targetId: UUID?
    private var collected: [CharacteristicInfo] = []
    private var serviceUUIDs: [String] = []
    private var pendingReads = 0
    private var didFinish = false

    func start(device: ScannedDevice) {
        cancel()
        guard device.isConnectable != false else {
            phase = .failed("Gerät wirbt nicht als verbindbar.")
            return
        }
        targetId = device.id
        phase = .connecting
        collected = []
        serviceUUIDs = []
        pendingReads = 0
        didFinish = false
        report = nil
        let mgr = CBCentralManager(delegate: self, queue: nil)
        central = mgr
        peripheral = device.peripheral
        peripheral?.delegate = self
        if mgr.state == .poweredOn {
            connect()
        }
    }

    func cancel() {
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
        peripheral?.delegate = nil
        peripheral = nil
        central?.delegate = nil
        central = nil
        targetId = nil
        if case .failed = phase { return }
        if phase != .done, phase != .idle {
            phase = .idle
        }
    }

    private func connect() {
        guard let central, let peripheral else { return }
        phase = .connecting
        central.connect(peripheral, options: nil)
    }

    private func finish(error: String? = nil) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            phase = .failed(error)
        } else {
            report = Report(
                services: serviceUUIDs,
                characteristics: collected,
                deviceName: collectedValue(uuid: "2A00"),
                manufacturerName: collectedValue(uuid: "2A29"),
                modelNumber: collectedValue(uuid: "2A24"),
                firmwareRevision: collectedValue(uuid: "2A26"),
                completedAt: Date()
            )
            phase = .done
        }
        if let p = peripheral {
            central?.cancelPeripheralConnection(p)
        }
    }

    private func collectedValue(uuid: String) -> String? {
        let key = uuid.uppercased()
        return collected.first { $0.uuid.uppercased().contains(key) }?.valueText
    }
}

extension BLEGattDeepAnalysis: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            guard central.state == .poweredOn else {
                if central.state == .poweredOff {
                    self.phase = .failed("Bluetooth ist aus.")
                }
                return
            }
            if self.phase == .connecting {
                self.connect()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.phase = .discovering
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.finish(error: error?.localizedDescription ?? "Verbindung abgelehnt.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if self.phase == .discovering || self.phase == .reading || self.phase == .connecting {
                if !self.didFinish {
                    self.finish(error: error?.localizedDescription ?? "Verbindung getrennt.")
                }
            }
        }
    }
}

extension BLEGattDeepAnalysis: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.finish(error: error.localizedDescription)
                return
            }
            let services = peripheral.services ?? []
            self.serviceUUIDs = services.map(\.uuid.uuidString)
            guard !services.isEmpty else {
                self.finish(error: "Keine GATT-Services gefunden.")
                return
            }
            self.phase = .reading
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.finish(error: error.localizedDescription)
                return
            }
            for ch in service.characteristics ?? [] {
                let props = Self.describe(ch.properties)
                let info = CharacteristicInfo(
                    serviceUUID: service.uuid.uuidString,
                    uuid: ch.uuid.uuidString,
                    properties: props,
                    valueText: nil
                )
                self.collected.append(info)
                // Nur sichere Reads: Device Information / Generic Access Namen
                if ch.properties.contains(.read), Self.isSafeReadable(ch.uuid) {
                    self.pendingReads += 1
                    peripheral.readValue(for: ch)
                }
            }
            self.checkReadsComplete()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            self.pendingReads = max(0, self.pendingReads - 1)
            if error == nil, let data = characteristic.value {
                let text = Self.decode(data)
                if let idx = self.collected.firstIndex(where: {
                    $0.uuid == characteristic.uuid.uuidString
                        && $0.serviceUUID == (characteristic.service?.uuid.uuidString ?? "")
                }) {
                    self.collected[idx].valueText = text
                }
            }
            self.checkReadsComplete()
        }
    }

    private func checkReadsComplete() {
        guard pendingReads == 0, phase == .reading else { return }
        // Kurz warten bis alle Discoveries durch sind
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.phase == .reading else { return }
            self.finish()
        }
    }

    private static func isSafeReadable(_ uuid: CBUUID) -> Bool {
        let s = uuid.uuidString.uppercased()
        let allowed = ["2A00", "2A01", "2A04", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29", "2A50"]
        return allowed.contains { s.contains($0) }
    }

    private static func describe(_ props: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if props.contains(.read) { parts.append("read") }
        if props.contains(.write) { parts.append("write") }
        if props.contains(.writeWithoutResponse) { parts.append("writeWithoutResponse") }
        if props.contains(.notify) { parts.append("notify") }
        if props.contains(.indicate) { parts.append("indicate") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    private static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8),
           s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

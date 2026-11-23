import Foundation

/// Serialisiert konkurrierende BLE-Central-Nutzung zwischen `BleClient` (Restore-ID)
/// und sekundären Centrals (`BLEGattDeepAnalysis`, `BLECapabilityService`).
///
/// Sekundäre Services **müssen** vor `CBCentralManager`-Erzeugung eine Lease holen
/// und sie nach Cancel/Done wieder freigeben. `BleClient` hält die exclusive
/// Auslese-/Handshake-Lease und blockiert damit Neben-Centrals.
@MainActor
enum BLECentralCoordinator {
    enum Owner: String, Equatable, Sendable {
        case bleClient
        case gattDeepAnalysis
        case capabilityService
    }

    enum LeaseError: Error, Equatable, LocalizedError {
        case busy(Owner)

        var errorDescription: String? {
            switch self {
            case .busy(let owner):
                return "Bluetooth wird gerade von \(owner.rawValue) genutzt. Bitte warten oder trennen."
            }
        }
    }

    private static var holder: Owner?
    private static var bleClientExclusive = false

    /// Ob Auslesen/Handshake exklusiv den Stack beansprucht.
    static var isBleClientExclusive: Bool { bleClientExclusive }

    static var currentOwner: Owner? { holder }

    /// BleClient: Scan bleibt freigegeben für Watch-Erweiterung; Connect/Dump blockiert Neben-Centrals.
    static func beginBleClientExclusive() {
        bleClientExclusive = true
        holder = .bleClient
    }

    static func endBleClientExclusive() {
        if holder == .bleClient {
            holder = nil
        }
        bleClientExclusive = false
    }

    /// Sekundärer Central: schlägt fehl, wenn BleClient exklusiv oder anderer Neben-Central aktiv.
    @discardableResult
    static func acquire(_ owner: Owner) throws -> Owner {
        precondition(owner != .bleClient, "BleClient uses beginBleClientExclusive()")
        if bleClientExclusive || holder == .bleClient {
            throw LeaseError.busy(.bleClient)
        }
        if let holder, holder != owner {
            throw LeaseError.busy(holder)
        }
        holder = owner
        return owner
    }

    static func release(_ owner: Owner) {
        guard holder == owner else { return }
        holder = nil
    }

    /// Test-/Diagnosehilfe.
    static func resetForTests() {
        holder = nil
        bleClientExclusive = false
    }
}

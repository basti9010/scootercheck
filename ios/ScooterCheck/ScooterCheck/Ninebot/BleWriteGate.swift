import Foundation

/// Purpose of a BLE characteristic write that may affect a vehicle or accessory.
///
/// SoftUnlock is **observational only** (readout / threshold evaluation). It must
/// **not** receive a `BleWritePurpose` that authorizes vehicle-affecting writes.
enum BleWritePurpose: String, Sendable {
    /// Enc2 handshake `SET_PWD` / auth pairing — required to establish a read session.
    case enc2Auth
    /// Ninebot identify / find beeps (playSound, lookingForScooter).
    case identifyFind
    /// GATT Immediate Alert (Find Me) — user-triggered locate beep.
    case capabilityAlert
    /// Documented Nordic LED characteristic — user-triggered locate blink.
    case capabilityNordicLed
    /// Any vehicle-affecting write (unlock, speed limit, flash, mode change, …).
    case vehicleManipulation
    /// Unclassified write — treated as deny.
    case unknown
}

/// Central default-deny gate for vehicle-affecting BLE writes.
///
/// Allowlist is fixed at compile time. `allowVehicleManipulation` is hardcoded
/// `false` and must never be read from `UserDefaults` or any runtime setting.
enum BleWriteGate {
    /// Hard kill-switch for vehicle manipulation. Always `false`.
    static var allowVehicleManipulation: Bool { false }

    /// Returns whether `purpose` is on the fixed allowlist.
    /// Vehicle manipulation and unknown are denied regardless of `allowVehicleManipulation`
    /// (which itself is permanently false).
    static func isAllowed(_ purpose: BleWritePurpose) -> Bool {
        switch purpose {
        case .enc2Auth, .identifyFind, .capabilityAlert, .capabilityNordicLed:
            return true
        case .vehicleManipulation, .unknown:
            return false
        }
    }

    /// Preferred call site API: returns `false` when the write must not proceed.
    static func authorize(_ purpose: BleWritePurpose) -> Bool {
        isAllowed(purpose)
    }

    /// Debug: trap on denied purposes. Release: same as `authorize`.
    @discardableResult
    static func assertAllowed(
        _ purpose: BleWritePurpose,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let ok = isAllowed(purpose)
        #if DEBUG
        if !ok {
            preconditionFailure(
                "BleWriteGate denied purpose \(purpose.rawValue)",
                file: file,
                line: line
            )
        }
        #endif
        return ok
    }
}

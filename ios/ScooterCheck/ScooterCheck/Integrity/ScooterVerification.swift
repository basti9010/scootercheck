import Foundation

/// Wann ein Gerät als technisch verifizierter Scooter gilt — nie nur nach Name/Connect.
enum ScooterVerification {
    /// Erfolgreiche Protokoll-Auslese mit aussagekräftigen Identitäts-/Board-Daten.
    static func isVerifiedScooterReading(_ reading: IntegrityReading) -> Bool {
        if let stack = reading.bleStack {
            switch stack {
            case BleStack.ninebotEnc2.rawValue, BleStack.xiaomiPlain.rawValue:
                break
            case BleStack.xiaomiEncrypted.rawValue, BleStack.unknown.rawValue, "":
                // Verschlüsselt/unbekannt allein reicht nicht — ohne Nutzdaten kein Verified.
                if reading.rawRegisters.isEmpty
                    && reading.liveBoards.isEmpty
                    && !hasIdentitySerial(reading)
                    && reading.fwMcu == nil
                    && reading.fwBle == nil
                    && reading.fwVcu == nil {
                    return false
                }
            default:
                break
            }
        }

        if hasIdentitySerial(reading) { return true }
        if !reading.rawRegisters.isEmpty { return true }
        if !reading.liveBoards.isEmpty { return true }
        if reading.fwMcu != nil || reading.fwBle != nil || reading.fwVcu != nil || reading.fwBms != nil {
            return true
        }
        return false
    }

    static func hasIdentitySerial(_ reading: IntegrityReading) -> Bool {
        let candidates = [
            reading.serialDisplay,
            reading.serialMcu,
            reading.serialBle,
            reading.serialBms,
            reading.serialVcu
        ]
        return candidates.contains { serial in
            guard let serial else { return false }
            let normalized = serial
                .uppercased()
                .filter { $0.isLetter || $0.isNumber }
            return normalized.count >= 8
        }
    }

    /// History-Eintrag darf in der Scan-Liste als „bekannter Scooter“ erscheinen.
    static func qualifiesAsKnownScooter(_ entry: ProtocolHistoryStore.Entry) -> Bool {
        if let flag = entry.wasVerifiedAsScooter {
            return flag
        }
        // Legacy ohne Flag: nur wenn eine echte SN aus einer vergangenen Auslese vorliegt.
        // Reines blePeripheralId ohne SN → nicht als bekannter Scooter (verhindert TV-Fehllinks).
        guard let sn = entry.serialDisplay else { return false }
        let normalized = sn.uppercased().filter { $0.isLetter || $0.isNumber }
        return normalized.count >= 8
    }
}

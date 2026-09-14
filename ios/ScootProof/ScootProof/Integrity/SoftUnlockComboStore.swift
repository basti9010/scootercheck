import Foundation

/// Vom Nutzer herausgefundene Soft-Unlock-Kombination (keine festen Katalog-Werte).
struct SoftUnlockCombo: Equatable, Hashable, Codable, Sendable {
    var control: SoftUnlockControl
    var repetitions: Int
    var customLabel: String?
    /// Optionale Notiz (wo/wie gefunden).
    var note: String?
    var updatedAt: Date

    init(
        control: SoftUnlockControl,
        repetitions: Int,
        customLabel: String? = nil,
        note: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.control = control
        self.repetitions = max(1, min(20, repetitions))
        self.customLabel = customLabel
        self.note = note
        self.updatedAt = updatedAt
    }

    var displayCode: String {
        if let customLabel, !customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customLabel
        }
        if control == .custom {
            let trimmed = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Individuelle Unlock-Geste" : trimmed
        }
        return "\(control.title) \(repetitions)×"
    }

    var entrySteps: String {
        """
        1) Scooter eingeschaltet lassen.
        2) Kombination „\(displayCode)“ am Fahrzeug eingeben.
        3) Auf Freigabe warten (Display/Fahrverhalten).
        4) In der App „Kombination eingegeben — erneut auslesen“ tippen.
        """
    }

    @MainActor
    static func fromSettings(_ settings: SoftUnlockSettings, note: String? = nil) -> SoftUnlockCombo {
        SoftUnlockCombo(
            control: settings.control,
            repetitions: settings.repetitions,
            customLabel: settings.control == .custom ? settings.customLabel : nil,
            note: note,
            updatedAt: Date()
        )
    }
}

/// Persistiert herausgefundene Geheimkombinationen **pro Scooter-Seriennummer**.
/// Es gibt keinen eingebauten Katalog — der Nutzer sucht die Kombination selbst;
/// erfolgreiche Treffer werden gespeichert und später wieder ausgelesen.
enum SoftUnlockComboStore {
    private static let defaultsKey = "soft_unlock_combos_by_serial_v1"

    private static func normalizeSerial(_ serial: String?) -> String? {
        guard let serial else { return nil }
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Gespeicherte Kombination für diese SN auslesen (falls vorhanden).
    static func load(forSerial serial: String?) -> SoftUnlockCombo? {
        guard let key = normalizeSerial(serial) else { return nil }
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: SoftUnlockCombo].self, from: data) else {
            return nil
        }
        return map[key]
    }

    /// Kombination für diese SN speichern (nach erfolgreicher Freischaltung / Nutzerbestätigung).
    static func save(_ combo: SoftUnlockCombo, forSerial serial: String?) {
        guard let key = normalizeSerial(serial) else { return }
        var map: [String: SoftUnlockCombo] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: SoftUnlockCombo].self, from: data) {
            map = decoded
        }
        var stored = combo
        stored.updatedAt = Date()
        map[key] = stored
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func delete(forSerial serial: String?) {
        guard let key = normalizeSerial(serial) else { return }
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var map = try? JSONDecoder().decode([String: SoftUnlockCombo].self, from: data) else {
            return
        }
        map.removeValue(forKey: key)
        if let encoded = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    /// Alle gespeicherten Kombinationen (für Übersicht / Debug).
    static func allStored() -> [String: SoftUnlockCombo] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: SoftUnlockCombo].self, from: data) else {
            return [:]
        }
        return map
    }
}

extension SoftUnlockSettings {
    /// Übernimmt eine gespeicherte / vom Nutzer gewählte Kombination in die aktiven Einstellungen.
    func apply(_ combo: SoftUnlockCombo) {
        control = combo.control
        repetitions = combo.repetitions
        if let label = combo.customLabel {
            customLabel = label
        }
        isEnabled = true
    }
}

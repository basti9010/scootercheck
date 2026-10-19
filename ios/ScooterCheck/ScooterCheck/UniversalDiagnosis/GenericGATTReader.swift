import Foundation

/// Dünne Fassade über `BLEGattDeepAnalysis` — keine zweite BLE-Verbindungsverwaltung.
///
/// Universelle Diagnose nutzt ausschließlich den bestehenden CoreBluetooth-Pfad
/// für standardisierte, lesbare Characteristics (Device Information / GAP Name).
@MainActor
enum GenericGATTReader {
    typealias Report = BLEGattDeepAnalysis.Report

    static func makeAnalyzer() -> BLEGattDeepAnalysis {
        BLEGattDeepAnalysis()
    }

    /// Nur dokumentierte sichere Characteristic-UUIDs (siehe BLEGattDeepAnalysis).
    static let safeReadableCharacteristicSuffixes = [
        "2A00", "2A01", "2A04", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29", "2A50"
    ]
}

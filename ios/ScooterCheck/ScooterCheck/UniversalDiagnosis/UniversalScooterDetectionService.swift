import Foundation

/// Mehrstufige, herstellerunabhängige Erkennung — passiv und ohne Fake-Diagnose.
@MainActor
final class UniversalScooterDetectionService: ObservableObject {
    static let shared = UniversalScooterDetectionService()

    struct PassiveAssessment: Equatable, Identifiable {
        var id: UUID { deviceId }
        var deviceId: UUID
        var manufacturer: String?
        var model: String?
        var signalLabel: String
        var possibleScooter: Bool
        var compatibility: ProtocolCompatibilityResult
        var approval: VehicleApprovalMatch?
        var stageNotes: [String]
    }

    private init() {}

    /// Stufe 1–2: Advertising + Klassifikation + Profil-Match (ohne Verbindung).
    func assessPassively(
        device: ScannedDevice,
        identity: BLEIdentificationResult? = nil
    ) -> PassiveAssessment {
        var notes: [String] = []
        notes.append("Stufe 1: Advertising (Name, Services, Manufacturer Data) ausgewertet.")

        let id = identity ?? BLEIdentificationService.shared.result(for: device.id)
        if id != nil {
            notes.append("Stufe 2: Identifikations-Engine / Herstellerhinweis berücksichtigt.")
        } else if let ext = ExtendedScooterModelHint.recognize(bleName: device.cryptoName) {
            notes.append("Stufe 2: Erweiterter Modellhinweis (\(ext.title)).")
        } else {
            notes.append("Stufe 2: Modell nicht eindeutig aus Advertising bestimmbar.")
        }

        let profiles = ScooterProtocolRegistry.shared.allProfiles
        let compat = ProtocolCompatibilityEngine.evaluate(
            device: device,
            identity: id,
            profiles: profiles
        )
        notes.append("Stufe 4 (lokal): \(compat.supportLevel.label)")

        let manufacturer = id?.manufacturer
            ?? ExtendedScooterModelHint.recognize(bleName: device.cryptoName)?.brand
            ?? compat.profile?.manufacturer
        let model = id?.model
            ?? ExtendedScooterModelHint.recognize(bleName: device.cryptoName)?.title
            ?? device.modelLabel

        let approval = VehicleApprovalCatalog.shared.match(
            displayName: device.name,
            bleName: device.cryptoName.isEmpty ? device.name : device.cryptoName,
            modelLabel: model,
            manufacturerHint: manufacturer
        )

        let possible = device.looksLikeScooter
            || (id?.radarEligibleScooter == true)
            || compat.supportLevel == .fullNative
            || ExtendedScooterModelHint.recognize(bleName: device.cryptoName) != nil

        return PassiveAssessment(
            deviceId: device.id,
            manufacturer: manufacturer,
            model: model,
            signalLabel: signalLabel(device.rssi),
            possibleScooter: possible,
            compatibility: compat,
            approval: approval,
            stageNotes: notes
        )
    }

    private func signalLabel(_ rssi: Int) -> String {
        switch rssi {
        case (-50)...0: return "Sehr stark"
        case (-65)...(-51): return "Stark"
        case (-80)...(-66): return "Mittel"
        default: return "Schwach"
        }
    }
}

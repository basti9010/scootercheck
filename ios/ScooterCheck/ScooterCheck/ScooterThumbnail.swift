import SwiftUI

/// Asset-Namen für freigestellte Scooter-Vorschaubilder (Asset Catalog).
///
/// Neue Modelle: PNG als `scooter_<slug>.imageset` ablegen und in
/// `familyAssetNames` / `labelMatchers` ergänzen.
enum ScooterThumbnailAsset {
    static let generic = "scooter_generic"
    static let zt3Pro = "scooter_zt3pro"
    static let maxG2 = "scooter_max_g2"
    static let maxG3 = "scooter_max_g3"

    /// Primäre Zuordnung Familie → Asset. Unbekannte Familien fallen auf `generic`.
    private static let familyAssetNames: [ScooterFamily: String] = [
        .zt3Pro: zt3Pro,
        .maxG2: maxG2,
        .maxG3: maxG3,
    ]

    /// Zusätzliche Texttreffer (lowercase) → Asset, falls kein Profil/Familie bekannt ist.
    private static let labelMatchers: [(needles: [String], asset: String)] = [
        (["zt3 pro", "zt3pro", "zt3"], zt3Pro),
        (["max g3", "maxg3", "max3", "max 3"], maxG3),
        (["max g2", "maxg2", "max 2"], maxG2),
    ]

    static func name(for family: ScooterFamily?) -> String {
        guard let family else { return generic }
        return familyAssetNames[family] ?? generic
    }

    static func name(for profile: ScooterProfile) -> String {
        name(for: profile.family)
    }

    /// Auflösung aus Profil, Familie und/oder freiem Modelltext (Badge/Label).
    static func name(
        profile: ScooterProfile? = nil,
        family: ScooterFamily? = nil,
        modelLabel: String? = nil,
        modelBadge: String? = nil
    ) -> String {
        if let profile {
            return name(for: profile)
        }
        if let family {
            return name(for: family)
        }
        return name(fromModelText: [modelLabel, modelBadge].compactMap { $0 }.joined(separator: " "))
    }

    static func name(fromModelText text: String?) -> String {
        let hay = (text ?? "")
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        guard !hay.isEmpty else { return generic }
        for entry in labelMatchers {
            if entry.needles.contains(where: { hay.contains($0) }) {
                return entry.asset
            }
        }
        return generic
    }
}

/// Dunkles, freigestelltes Scooter-Thumbnail für Karten (kein weißer Bildhintergrund).
struct ScooterModelThumbnail: View {
    let assetName: String
    var width: CGFloat = 76
    var height: CGFloat = 68
    var cornerRadius: CGFloat = 14

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .padding(8)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.line.opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

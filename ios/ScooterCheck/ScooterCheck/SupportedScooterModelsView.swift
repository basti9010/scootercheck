import SwiftUI

/// Liste der auslesbaren Modelle (Ninebot / Xiaomi) inkl. OEM-Firmware-Hinweis.
struct SupportedScooterModelsView: View {
    private let catalog = SupportedScooterModelsCatalog.shared

    var body: some View {
        List {
            Section {
                Text(
                    "\(SupportedScooterModelsCatalog.readableCount) von \(SupportedScooterModelsCatalog.allModels.count) Modellen sind für die schreibgeschützte Auslese vorgesehen. OEM-Firmwares liegen chronologisch unter server/firmware-analysis/stock-archive/."
                )
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .listRowBackground(Color.clear)
            }

            ForEach(catalog.brands) { brand in
                Section(brand.title) {
                    ForEach(brand.models) { model in
                        HStack(alignment: .top, spacing: Theme.Space.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.title)
                                    .font(Theme.cardTitle)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(model.hwProtocol ?? model.stack)
                                    .font(Theme.meta)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 8)
                            Text(model.readable ? "auslesbar" : "eingeschränkt")
                                .font(Theme.meta)
                                .foregroundStyle(model.readable ? Theme.accent : Theme.textMuted)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Unterstützte Modelle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

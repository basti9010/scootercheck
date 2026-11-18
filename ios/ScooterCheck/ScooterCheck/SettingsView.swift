import SwiftUI

/// Globale App-Einstellungen — erreichbar über das linke Menü.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var pairingPasswordCount = BleClient.storedPairingPasswordCount()
    @State private var showClearPairingConfirm = false
    @State private var clearPairingToast: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                        PageTitle(text: "Einstellungen")

                        displaySection
                        auslesenSection
                        findenSection
                        firmwareServerSection
                        aboutSection

                        AppCopyrightFooter()
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, Theme.Space.xxl)
                    }
                    .scootPagePadding()
                    .padding(.top, Theme.Space.sm)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                AppChromeSheetHeader { dismiss() }
            }
            .confirmationDialog(
                "Enc2-Passwörter löschen?",
                isPresented: $showClearPairingConfirm,
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    let removed = BleClient.clearAllStoredPairingPasswords()
                    pairingPasswordCount = BleClient.storedPairingPasswordCount()
                    clearPairingToast = removed == 0
                        ? "Keine Passwörter gespeichert"
                        : (removed == 1
                            ? "1 Pairing-Passwort gelöscht"
                            : "\(removed) Pairing-Passwörter gelöscht")
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Beim nächsten Auslesen dieses Geräts verlangt der Scooter wieder die Power-Taste. Nur App-Daten — kein iOS-Bluetooth-Bond.")
            }
            .overlay(alignment: .bottom) {
                if let clearPairingToast {
                    Text(clearPairingToast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                pairingPasswordCount = BleClient.storedPairingPasswordCount()
            }
            .onChange(of: clearPairingToast) { message in
                guard message != nil else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    withAnimation(.easeIn(duration: 0.2)) {
                        clearPairingToast = nil
                    }
                }
            }
        }
    }

    // MARK: - Darstellung

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            sectionLabel("Darstellung")

            Text("Schriftgröße")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)

            Text("Gilt für die gesamte App. Feature-Einstellungen (Radar, Karte) bleiben an Ort und Stelle.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Space.sm) {
                ForEach(AppTextSize.allCases) { size in
                    textSizeRow(size)
                }
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: - Auslesen

    private var auslesenSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            sectionLabel("E-Scooter auslesen")

            Text("Startwerte für die Geräteliste. Du kannst sie während der Suche weiterhin umschalten.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            settingsToggle(
                title: "Nur vermutete E-Scooter",
                subtitle: "Sonst alle BLE-Geräte in der Nähe",
                isOn: $settings.auslesenShowOnlyScooters
            )

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Sortierung")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textPrimary)
                Picker("Sortierung", selection: $settings.auslesenListSort) {
                    ForEach(BleDeviceListSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .scootSegmented()
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )

            if !settings.auslesenShowOnlyScooters {
                settingsToggle(
                    title: "Namenlose Geräte ausblenden",
                    subtitle: "Nur bei „Alle BLE-Geräte“",
                    isOn: $settings.auslesenHideNameless
                )
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Enc2-Pairing")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    pairingPasswordCount == 0
                        ? "Kein gespeichertes Passwort — nächstes Pairing braucht die Power-Taste."
                        : "\(pairingPasswordCount) gespeicherte\(pairingPasswordCount == 1 ? "s" : "") Passwort\(pairingPasswordCount == 1 ? "" : "e"). Löschen erzwingt wieder die Power-Taste."
                )
                .font(Theme.meta)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    showClearPairingConfirm = true
                } label: {
                    Text("Gespeicherte Passwörter löschen")
                        .font(Theme.secondary.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(pairingPasswordCount == 0)
                .opacity(pairingPasswordCount == 0 ? 0.45 : 1)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
        }
    }

    // MARK: - Finden

    private var findenSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            sectionLabel("E-Scooter finden")

            Text("Standard für die akustische Näherungssuche im Signal-Finder. Radar-Alarme bleiben separat.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            settingsToggle(
                title: "Suchton standardmäßig an",
                subtitle: "Kann im Finder jederzeit umgeschaltet werden",
                isOn: $settings.findProximityAudioDefault
            )

            settingsToggle(
                title: "Haptik standardmäßig an",
                subtitle: "Leichte Vibrationen bei Signaländerungen",
                isOn: $settings.findProximityHapticsDefault
            )
        }
    }

    // MARK: - Firmware-Server

    private var firmwareServerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            sectionLabel("Firmware-Analyse-Server")

            Text("ZIP/ENC: lokal prüfen, dann optional „Auf Server entschlüsseln“ (ninebottea → r2/Ghidra/… → Speeds/Combos/Stock-Diff; optional KI). Auth: Login (Bearer).")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Basis-URL")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textPrimary)
                TextField(FirmwareServerAnalysisClient.defaultBaseURLString, text: $settings.firmwareAnalysisServerURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textBody)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("API-Token")
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textPrimary)
                SecureField("X-ScooterCheck-Token", text: $settings.firmwareAnalysisAPIToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textBody)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
        }
    }

    // MARK: - Über

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            sectionLabel("Über die App")

            VStack(alignment: .leading, spacing: 4) {
                Text("ScooterCheck")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(settings.appVersionLabel)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.Control.hairline)
            )
        }
    }

    // MARK: - Rows

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.caption)
            .foregroundStyle(Theme.textMuted)
            .textCase(.uppercase)
    }

    private func textSizeRow(_ size: AppTextSize) -> some View {
        let selected = settings.textSize == size
        return Button {
            settings.textSize = size
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(size.title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(size.subtitle)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: Theme.Space.sm)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: Theme.Icon.standard, weight: .semibold))
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
            }
            .padding(.horizontal, Theme.Space.cardPadding)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.surfaceSecondary : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(
                        selected ? Theme.accent.opacity(0.55) : Theme.border,
                        lineWidth: Theme.Control.hairline
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.meta)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, Theme.Space.cardPadding)
        .padding(.vertical, 11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
        )
    }
}

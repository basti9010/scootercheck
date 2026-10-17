import AVFoundation
import CoreBluetooth
import CoreLocation
import Photos
import SwiftUI
import UIKit

/// Datenschutz-Zentrale — nur belegte Verarbeitungen aus dem App-Code.
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        PageTitle(text: "Datenschutz")
                        hero
                        atAGlanceCard
                        topicList
                        AppCopyrightFooter()
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Space.sm)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.sm)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Wordmark()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .font(Theme.buttonSecondary)
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(PrivacyContent.hubSubtitle)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(PrivacyContent.documentVersionLabel)
                .font(Theme.caption)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.sm)
    }

    private var atAGlanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PrivacyContent.atAGlanceTitle)
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("Prüfungsdaten werden lokal auf diesem Gerät gespeichert.")
                .font(Theme.buttonSecondary)
                .foregroundStyle(Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(PrivacyContent.atAGlanceBody)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scootCard()
    }

    private var topicList: some View {
        VStack(spacing: 0) {
            ForEach(Array(PrivacyContent.Topic.allCases.enumerated()), id: \.element.id) { index, topic in
                NavigationLink {
                    PrivacyTopicView(topic: topic)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: topic.symbolName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        Text(topic.title)
                            .font(Theme.cardTitle)
                            .foregroundStyle(Theme.textTitle)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < PrivacyContent.Topic.allCases.count - 1 {
                    Divider().overlay(Theme.line).padding(.leading, 56)
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Topic detail

struct PrivacyTopicView: View {
    let topic: PrivacyContent.Topic

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(PrivacyContent.sections(for: topic)) { section in
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text(section.title)
                                .font(Theme.sectionTitle)
                                .foregroundStyle(Theme.textPrimary)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textBody)
                                    .lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .scootCard()
                    }

                    if topic == .permissions {
                        PrivacyPermissionsPanel()
                    }

                    if topic == .rights {
                        privacyRequestCard
                    }

                    if topic == .externalServices, let url = URL(string: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement") {
                        Link(destination: url) {
                            Label("GitHub-Datenschutzhinweise öffnen", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }

                    Text(PrivacyContent.documentVersionLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var privacyRequestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datenschutzanfrage stellen")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("In dieser App-Version ist keine Datenschutz-E-Mail hinterlegt. Bitte nutze die Kontaktmöglichkeit des Anbieters im Apple App Store. Es wird keine Anfrage automatisch versendet.")
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let storeURL = URL(string: "https://apps.apple.com/search?term=ScooterCheck") {
                Link(destination: storeURL) {
                    Label("App-Store-Eintrag suchen", systemImage: "bag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Live permission status

private struct PrivacyPermissionsPanel: View {
    @State private var bluetoothLabel = "—"
    @State private var cameraLabel = "—"
    @State private var photosLabel = "—"
    @State private var locationLabel = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aktueller Status")
                .font(Theme.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            statusRow(title: "Bluetooth", value: bluetoothLabel)
            statusRow(title: "Kamera", value: cameraLabel)
            statusRow(title: "Fotos", value: photosLabel)
            statusRow(title: "Standort", value: locationLabel)
            statusRow(title: "Bewegung", value: "Vom System bei Nutzung von „Scooter finden“ angefragt")

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("In Einstellungen öffnen", systemImage: "gear")
                    .font(Theme.buttonSecondary)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.md)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Space.xs)
        }
        .scootCard()
        .onAppear(perform: refresh)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textTitle)
            Spacer()
            Text(value)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.trailing)
        }
    }

    private func refresh() {
        switch CBManager.authorization {
        case .allowedAlways: bluetoothLabel = "Erlaubt"
        case .denied: bluetoothLabel = "Abgelehnt"
        case .restricted: bluetoothLabel = "Eingeschränkt"
        case .notDetermined: bluetoothLabel = "Noch nicht gefragt"
        @unknown default: bluetoothLabel = "Unbekannt"
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraLabel = "Erlaubt"
        case .denied: cameraLabel = "Abgelehnt"
        case .restricted: cameraLabel = "Eingeschränkt"
        case .notDetermined: cameraLabel = "Noch nicht gefragt"
        @unknown default: cameraLabel = "Unbekannt"
        }

        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: photosLabel = "Erlaubt"
        case .denied: photosLabel = "Abgelehnt"
        case .restricted: photosLabel = "Eingeschränkt"
        case .notDetermined: photosLabel = "Noch nicht gefragt"
        @unknown default: photosLabel = "Unbekannt"
        }

        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: locationLabel = "Erlaubt"
        case .denied: locationLabel = "Abgelehnt"
        case .restricted: locationLabel = "Eingeschränkt"
        case .notDetermined: locationLabel = "Noch nicht gefragt"
        @unknown default: locationLabel = "Unbekannt"
        }
    }
}

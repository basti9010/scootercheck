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
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        atAGlanceCard
                        topicList
                        AppCopyrightFooter()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Datenschutz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(PrivacyContent.hubSubtitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(PrivacyContent.documentVersionLabel)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var atAGlanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PrivacyContent.atAGlanceTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Prüfungsdaten werden lokal auf diesem Gerät gespeichert.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(PrivacyContent.atAGlanceBody)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
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
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("In dieser App-Version ist keine Datenschutz-E-Mail hinterlegt. Bitte nutze die Kontaktmöglichkeit des Anbieters im Apple App Store. Es wird keine Anfrage automatisch versendet.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
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
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .onAppear(perform: refresh)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
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

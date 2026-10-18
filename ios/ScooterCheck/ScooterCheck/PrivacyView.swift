import AVFoundation
import CoreBluetooth
import CoreLocation
import Photos
import SwiftUI
import UIKit

/// Datenschutz — gleiche Sheet-Optik und Accordion-Liste wie FAQ & Wissensbasis.
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    /// Nur ein Thema gleichzeitig geöffnet (wie FAQ-Hauptkategorien).
    @State private var expandedTopicID: String? = "overview"

    private let overviewID = "overview"

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PageTitle(text: "Datenschutz")
                            .padding(.bottom, Theme.Space.md)

                        Text(PrivacyContent.documentVersionLabel)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                            .padding(.bottom, Theme.Space.xxl)

                        VStack(alignment: .leading, spacing: 0) {
                            overviewSection
                            topicDivider

                            ForEach(Array(PrivacyContent.Topic.allCases.enumerated()), id: \.element.id) { index, topic in
                                topicSection(topic)
                                if index < PrivacyContent.Topic.allCases.count - 1 {
                                    topicDivider
                                }
                            }
                        }

                        AppCopyrightFooter()
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Space.xxl)
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
            .preferredColorScheme(.dark)
        }
    }

    private var topicDivider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: Theme.Control.hairline)
            .padding(.leading, Theme.Icon.nav + Theme.Space.md)
    }

    private var overviewSection: some View {
        let isOpen = expandedTopicID == overviewID
        return VStack(alignment: .leading, spacing: 0) {
            topicHeader(
                title: PrivacyContent.atAGlanceTitle,
                symbolName: "lock.shield",
                isOpen: isOpen
            ) {
                toggleTopic(overviewID)
            }

            PrivacyExpandablePanel(isExpanded: isOpen) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Prüfungsdaten werden lokal auf diesem Gerät gespeichert.")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(PrivacyContent.atAGlanceBody)
                        .font(.system(size: 14.5, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, Theme.Space.lg)
                .padding(.bottom, Theme.Space.md)
                .padding(.trailing, Theme.Space.sm)
            }
        }
    }

    @ViewBuilder
    private func topicSection(_ topic: PrivacyContent.Topic) -> some View {
        let isOpen = expandedTopicID == topic.id
        VStack(alignment: .leading, spacing: 0) {
            topicHeader(
                title: topic.title,
                symbolName: topic.symbolName,
                isOpen: isOpen
            ) {
                toggleTopic(topic.id)
            }

            PrivacyExpandablePanel(isExpanded: isOpen) {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    ForEach(PrivacyContent.sections(for: topic)) { section in
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Text(section.title)
                                .font(.system(size: 15.5, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.system(size: 14.5, weight: .regular))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if topic == .permissions {
                        PrivacyPermissionsPanel()
                    }

                    if topic == .rights {
                        privacyRequestBlock
                    }

                    if topic == .externalServices,
                       let url = URL(string: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement") {
                        Link(destination: url) {
                            HStack(spacing: Theme.Space.sm) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: Theme.Icon.compact, weight: .medium))
                                Text("GitHub-Datenschutzhinweise öffnen")
                                    .font(.system(size: 14.5, weight: .medium))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .padding(.leading, Theme.Space.lg)
                .padding(.bottom, Theme.Space.md)
                .padding(.trailing, Theme.Space.sm)
            }
        }
        .id(topic.id)
    }

    private func topicHeader(
        title: String,
        symbolName: String,
        isOpen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: symbolName)
                    .font(.system(size: Theme.Icon.standard, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: Theme.Icon.nav, alignment: .center)

                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Theme.Space.sm)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Thema zuklappen" : "Thema aufklappen")
    }

    private func toggleTopic(_ id: String) {
        withAnimation(.easeInOut(duration: 0.26)) {
            if expandedTopicID == id {
                expandedTopicID = nil
            } else {
                expandedTopicID = id
            }
        }
    }

    private var privacyRequestBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Datenschutzanfrage stellen")
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("In dieser App-Version ist keine Datenschutz-E-Mail hinterlegt. Bitte nutze die Kontaktmöglichkeit des Anbieters im Apple App Store. Es wird keine Anfrage automatisch versendet.")
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let storeURL = URL(string: "https://apps.apple.com/search?term=ScooterCheck") {
                Link(destination: storeURL) {
                    Text("App-Store-Eintrag suchen")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

// MARK: - Local height accordion (wie FAQ)

private struct PrivacyExpandablePanel<Content: View>: View {
    let isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: isExpanded ? nil : 0, alignment: .top)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
    }
}

// MARK: - Live permission status

private struct PrivacyPermissionsPanel: View {
    @State private var bluetoothLabel = "—"
    @State private var cameraLabel = "—"
    @State private var photosLabel = "—"
    @State private var locationLabel = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Aktueller Status")
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            statusRow(title: "Bluetooth", value: bluetoothLabel)
            statusRow(title: "Kamera", value: cameraLabel)
            statusRow(title: "Fotos", value: photosLabel)
            statusRow(title: "Standort", value: locationLabel)
            statusRow(title: "Bewegung", value: "Vom System bei Nutzung von „E-Scooter finden“ angefragt")

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("In Einstellungen öffnen")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Space.xs)
        }
        .onAppear(perform: refresh)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Space.sm)
            Text(value)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
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

import SwiftUI

/// Native FAQ- & Wissensbasis-Seite (Dark Mode, Accordion, Suche).
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expandedIDs: Set<String> = []

    private var categories: [FAQCategory] {
        FAQCatalog.filtered(query: query)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        searchField
                        introCallouts

                        if categories.isEmpty {
                            emptySearch
                        } else {
                            ForEach(categories) { category in
                                categorySection(category)
                            }
                        }

                        AppCopyrightFooter()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("FAQ & Wissensbasis")
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.muted)
            TextField("Suche (z. B. Soft Unlock, Region…)", text: $query)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private var introCallouts: some View {
        VStack(spacing: 10) {
            FAQCalloutBanner(
                text: "ScooterCheck bewertet die aktuell technisch auslesbaren Daten. Ein unauffälliges Ergebnis ist kein Beweis dafür, dass ein Fahrzeug zu keinem früheren Zeitpunkt verändert wurde."
            )
            FAQCalloutBanner(
                text: "Technische Auffälligkeiten können auch durch Reparaturen, Ersatzteile, Softwareupdates oder Modellvarianten entstehen und sollten immer im Gesamtzusammenhang betrachtet werden."
            )
        }
    }

    private var emptySearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keine Treffer")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Versuche andere Stichworte wie Tuning, Firmware, Register, Soft Unlock oder Power Cycle.")
                .font(.subheadline)
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

    private func categorySection(_ category: FAQCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: category.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(category.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            VStack(spacing: 8) {
                ForEach(category.items) { item in
                    FAQAccordionRow(
                        item: item,
                        isExpanded: expandedIDs.contains(item.id)
                    ) {
                        toggle(item.id)
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }
}

// MARK: - Rows

private struct FAQAccordionRow: View {
    let item: FAQItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    Text(item.question)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 4)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Zuklappen" : "Aufklappen")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(item.segments.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segmentView(_ segment: FAQSegment) -> some View {
        switch segment {
        case .paragraph(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(Theme.accent)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .callout(let text):
            FAQCalloutBanner(text: text)
        }
    }
}

private struct FAQCalloutBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

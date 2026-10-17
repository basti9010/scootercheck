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
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        PageTitle(text: "FAQ & Wissensbasis")
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
                            .padding(.top, Theme.Space.sm)
                            .padding(.bottom, 28)
                    }
                    .padding(.horizontal, Theme.Space.xl)
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textMuted)
            TextField("Suche (z. B. Soft Unlock, Region…)", text: $query)
                .font(Theme.fieldValue)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Theme.Space.md)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
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
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Keine Treffer")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textTitle)
            Text("Versuche andere Stichworte wie Tuning, Firmware, Register, Soft Unlock oder Power Cycle.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scootCard()
    }

    private func categorySection(_ category: FAQCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: category.title, systemImage: category.symbolName)
                .padding(.top, Theme.Space.xs)

            VStack(spacing: Theme.Space.sm) {
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
        withAnimation(Theme.Motion.standard) {
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
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Text(item.question)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textTitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.sm)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, Theme.Space.xs)
                }
                .padding(Theme.Space.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Zuklappen" : "Aufklappen")

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(Array(item.segments.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment)
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segmentView(_ segment: FAQSegment) -> some View {
        switch segment {
        case .paragraph(let text):
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Text("•")
                            .foregroundStyle(Theme.accent)
                        Text(line)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textBody)
                            .lineSpacing(4)
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
                .font(Theme.body)
                .foregroundStyle(Theme.textBody)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

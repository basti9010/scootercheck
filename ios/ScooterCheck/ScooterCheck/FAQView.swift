import SwiftUI

/// Native FAQ- & Wissensbasis-Seite (Dark Mode, Themen-Chips, Accordion).
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expandedIDs: Set<String> = []
    /// Welche Themenblöcke aufgeklappt sind (bei Suche: alle Treffer-Themen).
    @State private var expandedCategories: Set<String> = ["verstehen"]
    @State private var focusCategoryID: String?

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categories: [FAQCategory] {
        FAQCatalog.filtered(query: query)
    }

    private var chipCategories: [FAQCategory] {
        isSearching ? categories : FAQCatalog.categories
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.lg) {
                            PageTitle(text: "FAQ & Wissensbasis")
                            Text("Themen wählen oder suchen — Antworten klappen sich bei Bedarf auf.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            searchField
                            categoryChips(proxy: proxy)

                            if !isSearching {
                                introCallouts
                            }

                            if categories.isEmpty {
                                emptySearch
                            } else {
                                ForEach(categories) { category in
                                    categorySection(category)
                                        .id(category.id)
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
                    .onChange(of: focusCategoryID) { id in
                        guard let id else { return }
                        withAnimation(Theme.Motion.standard) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .onChange(of: query) { _ in
                        if isSearching {
                            expandedCategories = Set(categories.map(\.id))
                        }
                    }
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
            TextField("Suche (z. B. Signal-Finder, Soft Unlock…)", text: $query)
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

    private func categoryChips(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chipCategories) { category in
                    let selected = focusCategoryID == category.id
                        || (focusCategoryID == nil && expandedCategories.contains(category.id))
                    Button {
                        query = ""
                        withAnimation(Theme.Motion.standard) {
                            // Ein Thema fokussieren: andere zuklappen für Übersicht
                            expandedCategories = [category.id]
                            focusCategoryID = category.id
                            proxy.scrollTo(category.id, anchor: .top)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.symbolName)
                                .font(.caption.weight(.semibold))
                            Text(category.title)
                                .font(Theme.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? Theme.ink : Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.accent : Theme.card)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selected ? Color.clear : Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.title)
                }
            }
            .padding(.vertical, 2)
        }
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
            Text("Versuche Stichworte wie Signal-Finder, Geräte-Wächter, Soft Unlock, Firmware oder Register.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .scootCard()
    }

    private func categorySection(_ category: FAQCategory) -> some View {
        let isOpen = isSearching || expandedCategories.contains(category.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Theme.Motion.standard) {
                    if expandedCategories.contains(category.id) {
                        expandedCategories.remove(category.id)
                    } else {
                        expandedCategories.insert(category.id)
                    }
                    focusCategoryID = category.id
                }
            } label: {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: category.symbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(Theme.sectionTitle)
                            .foregroundStyle(Theme.textTitle)
                        Text("\(category.items.count) Themen")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textMuted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(Theme.Space.lg)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Themen zuklappen" : "Themen aufklappen")

            if isOpen {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, Theme.Space.xs)
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

import SwiftUI

/// Native FAQ- & Wissensbasis-Seite (Dark Mode, ruhige Accordion-Hierarchie).
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expandedIDs: Set<String> = []
    /// Geöffnete Hauptkategorie (nur eine gleichzeitig — außer bei aktiver Suche).
    @State private var expandedCategoryID: String? = "verstehen"

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categories: [FAQCategory] {
        FAQCatalog.filtered(query: query)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        VStack(alignment: .leading, spacing: 6) {
                            PageTitle(text: "FAQ & Wissensbasis")
                            Text("Themen aufklappen oder suchen — Antworten erscheinen darunter.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        searchField

                        if categories.isEmpty {
                            emptySearch
                        } else {
                            VStack(alignment: .leading, spacing: Theme.Space.md) {
                                ForEach(categories) { category in
                                    categoryBlock(category)
                                        .id(category.id)
                                }
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
            .onChange(of: query) { _ in
                if isSearching {
                    expandedIDs = []
                } else if expandedCategoryID == nil {
                    expandedCategoryID = "verstehen"
                }
            }
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

    @ViewBuilder
    private func categoryBlock(_ category: FAQCategory) -> some View {
        let isOpen = isSearching || expandedCategoryID == category.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    if expandedCategoryID == category.id {
                        expandedCategoryID = nil
                    } else {
                        expandedCategoryID = category.id
                        expandedIDs = []
                    }
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
            .disabled(isSearching)

            // Inhalt bleibt im lokalen Block; Höhe clippt nach oben — kein slide-from-top.
            FAQExpandablePanel(isExpanded: isOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(category.items) { item in
                        FAQAccordionRow(
                            item: item,
                            isExpanded: expandedIDs.contains(item.id)
                        ) {
                            toggleQuestion(item.id)
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 10)
            }
        }
    }

    private func toggleQuestion(_ id: String) {
        withAnimation(.easeInOut(duration: 0.26)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }
}

// MARK: - Local height accordion (kein move-from-top)

/// Klappt Inhalt lokal unter dem Header auf; clippt von oben nach unten (kein slide-from-top).
private struct FAQExpandablePanel<Content: View>: View {
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

// MARK: - Question rows

private struct FAQAccordionRow: View {
    let item: FAQItem
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Text(item.question)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textTitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.sm)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 2)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Zuklappen" : "Aufklappen")

            FAQExpandablePanel(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(Array(item.segments.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment)
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
            }
        }
        .background(Theme.card.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(Theme.border.opacity(0.9), lineWidth: 1)
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

import SwiftUI

/// FAQ & Wissensbasis — schlanke iOS-Listenoptik (keine Themen-Kartenstapel).
struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expandedIDs: Set<String> = []
    /// Nur eine Hauptkategorie gleichzeitig (außer bei Suche: alle Treffer-Gruppen offen).
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
                    VStack(alignment: .leading, spacing: 0) {
                        PageTitle(text: "FAQ & Wissensbasis")
                            .padding(.bottom, Theme.Space.md)

                        searchField
                            .padding(.bottom, Theme.Space.xxl)

                        if categories.isEmpty {
                            emptySearch
                                .padding(.bottom, Theme.Space.xxl)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                    categorySection(category)
                                    if index < categories.count - 1 {
                                        categoryDivider
                                    }
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
            .onChange(of: query) { _ in
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isSearching {
                        expandedIDs = []
                    } else if expandedCategoryID == nil {
                        expandedCategoryID = "verstehen"
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.Icon.standard, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            TextField("FAQ durchsuchen …", text: $query)
                .font(Theme.fieldValue)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.Icon.standard))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(Theme.border, lineWidth: Theme.Control.hairline)
        )
    }

    private var emptySearch: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Keine Treffer")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("Versuche andere Stichworte — die Suche prüft Fragen und Antworten.")
                .font(Theme.secondary)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Space.md)
    }

    private var categoryDivider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: Theme.Control.hairline)
            .padding(.leading, Theme.Icon.nav + Theme.Space.md)
    }

    @ViewBuilder
    private func categorySection(_ category: FAQCategory) -> some View {
        let isOpen = isSearching || expandedCategoryID == category.id

        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !isSearching else { return }
                withAnimation(.easeInOut(duration: 0.26)) {
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
                        .font(.system(size: Theme.Icon.standard, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.Icon.nav, alignment: .center)

                    Text(category.title)
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
            .accessibilityHint(isOpen ? "Kategorie zuklappen" : "Kategorie aufklappen")
            .disabled(isSearching)

            FAQExpandablePanel(isExpanded: isOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                        FAQQuestionRow(
                            item: item,
                            isExpanded: expandedIDs.contains(item.id),
                            showDivider: index < category.items.count - 1
                        ) {
                            toggleQuestion(item.id)
                        }
                    }
                }
                .padding(.leading, Theme.Space.lg)
                .padding(.bottom, Theme.Space.sm)
            }
        }
        .id(category.id)
    }

    private func toggleQuestion(_ id: String) {
        withAnimation(.easeInOut(duration: 0.24)) {
            if expandedIDs.contains(id) {
                expandedIDs.remove(id)
            } else {
                expandedIDs.insert(id)
            }
        }
    }
}

// MARK: - Local height accordion

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

// MARK: - Question / answer rows

private struct FAQQuestionRow: View {
    let item: FAQItem
    let isExpanded: Bool
    let showDivider: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Text(item.question)
                        .font(.system(size: 15.5, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.sm)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 3)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Antwort zuklappen" : "Antwort aufklappen")

            FAQExpandablePanel(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(Array(item.segments.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment)
                    }
                }
                .padding(.bottom, Theme.Space.md)
                .padding(.trailing, Theme.Space.sm)
            }

            if showDivider {
                Rectangle()
                    .fill(Theme.line.opacity(0.85))
                    .frame(height: Theme.Control.hairline)
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: FAQSegment) -> some View {
        switch segment {
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Text("•")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Theme.accent)
                        Text(line)
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .callout(let text):
            FAQInlineCallout(text: text)
        }
    }
}

private struct FAQInlineCallout: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: Theme.Icon.compact, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

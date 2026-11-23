import SwiftUI

/// Aktiv | Archiv shelf for the Prüfungen overview.
enum ProtocolHistoryShelf: Equatable {
    case active
    case archive
}

/// Prüfungen overview: list, multi-select, swipe actions, share/archive/delete.
struct ProtocolHistoryOverviewView: View {
    @ObservedObject var history: ProtocolHistoryStore
    @Binding var shelf: ProtocolHistoryShelf
    @Binding var selecting: Bool
    @Binding var selectedIds: Set<UUID>
    var onNewCheck: () -> Void
    var onOpen: (ProtocolHistoryStore.Entry) -> Void

    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var pendingDeleteIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var toast: String?

    private var visibleEntries: [ProtocolHistoryStore.Entry] {
        shelf == .archive ? history.archivedEntries : history.activeEntries
    }

    private var shelfTitle: String {
        switch shelf {
        case .active:
            return history.activeCount == 0 ? "Prüfungen" : "Prüfungen (\(history.activeCount))"
        case .archive:
            return history.archivedCount == 0 ? "Archiv" : "Archiv (\(history.archivedCount))"
        }
    }

    var body: some View {
        listContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting, !selectedIds.isEmpty {
                    selectionActionBar
                        .padding(.horizontal, Theme.Space.page)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showShare, onDismiss: { shareItems = [] }) {
                ActivityShare(
                    items: shareItems,
                    subject: shareItems.count > 3
                        ? "ScooterCheck Prüfberichte"
                        : "ScooterCheck Prüfbericht"
                )
            }
            .confirmationDialog(
                pendingDeleteIds.count <= 1 ? "Prüfung löschen?" : "Prüfungen löschen?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    confirmDelete()
                }
                Button("Abbrechen", role: .cancel) {
                    pendingDeleteIds = []
                }
            } message: {
                if pendingDeleteIds.count <= 1 {
                    Text("Diese Prüfung wird dauerhaft gelöscht.")
                } else {
                    Text("Die \(pendingDeleteIds.count) ausgewählten Prüfungen werden dauerhaft gelöscht.")
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
    }

    private var listContent: some View {
        List {
            overviewHeader
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)

            if visibleEntries.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(visibleEntries) { entry in
                    Group {
                        if selecting {
                            controlRow(entry)
                        } else {
                            controlRow(entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    swipeActions(for: entry)
                                }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .listRowSeparator(.hidden)
                }
            }

            AppCopyrightFooter()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 28, trailing: 20))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .background(Theme.bg)
        .animation(.easeInOut(duration: 0.22), value: shelf)
        .animation(.easeInOut(duration: 0.22), value: selecting)
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                PageTitle(text: shelfTitle)
                Spacer(minLength: Theme.Space.sm)
                if !selecting {
                    Button {
                        onNewCheck()
                    } label: {
                        Text("Neue Prüfung")
                            .font(Theme.buttonSecondary)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neue Prüfung")
                }
                Button {
                    toggleSelecting()
                } label: {
                    Text(selecting ? "Fertig" : "Auswählen")
                        .font(Theme.buttonSecondary)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(visibleEntries.isEmpty && !selecting)
                .opacity(visibleEntries.isEmpty && !selecting ? 0.35 : 1)
            }

            Picker("Bereich", selection: $shelf) {
                Text("Aktiv (\(history.activeCount))").tag(ProtocolHistoryShelf.active)
                Text("Archiv (\(history.archivedCount))").tag(ProtocolHistoryShelf.archive)
            }
            .scootSegmented()
            .onChange(of: shelf) { _ in
                selectedIds = []
                selecting = false
            }

            if selecting {
                HStack {
                    Text(
                        selectedIds.isEmpty
                            ? "Keine ausgewählt"
                            : "\(selectedIds.count) ausgewählt"
                    )
                    .font(Theme.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if !visibleEntries.isEmpty {
                        Button(
                            selectedIds.count == visibleEntries.count
                                ? "Auswahl aufheben"
                                : "Alle auswählen"
                        ) {
                            if selectedIds.count == visibleEntries.count {
                                selectedIds = []
                            } else {
                                selectedIds = Set(visibleEntries.map(\.id))
                            }
                        }
                        .font(Theme.buttonSecondary)
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.sm)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Image(systemName: shelf == .archive ? "archivebox" : "tray")
                .font(.system(size: Theme.Icon.function, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(shelf == .archive ? "Archiv ist leer" : "Noch keine Prüfungen")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(
                shelf == .archive
                    ? "Archivierte Prüfungen erscheinen hier und können jederzeit wiederhergestellt werden."
                    : "Gespeicherte Prüfberichte erscheinen hier offline auf diesem Gerät."
            )
            .font(Theme.caption)
            .foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .scootCard()
    }

    @ViewBuilder
    private func swipeActions(for entry: ProtocolHistoryStore.Entry) -> some View {
        // Trailing swipeActions: first declared sits at the trailing edge (rechts).
        // Gewünschte Sicht links→rechts: Öffnen · Teilen · Archiv/Restore · Löschen
        Button(role: .destructive) {
            requestDelete(ids: Set([entry.id]))
        } label: {
            Label("Löschen", systemImage: "trash")
        }

        if shelf == .archive {
            Button {
                restore(ids: Set([entry.id]))
            } label: {
                Label("Wiederherstellen", systemImage: "arrow.uturn.backward")
            }
            .tint(Theme.accent)
        } else {
            Button {
                archive(ids: Set([entry.id]))
            } label: {
                Label("Archivieren", systemImage: "archivebox")
            }
            .tint(Color.white.opacity(0.55))
        }

        Button {
            share(ids: Set([entry.id]))
        } label: {
            Label("Teilen", systemImage: "square.and.arrow.up")
        }
        .tint(.gray)

        Button {
            open(entry)
        } label: {
            Label("Öffnen", systemImage: "doc.text.magnifyingglass")
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func controlRow(_ entry: ProtocolHistoryStore.Entry) -> some View {
        let selected = selectedIds.contains(entry.id)
        Button {
            if selecting {
                toggleSelection(entry.id)
            } else {
                open(entry)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                        .padding(.top, 24)
                        .accessibilityHidden(true)
                }

                CheckCoverThumbnail(entry: entry, size: 64)

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(alignment: .top, spacing: Theme.Space.sm) {
                        Text(entry.protocolNumber)
                            .font(Theme.cardTitle)
                            .foregroundStyle(Theme.textTitle)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        if let verdict = entry.verdict {
                            VerdictBadge(verdict: verdict)
                        }
                    }
                    Text("\(entry.profile.family.title) · \(Int(entry.profile.ratedMaxKmh)) km/h")
                        .font(Theme.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if let serial = entry.serialDisplay, !serial.isEmpty {
                        Text(serial)
                            .font(Theme.caption.monospaced())
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                    if let subject = entry.subjectSummary ?? entry.knownLabel, !subject.isEmpty {
                        Text(subject)
                            .font(Theme.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected && selecting ? Theme.accent.opacity(0.10) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(
                        selected && selecting ? Theme.accent.opacity(0.55) : Theme.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.protocolNumber)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectionActionBar: some View {
        // Links→rechts: Öffnen (nur Einzelwahl) · Teilen · Archiv/Restore · Löschen
        HStack(spacing: 0) {
            if selectedIds.count == 1,
               let id = selectedIds.first,
               let entry = visibleEntries.first(where: { $0.id == id }) {
                actionButton(
                    title: "Öffnen",
                    systemImage: "doc.text.magnifyingglass",
                    tint: Theme.accent,
                    enabled: true
                ) {
                    open(entry)
                }
            }
            actionButton(
                title: "Teilen",
                systemImage: "square.and.arrow.up",
                tint: Theme.accent,
                enabled: !selectedIds.isEmpty
            ) {
                share(ids: selectedIds)
            }
            if shelf == .archive {
                actionButton(
                    title: "Wiederherstellen",
                    systemImage: "arrow.uturn.backward",
                    tint: Theme.accent,
                    enabled: !selectedIds.isEmpty
                ) {
                    restore(ids: selectedIds)
                }
            } else {
                actionButton(
                    title: "Archivieren",
                    systemImage: "archivebox",
                    tint: Theme.accent,
                    enabled: !selectedIds.isEmpty
                ) {
                    archive(ids: selectedIds)
                }
            }
            actionButton(
                title: "Löschen",
                systemImage: "trash",
                tint: Theme.danger,
                enabled: !selectedIds.isEmpty
            ) {
                requestDelete(ids: selectedIds)
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(enabled ? tint : Theme.muted.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toggleSelecting() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selecting.toggle()
            if !selecting {
                selectedIds = []
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func open(_ entry: ProtocolHistoryStore.Entry) {
        selecting = false
        selectedIds = []
        onOpen(entry)
    }

    private func share(ids: Set<UUID>) {
        let items = history.shareItems(for: ids)
        guard !items.isEmpty else { return }
        shareItems = items
        showShare = true
    }

    private func archive(ids: Set<UUID>) {
        let count = history.archive(ids: ids)
        guard count > 0 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedIds.subtract(ids)
            if selectedIds.isEmpty { selecting = false }
        }
        presentToast(
            count == 1 ? "Prüfung archiviert" : "\(count) Prüfungen archiviert"
        )
    }

    private func restore(ids: Set<UUID>) {
        let count = history.restore(ids: ids)
        guard count > 0 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedIds.subtract(ids)
            if selectedIds.isEmpty { selecting = false }
        }
        presentToast(
            count == 1 ? "Prüfung wiederhergestellt" : "\(count) Prüfungen wiederhergestellt"
        )
    }

    private func requestDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIds = ids
        showDeleteConfirm = true
    }

    private func confirmDelete() {
        let ids = pendingDeleteIds
        pendingDeleteIds = []
        guard !ids.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            history.delete(ids: ids)
            selectedIds.subtract(ids)
            if selectedIds.isEmpty { selecting = false }
        }
    }

    private func presentToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            toast = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeIn(duration: 0.2)) {
                if toast == message {
                    toast = nil
                }
            }
        }
    }
}

import PhotosUI
import SwiftUI
import UIKit

// MARK: - List cover thumbnail

/// Vorschaubild in der Prüfungsübersicht (ca. 64 pt, abgerundet).
struct CheckCoverThumbnail: View {
    let entry: ProtocolHistoryStore.Entry
    var size: CGFloat = 64
    @ObservedObject private var history = ProtocolHistoryStore.shared

    private var liveEntry: ProtocolHistoryStore.Entry {
        history.entries.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        Group {
            if let image = history.coverThumbnail(for: liveEntry) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.card
                    Image(systemName: "camera.fill")
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .accessibilityLabel(liveEntry.coverPhotoId == nil ? "Kein Titelbild" : "Titelbild")
        .id(liveEntry.coverPhotoId)
    }
}

// MARK: - Gallery section (detail / result)

struct CheckPhotosSection: View {
    let entryId: UUID
    @ObservedObject private var history = ProtocolHistoryStore.shared

    @State private var showAddMenu = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var viewerItem: PhotoViewerItem?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var pendingDeleteId: UUID?
    @State private var showDeleteConfirm = false

    private var entry: ProtocolHistoryStore.Entry? {
        history.entries.first { $0.id == entryId }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bilder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showAddMenu = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            Text("Fotos helfen, individualisierte Scooter in der Übersicht wiederzuerkennen. Das Titelbild erscheint in der Prüfliste.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let entry, !entry.photoIds.isEmpty {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(entry.photoIds, id: \.self) { photoId in
                        photoCell(entry: entry, photoId: photoId)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noch keine Bilder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Kamera oder Fotomediathek — erstes Bild wird Titelbild.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
            }
        }
        .padding(.top, 4)
        .confirmationDialog("Bild hinzufügen", isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("Foto aufnehmen") { showCamera = true }
            Button("Aus Fotomediathek wählen") { showLibrary = true }
            Button("Abbrechen", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { images in
                _ = history.addPhotos(to: entryId, images: images)
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showLibrary,
            selection: $libraryItems,
            maxSelectionCount: 12,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: libraryItems) { items in
            guard !items.isEmpty else { return }
            Task { await importLibraryItems(items) }
        }
        .fullScreenCover(item: $viewerItem) { item in
            if let entry {
                CheckPhotoViewer(
                    entry: entry,
                    photoId: item.id,
                    onClose: { viewerItem = nil },
                    onSetCover: {
                        history.setCoverPhoto(entryId: entryId, photoId: item.id)
                    },
                    onShare: {
                        sharePhoto(entry: entry, photoId: item.id)
                    },
                    onDelete: {
                        pendingDeleteId = item.id
                        showDeleteConfirm = true
                    }
                )
            }
        }
        .confirmationDialog(
            "Bild löschen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let id = pendingDeleteId {
                    history.deletePhoto(entryId: entryId, photoId: id)
                    if viewerItem?.id == id { viewerItem = nil }
                }
                pendingDeleteId = nil
            }
            Button("Abbrechen", role: .cancel) {
                pendingDeleteId = nil
            }
        } message: {
            Text("Dieses Bild wird dauerhaft von der Prüfung entfernt.")
        }
        .sheet(isPresented: $showShare, onDismiss: { shareItems = [] }) {
            ActivityShare(items: shareItems, subject: "ScooterCheck Foto")
        }
    }

    @ViewBuilder
    private func photoCell(entry: ProtocolHistoryStore.Entry, photoId: UUID) -> some View {
        let isCover = entry.coverPhotoId == photoId
        Button {
            viewerItem = PhotoViewerItem(id: photoId)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = history.thumbnailImage(for: entry, photoId: photoId) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.card
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCover ? Theme.accent.opacity(0.8) : Theme.line, lineWidth: isCover ? 1.5 : 1)
                )

                if isCover {
                    Label("Titelbild", systemImage: "star.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(5)
                        .background(Theme.accent)
                        .clipShape(Circle())
                        .padding(6)
                        .accessibilityLabel("Titelbild")
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                history.setCoverPhoto(entryId: entryId, photoId: photoId)
            } label: {
                Label(
                    isCover ? "Ist Titelbild" : "Als Titelbild festlegen",
                    systemImage: isCover ? "star.fill" : "star"
                )
            }
            .disabled(isCover)

            Button {
                sharePhoto(entry: entry, photoId: photoId)
            } label: {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                pendingDeleteId = photoId
                showDeleteConfirm = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func sharePhoto(entry: ProtocolHistoryStore.Entry, photoId: UUID) {
        guard let url = history.originalPhotoFileURL(for: entry, photoId: photoId) else { return }
        shareItems = [
            NamedShareFile(
                url: url,
                title: "ScooterCheck \(entry.protocolNumber) Foto.jpg",
                utType: "public.jpeg"
            )
        ]
        showShare = true
    }

    private func importLibraryItems(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run {
            _ = history.addPhotos(to: entryId, images: images)
            libraryItems = []
        }
    }
}

// MARK: - Full-screen viewer

private struct CheckPhotoViewer: View {
    let entry: ProtocolHistoryStore.Entry
    let photoId: UUID
    let onClose: () -> Void
    let onSetCover: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var history = ProtocolHistoryStore.shared

    private var isCover: Bool {
        let live = history.entries.first { $0.id == entry.id } ?? entry
        return live.coverPhotoId == photoId
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = ProtocolHistoryStore.shared.originalImage(for: entry, photoId: photoId) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig", action: onClose)
                        .foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .principal) {
                    if isCover {
                        Label("Titelbild", systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        onSetCover()
                    } label: {
                        Label(
                            isCover ? "Titelbild" : "Als Titelbild festlegen",
                            systemImage: isCover ? "star.fill" : "star"
                        )
                    }
                    .disabled(isCover)
                    .foregroundStyle(Theme.accent)

                    Spacer()

                    Button(action: onShare) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
                    .foregroundStyle(Theme.danger)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
        }
    }
}

private struct PhotoViewerItem: Identifiable {
    let id: UUID
}

// MARK: - Camera picker

struct CameraPicker: UIViewControllerRepresentable {
    var onImages: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImages([image])
            }
            parent.dismiss()
        }
    }
}

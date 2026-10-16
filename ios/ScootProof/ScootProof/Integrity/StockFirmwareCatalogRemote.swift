import Foundation

/// Optionale Online-Erweiterung des Serienkatalogs.
/// Offline-Kern bleibt in `StockFirmwareCatalog`; Remote-Versionen werden nur **hinzugefügt**.
enum StockFirmwareCatalogRemote {
    /// Öffentliche JSON-Liste im Repo (raw). Fail → App bleibt bei Bundled/Cache.
    static let defaultURL = URL(string:
        "https://raw.githubusercontent.com/basti9010/scootercheck/main/catalogs/stock-firmware.json"
    )!

    struct ModuleVersions: Codable, Sendable, Equatable {
        var mcu: [String]
        var vcu: [String]
        var ble: [String]
        var bms: [String]

        func asEntry() -> StockFirmwareCatalog.Entry {
            StockFirmwareCatalog.Entry(
                mcu: Set(mcu),
                vcu: Set(vcu),
                ble: Set(ble),
                bms: Set(bms)
            )
        }
    }

    struct Payload: Codable, Sendable, Equatable {
        var schemaVersion: Int
        var updatedAt: String
        var sourceNote: String?
        var families: [String: ModuleVersions]
    }

    struct Snapshot: Sendable, Equatable {
        var payload: Payload
        var fetchedAt: Date
        var sourceURL: String
    }

    private static let cacheName = "stock-firmware-catalog-cache.json"
    private static let fetchedAtKey = "stockFirmwareCatalog.fetchedAt"
    private static let sourceURLKey = "stockFirmwareCatalog.sourceURL"

    private static let lock = NSLock()
    private static var memory: Snapshot?

    /// Aktueller Remote-/Cache-Stand (nil = nur Bundled).
    static var current: Snapshot? {
        lock.lock(); defer { lock.unlock() }
        if let memory { return memory }
        if let disk = loadFromDisk() {
            memory = disk
            return disk
        }
        return nil
    }

    /// Kurzlabel für Protokoll / UI.
    static var provenanceLabel: String {
        guard let snap = current else { return "Bundled" }
        return "Online \(snap.payload.updatedAt) (Stand Abruf \(Format.shortDate(snap.fetchedAt)))"
    }

    /// Einstieg beim App-Start — Netzwerkfehler werden still ignoriert.
    static func refreshInBackground(url: URL = defaultURL) {
        Task.detached(priority: .utility) {
            _ = await refresh(url: url)
        }
    }

    @discardableResult
    static func refresh(url: URL = defaultURL) async -> Bool {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.schemaVersion >= 1, !payload.families.isEmpty else { return false }
            let snap = Snapshot(payload: payload, fetchedAt: Date(), sourceURL: url.absoluteString)
            saveToDisk(snap)
            lock.lock(); memory = snap; lock.unlock()
            return true
        } catch {
            return false
        }
    }

    /// Für Tests: Snapshot setzen ohne Netzwerk.
    static func installForTesting(_ snapshot: Snapshot?) {
        lock.lock(); memory = snapshot; lock.unlock()
    }

    // MARK: - Disk

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(cacheName)
    }

    private static func saveToDisk(_ snap: Snapshot) {
        do {
            let data = try JSONEncoder().encode(snap.payload)
            try data.write(to: cacheURL, options: .atomic)
            UserDefaults.standard.set(snap.fetchedAt.timeIntervalSince1970, forKey: fetchedAtKey)
            UserDefaults.standard.set(snap.sourceURL, forKey: sourceURLKey)
        } catch {
            // Cache optional
        }
    }

    private static func loadFromDisk() -> Snapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        let fetched = Date(
            timeIntervalSince1970: UserDefaults.standard.double(forKey: fetchedAtKey)
        )
        let url = UserDefaults.standard.string(forKey: sourceURLKey) ?? defaultURL.absoluteString
        return Snapshot(payload: payload, fetchedAt: fetched, sourceURL: url)
    }
}

private enum Format {
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

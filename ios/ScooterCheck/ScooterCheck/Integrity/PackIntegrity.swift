import CryptoKit
import Foundation

/// SHA-256 integrity manifest for a protocol history pack directory.
struct PackIntegrityManifest: Codable, Equatable, Sendable {
    struct FileEntry: Codable, Equatable, Sendable {
        let relativePath: String
        let sha256: String
        let byteCount: Int
    }

    let protocolNumber: String
    let createdAt: Date
    let appVersion: String?
    let sealed: Bool
    let files: [FileEntry]
    let manifestAlgorithm: String

    static let algorithmSHA256 = "SHA-256"
    static let fileName = "integrity-manifest.json"
}

enum PackIntegrity {
    struct VerifyResult: Equatable, Sendable {
        let ok: Bool
        let mismatches: [String]
        let missing: [String]
    }

    enum IntegrityError: Error, LocalizedError {
        case manifestMissing
        case manifestDecodeFailed
        case directoryMissing

        var errorDescription: String? {
            switch self {
            case .manifestMissing:
                return "integrity-manifest.json fehlt"
            case .manifestDecodeFailed:
                return "integrity-manifest.json konnte nicht gelesen werden"
            case .directoryMissing:
                return "Pack-Verzeichnis fehlt"
            }
        }
    }

    /// Lowercase hex SHA-256 of `data`.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Builds a manifest by hashing canonical pack artifacts that currently exist.
    /// Skips `integrity-manifest.json` so sealing is not recursive.
    static func buildManifest(
        directory: URL,
        fileManager: FileManager = .default,
        protocolNumber: String,
        sealed: Bool,
        createdAt: Date = Date(),
        appVersion: String? = ProtocolPDF.appVersion
    ) throws -> PackIntegrityManifest {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw IntegrityError.directoryMissing
        }

        let relativePaths = try collectArtifactRelativePaths(
            directory: directory,
            protocolNumber: protocolNumber,
            fileManager: fileManager
        )

        var entries: [PackIntegrityManifest.FileEntry] = []
        entries.reserveCapacity(relativePaths.count)
        for relative in relativePaths {
            let url = directory.appendingPathComponent(relative)
            let data = try Data(contentsOf: url)
            entries.append(
                PackIntegrityManifest.FileEntry(
                    relativePath: relative,
                    sha256: sha256Hex(of: data),
                    byteCount: data.count
                )
            )
        }

        return PackIntegrityManifest(
            protocolNumber: protocolNumber,
            createdAt: createdAt,
            appVersion: appVersion,
            sealed: sealed,
            files: entries,
            manifestAlgorithm: PackIntegrityManifest.algorithmSHA256
        )
    }

    /// Writes `integrity-manifest.json` atomically with sorted keys.
    static func writeManifest(_ manifest: PackIntegrityManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let url = directory.appendingPathComponent(PackIntegrityManifest.fileName)
        try data.write(to: url, options: .atomic)
    }

    /// Verifies on-disk artifacts against `integrity-manifest.json`.
    static func verify(
        directory: URL,
        fileManager: FileManager = .default
    ) throws -> VerifyResult {
        let manifestURL = directory.appendingPathComponent(PackIntegrityManifest.fileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw IntegrityError.manifestMissing
        }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(PackIntegrityManifest.self, from: data) else {
            throw IntegrityError.manifestDecodeFailed
        }

        var mismatches: [String] = []
        var missing: [String] = []

        for entry in manifest.files {
            let url = directory.appendingPathComponent(entry.relativePath)
            guard fileManager.fileExists(atPath: url.path) else {
                missing.append(entry.relativePath)
                continue
            }
            let disk = try Data(contentsOf: url)
            let hash = sha256Hex(of: disk)
            if hash != entry.sha256 || disk.count != entry.byteCount {
                mismatches.append(entry.relativePath)
            }
        }

        return VerifyResult(
            ok: mismatches.isEmpty && missing.isEmpty,
            mismatches: mismatches.sorted(),
            missing: missing.sorted()
        )
    }

    // MARK: - Artifact discovery

    /// Relative paths of pack artifacts to hash, sorted lexicographically.
    static func collectArtifactRelativePaths(
        directory: URL,
        protocolNumber: String,
        fileManager: FileManager
    ) throws -> [String] {
        var paths = Set<String>()

        let rootItems = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for url in rootItems {
            let name = url.lastPathComponent
            if name == PackIntegrityManifest.fileName { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            if isRootArtifact(name: name, protocolNumber: protocolNumber) {
                paths.insert(name)
            }
        }

        let photosDir = directory.appendingPathComponent("photos", isDirectory: true)
        if fileManager.fileExists(atPath: photosDir.path) {
            let photoItems = try fileManager.contentsOfDirectory(
                at: photosDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for url in photoItems {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                    continue
                }
                paths.insert("photos/\(url.lastPathComponent)")
            }
        }

        return paths.sorted()
    }

    /// `session.json`, share/canonical PDF+JSON names, and short-form protocol files.
    private static func isRootArtifact(name: String, protocolNumber: String) -> Bool {
        if name == "session.json" { return true }
        if name.hasSuffix("_Bericht.pdf") { return true }
        if name.hasSuffix("_Daten.json") { return true }
        if name.hasSuffix("_Rohdaten.pdf") { return true }
        if name.hasSuffix("_raw.pdf") { return true }
        // Canonical short names written by ProtocolPack.makePack
        if name == "\(protocolNumber).pdf" { return true }
        if name == "\(protocolNumber).json" { return true }
        return false
    }
}

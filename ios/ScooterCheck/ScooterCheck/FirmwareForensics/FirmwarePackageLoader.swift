import Foundation

struct FirmwareLoadedPackage: Equatable, Sendable {
    var containerKind: FirmwareContainerKind
    var archiveDigest: FirmwareFileDigest
    var archiveByteCount: Int
    var files: [(path: String, data: Data)]
    var meta: FirmwarePackageMeta
    var loadWarnings: [String]
}

enum FirmwarePackageLoader {
    static func load(fileName: String, data: Data) -> FirmwareLoadedPackage {
        let archiveDigest = FirmwareDigest.make(from: data)
        let lower = fileName.lowercased()

        if lower.hasSuffix(".zip") || looksLikeZip(data) {
            return loadZip(fileName: fileName, data: data, archiveDigest: archiveDigest)
        }
        if lower.hasSuffix(".json") {
            return bare(
                kind: .json,
                path: fileName,
                data: data,
                archiveDigest: archiveDigest,
                roleHint: .infoJson
            )
        }
        if lower.hasSuffix(".txt") {
            return bare(
                kind: .text,
                path: fileName,
                data: data,
                archiveDigest: archiveDigest,
                roleHint: .paramsText
            )
        }
        if lower.hasSuffix(".bin.enc") || lower.hasSuffix(".enc") {
            return bare(
                kind: .bareEncryptedBinary,
                path: fileName,
                data: data,
                archiveDigest: archiveDigest,
                roleHint: .firmEncrypted
            )
        }
        if lower.hasSuffix(".bin") {
            return bare(
                kind: .bareBinary,
                path: fileName,
                data: data,
                archiveDigest: archiveDigest,
                roleHint: .firmPlain
            )
        }
        // Unknown — try ZIP then treat as binary
        if looksLikeZip(data) {
            return loadZip(fileName: fileName, data: data, archiveDigest: archiveDigest)
        }
        return bare(
            kind: .unknown,
            path: fileName,
            data: data,
            archiveDigest: archiveDigest,
            roleHint: .other
        )
    }

    private static func bare(
        kind: FirmwareContainerKind,
        path: String,
        data: Data,
        archiveDigest: FirmwareFileDigest,
        roleHint: FirmwarePayloadRole
    ) -> FirmwareLoadedPackage {
        var meta = FirmwarePackageMeta(
            schemaVersion: nil,
            displayName: nil,
            models: [],
            type: nil,
            compatible: [],
            declaredMd5: nil,
            declaredEncrypted: kind == .bareEncryptedBinary ? true : nil,
            rawInfoJSON: nil
        )
        if roleHint == .infoJson, let text = String(data: data, encoding: .utf8) {
            meta = parseInfoJSON(data) ?? meta
            meta.rawInfoJSON = text
        }
        return FirmwareLoadedPackage(
            containerKind: kind,
            archiveDigest: archiveDigest,
            archiveByteCount: data.count,
            files: [(path, data)],
            meta: meta,
            loadWarnings: []
        )
    }

    private static func loadZip(fileName: String, data: Data, archiveDigest: FirmwareFileDigest) -> FirmwareLoadedPackage {
        var warnings: [String] = []
        let entries: [MinimalZipReader.Entry]
        do {
            entries = try MinimalZipReader.entries(from: data)
        } catch {
            return FirmwareLoadedPackage(
                containerKind: .unknown,
                archiveDigest: archiveDigest,
                archiveByteCount: data.count,
                files: [],
                meta: .empty,
                loadWarnings: [error.localizedDescription]
            )
        }
        let files = entries.map { ($0.name, $0.data) }
        var meta = FirmwarePackageMeta.empty
        if let info = entries.first(where: { baseName($0.name).lowercased() == "info.json" }) {
            meta = parseInfoJSON(info.data) ?? meta
            meta.rawInfoJSON = String(data: info.data, encoding: .utf8)
            if meta.schemaVersion == nil && meta.displayName == nil && meta.models.isEmpty {
                warnings.append("info.json vorhanden, aber nicht als ZIPv3-Metadaten lesbar.")
            }
        } else {
            warnings.append("Kein info.json im Archiv.")
        }
        let kind: FirmwareContainerKind = (meta.schemaVersion != nil || !meta.models.isEmpty || meta.type != nil)
            ? .zipV3
            : .zipGeneric
        return FirmwareLoadedPackage(
            containerKind: kind,
            archiveDigest: archiveDigest,
            archiveByteCount: data.count,
            files: files,
            meta: meta,
            loadWarnings: warnings
        )
    }

    static func role(for path: String, meta: FirmwarePackageMeta) -> FirmwarePayloadRole {
        let base = baseName(path).lowercased()
        if base == "info.json" { return .infoJson }
        if base == "params.txt" || base == "changelog.txt" || base == "readme.txt" { return .paramsText }
        if base.hasSuffix(".bin.enc") || base.hasSuffix(".enc") { return .firmEncrypted }
        if base == "firm.bin" || base.hasSuffix(".bin") {
            if meta.declaredEncrypted == true { return .firmEncrypted }
            return .firmPlain
        }
        return .other
    }

    static func baseName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    static func parseInfoJSON(_ data: Data) -> FirmwarePackageMeta? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let fw = (obj["firmware"] as? [String: Any]) ?? obj
        let encrypted: Bool? = {
            if let b = fw["encrypted"] as? Bool { return b }
            if let s = fw["encrypted"] as? String {
                let l = s.lowercased()
                if l == "true" || l == "encrypted" || l == "yes" { return true }
                if l == "false" || l == "no" { return false }
            }
            if let s = fw["encryption"] as? String {
                let l = s.lowercased()
                if l.contains("encrypt") || l == "tea" || l == "xtea" { return true }
                if l == "none" || l == "plain" { return false }
            }
            return nil
        }()
        return FirmwarePackageMeta(
            schemaVersion: obj["schemaVersion"] as? Int,
            displayName: fw["displayName"] as? String,
            models: (fw["models"] as? [String]) ?? [],
            type: fw["type"] as? String,
            compatible: (fw["compatible"] as? [String]) ?? [],
            declaredMd5: (fw["md5"] as? String)?.lowercased(),
            declaredEncrypted: encrypted,
            rawInfoJSON: String(data: data, encoding: .utf8)
        )
    }

    private static func looksLikeZip(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B && (data[2] == 0x03 || data[2] == 0x05 || data[2] == 0x07)
    }
}

private extension FirmwarePackageMeta {
    static let empty = FirmwarePackageMeta(
        schemaVersion: nil,
        displayName: nil,
        models: [],
        type: nil,
        compatible: [],
        declaredMd5: nil,
        declaredEncrypted: nil,
        rawInfoJSON: nil
    )
}

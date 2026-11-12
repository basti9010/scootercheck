import Foundation

enum FirmwareCryptoAssessor {
    /// Offline decryption is intentionally unavailable: ScooterCheck has no lawful key material for SH TEA/XTEA packages.
    static let decryptionUnavailableNote = """
    Offline-Entschlüsselung ist in ScooterCheck nicht verfügbar: Es liegt kein rechtmäßig \
    nutzbares Schlüsselmaterial für ScooterHacking-/Hersteller-Transferverschlüsselung vor. \
    Funktionsanalyse des Klartext-Images ist daher nicht möglich.
    """

    static func assess(
        package: FirmwareLoadedPackage,
        primaryPath: String?,
        primaryData: Data?,
        primaryRole: FirmwarePayloadRole?
    ) -> FirmwareCryptoAssessment {
        var evidence: [String] = []
        let base = primaryPath.map { FirmwarePackageLoader.baseName($0).lowercased() } ?? ""

        if package.meta.declaredEncrypted == true {
            evidence.append("info.json / Metadaten: encrypted=true bzw. encryption gesetzt")
            return FirmwareCryptoAssessment(
                status: .confirmedByMetadata,
                detectedFormat: package.containerKind == .zipV3
                    ? "ScooterHacking ZIPv3 (encrypted payload)"
                    : "Paket mit Verschlüsselungsflag",
                decryptionAvailable: false,
                decryptionNote: decryptionUnavailableNote,
                evidence: evidence
            )
        }

        if primaryRole == .firmEncrypted || base.hasSuffix(".bin.enc") || base.hasSuffix(".enc") {
            evidence.append("Dateiname: \(base) (.enc)")
            if let d = primaryData {
                evidence.append(String(format: "Entropie FIRM: %.2f bit/Byte", d.isEmpty ? 0 : FirmwareDigest.shannonEntropy(d)))
            }
            return FirmwareCryptoAssessment(
                status: .confirmedByMetadata,
                detectedFormat: package.containerKind == .zipV3
                    ? "ScooterHacking ZIPv3 / .bin.enc"
                    : "Encrypted binary (.enc)",
                decryptionAvailable: false,
                decryptionNote: decryptionUnavailableNote,
                evidence: evidence
            )
        }

        guard let data = primaryData, !data.isEmpty else {
            return FirmwareCryptoAssessment(
                status: .unknownFormat,
                detectedFormat: "Keine Firmware-Payload erkannt",
                decryptionAvailable: false,
                decryptionNote: decryptionUnavailableNote,
                evidence: ["Keine primäre Firmwaredatei"]
            )
        }

        let entropy = FirmwareDigest.shannonEntropy(data)
        evidence.append(String(format: "Shannon-Entropie: %.2f bit/Byte (n=%d)", entropy, data.count))

        // Magic / signature checks for plaintext firmware-ish images
        if looksLikeArmVectorTable(data) {
            evidence.append("ARM-Vektor-/Adressmuster am Dateianfang")
            return FirmwareCryptoAssessment(
                status: .plaintext,
                detectedFormat: package.containerKind == .zipV3 ? "ScooterHacking ZIPv3 (plain FIRM.bin)" : "Plain binary",
                decryptionAvailable: false,
                decryptionNote: "Keine Entschlüsselung nötig (Klartextindikatoren).",
                evidence: evidence
            )
        }

        if entropy >= 7.5 && data.count >= 256 {
            evidence.append("Hohe Entropie ohne Klartext-Header → Verschlüsselung/Kompression wahrscheinlich")
            return FirmwareCryptoAssessment(
                status: .likelyByStructure,
                detectedFormat: "Hochentropisches Image ohne erkannte Signatur",
                decryptionAvailable: false,
                decryptionNote: decryptionUnavailableNote,
                evidence: evidence
            )
        }

        if entropy < 6.5 {
            evidence.append("Moderate/niedrige Entropie — eher Klartext oder strukturierte Daten")
            return FirmwareCryptoAssessment(
                status: .plaintext,
                detectedFormat: package.containerKind == .zipV3 ? "ScooterHacking ZIPv3 (vermutlich plain)" : "Vermutlich Klartext",
                decryptionAvailable: false,
                decryptionNote: "Keine Entschlüsselung nötig (strukturelle Klartextindikatoren).",
                evidence: evidence
            )
        }

        return FirmwareCryptoAssessment(
            status: .unknownFormat,
            detectedFormat: "Nicht eindeutig klassifizierbar",
            decryptionAvailable: false,
            decryptionNote: decryptionUnavailableNote,
            evidence: evidence
        )
    }

    /// Cortex-M vector tables often start with SP in SRAM (0x2000_0000+) and Thumb reset in flash (0x0800_0000+ or 0x0000_xxxx odd).
    static func looksLikeArmVectorTable(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let sp = u32le(data, 0)
        let reset = u32le(data, 4)
        let spOk = (sp >= 0x2000_0000 && sp <= 0x2008_0000) || (sp >= 0x1000_0000 && sp <= 0x1008_0000)
        let resetThumb = (reset & 1) == 1
        let resetFlash = (reset & ~UInt32(1)) < 0x0020_0000 || ((reset & ~UInt32(1)) >= 0x0800_0000 && (reset & ~UInt32(1)) < 0x0820_0000)
        return spOk && resetThumb && resetFlash
    }

    private static func u32le(_ data: Data, _ o: Int) -> UInt32 {
        UInt32(data[o])
            | (UInt32(data[o + 1]) << 8)
            | (UInt32(data[o + 2]) << 16)
            | (UInt32(data[o + 3]) << 24)
    }
}

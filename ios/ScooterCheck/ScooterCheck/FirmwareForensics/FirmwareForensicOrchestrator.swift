import Foundation

enum FirmwareForensicOrchestrator {
    static func analyze(
        fileName: String,
        data: Data,
        references: [FirmwareReferenceRecord] = [],
        preferredReferenceId: String? = nil,
        vehicleContext: FirmwareVehicleContext? = nil
    ) -> FirmwareForensicReport {
        let loaded = FirmwarePackageLoader.load(fileName: fileName, data: data)
        var evidence: [FirmwareEvidenceItem] = []
        var limits: [String] = [
            "Rein lesende Dateianalyse — keine Übertragung an ein Fahrzeug.",
            "Importierte Dateien sind nicht automatisch die installierte Fahrzeugfirmware.",
            "Einzelne Strings/Zahlen sind kein Funktionsnachweis am Fahrzeug."
        ]
        limits.append(contentsOf: loaded.loadWarnings)

        // Inventory
        var entries: [FirmwarePackageEntry] = []
        var primaryPath: String?
        var primaryData: Data?
        var primaryRole: FirmwarePayloadRole?
        var paramsText: String?

        for (path, bytes) in loaded.files {
            let role = FirmwarePackageLoader.role(for: path, meta: loaded.meta)
            let digest = FirmwareDigest.make(from: bytes)
            var notes: [String] = []
            var status = "erfasst"

            if role == .infoJson {
                status = "Metadaten ausgewertet"
            } else if role == .paramsText {
                status = "Text ausgewertet"
                paramsText = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
            } else if role == .firmEncrypted {
                status = "als verschlüsselt markiert — Inhalt nicht analysierbar"
                notes.append("Klartextanalyse nicht verfügbar")
                if primaryPath == nil {
                    primaryPath = path
                    primaryData = bytes
                    primaryRole = role
                }
            } else if role == .firmPlain {
                status = "als Klartext-Kandidat erfasst"
                if primaryPath == nil || primaryRole == .other {
                    primaryPath = path
                    primaryData = bytes
                    primaryRole = role
                }
            }

            // Prefer FIRM.bin / FIRM.bin.enc over other bins
            let base = FirmwarePackageLoader.baseName(path).lowercased()
            if base == "firm.bin" || base == "firm.bin.enc" {
                primaryPath = path
                primaryData = bytes
                primaryRole = role
            }

            entries.append(.init(
                path: path,
                role: role,
                digest: digest,
                analysisStatus: status,
                notes: notes
            ))
        }

        // Package meta evidence
        if !loaded.meta.models.isEmpty || loaded.meta.type != nil {
            evidence.append(.init(
                id: "pkg-meta",
                category: .package,
                title: "Paketmetadaten",
                detail: [
                    loaded.meta.displayName.map { "Name: \($0)" },
                    loaded.meta.type.map { "Steuergerät: \($0)" },
                    loaded.meta.models.isEmpty ? nil : "Modelle: \(loaded.meta.models.joined(separator: ", "))",
                    loaded.meta.compatible.isEmpty ? nil : "Boards: \(loaded.meta.compatible.joined(separator: ", "))"
                ].compactMap { $0 }.joined(separator: " · "),
                evidence: "info.json",
                method: "JSON-Metadatenparser",
                verifiability: .confirmed,
                confirmed: true
            ))
        }

        // MD5 verify against primary plaintext/cipher payload
        if let declared = loaded.meta.declaredMd5, let primaryData {
            let md5 = FirmwareDigest.md5Hex(primaryData)
            let ok = md5 == declared
            evidence.append(.init(
                id: "pkg-md5",
                category: .package,
                title: ok ? "MD5 stimmt mit info.json überein" : "MD5 weicht von info.json ab",
                detail: "deklariert=\(declared) berechnet=\(md5)",
                evidence: primaryPath ?? "payload",
                method: "MD5-Vergleich",
                verifiability: .confirmed,
                confirmed: true
            ))
            if !ok {
                limits.append("Deklarierte MD5 stimmt nicht mit der Payload überein.")
            }
        }

        let crypto = FirmwareCryptoAssessor.assess(
            package: loaded,
            primaryPath: primaryPath,
            primaryData: primaryData,
            primaryRole: primaryRole
        )
        evidence.append(.init(
            id: "crypto-status",
            category: .crypto,
            title: crypto.status.label,
            detail: crypto.detectedFormat,
            evidence: crypto.evidence.joined(separator: " | "),
            method: "Crypto-Assessment",
            verifiability: crypto.status == .confirmedByMetadata || crypto.status == .plaintext ? .confirmed : .indicative,
            confirmed: crypto.status == .confirmedByMetadata || crypto.status == .plaintext
        ))
        if !crypto.decryptionAvailable {
            limits.append(crypto.decryptionNote)
        }

        let (binary, binEvidence) = FirmwareBinaryStaticAnalyzer.analyze(
            path: primaryPath,
            data: primaryData,
            crypto: crypto,
            meta: loaded.meta,
            paramsText: paramsText
        )
        evidence.append(contentsOf: binEvidence)

        let encrypted = crypto.status == .confirmedByMetadata || crypto.status == .likelyByStructure
        let subjectSHA = primaryData.map { FirmwareDigest.sha256Hex($0) } ?? loaded.archiveDigest.sha256
        let comparison = FirmwareComparer.compare(
            subjectSHA256: subjectSHA,
            subjectData: encrypted ? nil : primaryData,
            encrypted: encrypted,
            references: references,
            preferredId: preferredReferenceId
        )
        evidence.append(.init(
            id: "cmp",
            category: .comparison,
            title: comparison.outcome.label,
            detail: comparison.note,
            evidence: comparison.referenceLabel ?? "keine Referenz",
            method: "Referenzvergleich (SHA-256 / Bytes)",
            verifiability: comparison.outcome == .identical || comparison.outcome == .different ? .confirmed : .indicative,
            confirmed: comparison.outcome == .identical || comparison.outcome == .different
        ))

        var vehicleNotes: [String] = []
        if let ctx = vehicleContext {
            vehicleNotes.append("Fahrzeugkontext nur zur Zuordnung — Datei ≠ installierte Firmware.")
            if let m = ctx.modelLabel { vehicleNotes.append("Auslese-Modell: \(m)") }
            if let v = ctx.fwVcu { vehicleNotes.append("VCU-FW aus Auslese: \(v)") }
            if let v = ctx.fwMcu { vehicleNotes.append("MCU-FW aus Auslese: \(v)") }
            if let v = ctx.fwBle { vehicleNotes.append("BLE-FW aus Auslese: \(v)") }
            if let model = loaded.meta.models.first, let label = ctx.modelLabel?.lowercased(),
               !label.contains(model.lowercased()) && !model.lowercased().contains(label.prefix(3)) {
                evidence.append(.init(
                    id: "veh-model-mismatch",
                    category: .vehicleLink,
                    title: "Modellhinweis weicht möglicherweise ab",
                    detail: "Paket-Modell \(loaded.meta.models.joined(separator: "/")) vs. Auslese \(ctx.modelLabel ?? "—")",
                    evidence: "Vergleich info.json.models ↔ ScooterProfile/Auslese",
                    method: "Heuristischer Abgleich",
                    verifiability: .indicative,
                    confirmed: false
                ))
            }
            evidence.append(.init(
                id: "veh-link",
                category: .vehicleLink,
                title: "Zuordnung zum Prüfkontext",
                detail: vehicleNotes.joined(separator: " · "),
                evidence: ctx.protocolNumber ?? ctx.serial ?? "Session",
                method: "UI-Kontext (kein Installationsnachweis)",
                verifiability: .unverified,
                confirmed: false
            ))
        }

        let (verdict, rationale) = FirmwareForensicScorer.score(
            crypto: crypto,
            comparison: comparison,
            evidence: evidence,
            hasPrimaryPayload: primaryData != nil || !loaded.files.isEmpty
        )

        let summary = buildSummary(
            fileName: fileName,
            meta: loaded.meta,
            crypto: crypto,
            verdict: verdict,
            comparison: comparison
        )

        return FirmwareForensicReport(
            id: UUID().uuidString,
            analyzedAt: Date(),
            originalFileName: fileName,
            containerKind: loaded.containerKind,
            archiveByteCount: loaded.archiveByteCount,
            archiveDigest: loaded.archiveDigest,
            meta: loaded.meta,
            entries: entries.sorted { $0.path < $1.path },
            primaryFirmwarePath: primaryPath,
            crypto: crypto,
            binary: binary,
            evidence: evidence,
            comparison: comparison,
            verdict: verdict,
            verdictRationale: rationale,
            limits: limits,
            vehicleContext: vehicleContext,
            vehicleLinkNotes: vehicleNotes,
            summary: summary
        )
    }

    private static func buildSummary(
        fileName: String,
        meta: FirmwarePackageMeta,
        crypto: FirmwareCryptoAssessment,
        verdict: FirmwareForensicVerdict,
        comparison: FirmwareComparisonResult?
    ) -> String {
        var parts: [String] = [verdict.shortLabel]
        if let t = meta.type { parts.append(t) }
        if !meta.models.isEmpty { parts.append(meta.models.joined(separator: "/")) }
        parts.append(crypto.status == .plaintext ? "Klartext" : "verschlüsselt/unlesbar")
        if let c = comparison { parts.append(c.outcome.label) }
        parts.append(fileName)
        return parts.joined(separator: " · ")
    }
}

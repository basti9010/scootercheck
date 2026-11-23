import Foundation

/// Minimal local forensics pipeline for Cycle-8 Hub flow.
/// Uses PackageLoader + CryptoAssessor + BinaryStaticAnalyzer + Scorer
/// (no full Orchestrator / ReferenceStore / CFW catalog dependency).
enum FirmwareLocalAnalysisPipeline {
    struct Outcome: Equatable, Sendable {
        var report: FirmwareForensicReport
        var primaryData: Data?
        var primaryPath: String?
        var primaryRole: FirmwarePayloadRole?
        /// UI status after crypto gate (local-only — no server yet).
        var uiStatus: FirmwareAnalysisJobUIStatus
    }

    static func analyze(
        fileName: String,
        data: Data,
        vehicleContext: FirmwareVehicleContext? = nil
    ) -> Outcome {
        let loaded = FirmwarePackageLoader.load(fileName: fileName, data: data)
        var evidence: [FirmwareEvidenceItem] = []
        var limits: [String] = [
            "Rein lesende Dateianalyse — keine Übertragung an ein Fahrzeug.",
            "Importierte Dateien sind nicht automatisch die installierte Fahrzeugfirmware.",
            "Einzelne Strings/Zahlen sind kein Funktionsnachweis am Fahrzeug."
        ]
        limits.append(contentsOf: loaded.loadWarnings)

        var entries: [FirmwarePackageEntry] = []
        var primaryPath: String?
        var primaryData: Data?
        var primaryRole: FirmwarePayloadRole?
        var paramsText: String?

        for file in loaded.files {
            let path = file.path
            let bytes = file.data
            let role = FirmwarePackageLoader.role(for: path, meta: loaded.meta)
            let digest = FirmwareDigest.make(from: bytes)
            var notes: [String] = []
            var status = "erfasst"

            if role == .infoJson {
                status = "Metadaten ausgewertet"
            } else if role == .paramsText {
                status = "Text ausgewertet"
                paramsText = String(data: bytes, encoding: .utf8)
                    ?? String(data: bytes, encoding: .isoLatin1)
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

        // Integrity: MD5 vs info.json + always expose SHA-256 / MD5 of primary payload.
        if let primaryData {
            let sha = FirmwareDigest.sha256Hex(primaryData)
            let md5 = FirmwareDigest.md5Hex(primaryData)
            evidence.append(.init(
                id: "pkg-sha256",
                category: .package,
                title: "SHA-256 (Payload)",
                detail: sha,
                evidence: primaryPath ?? "payload",
                method: "SHA-256",
                verifiability: .confirmed,
                confirmed: true
            ))
            evidence.append(.init(
                id: "pkg-md5-computed",
                category: .package,
                title: "MD5 (Payload)",
                detail: md5,
                evidence: primaryPath ?? "payload",
                method: "MD5",
                verifiability: .confirmed,
                confirmed: true
            ))
            if let declared = loaded.meta.declaredMd5 {
                let ok = md5.lowercased() == declared.lowercased()
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
        } else {
            evidence.append(.init(
                id: "pkg-sha256-archive",
                category: .package,
                title: "SHA-256 (Archiv)",
                detail: loaded.archiveDigest.sha256,
                evidence: fileName,
                method: "SHA-256",
                verifiability: .confirmed,
                confirmed: true
            ))
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
            verifiability: crypto.status == .confirmedByMetadata || crypto.status == .plaintext
                ? .confirmed : .indicative,
            confirmed: crypto.status == .confirmedByMetadata || crypto.status == .plaintext
        ))
        if !crypto.decryptionAvailable {
            limits.append(crypto.decryptionNote)
        }

        let (binary, binEvidence) = FirmwareBinaryStaticAnalyzer.analyze(
            path: primaryPath,
            archiveFileName: fileName,
            data: primaryData,
            crypto: crypto,
            meta: loaded.meta,
            paramsText: paramsText
        )
        evidence.append(contentsOf: binEvidence)

        var vehicleNotes: [String] = []
        if let ctx = vehicleContext {
            vehicleNotes.append("Fahrzeugkontext nur zur Zuordnung — Datei ≠ installierte Firmware.")
            if let m = ctx.modelLabel { vehicleNotes.append("Auslese-Modell: \(m)") }
            if let v = ctx.fwVcu { vehicleNotes.append("VCU-FW aus Auslese: \(v)") }
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

        let comparison = FirmwareComparisonResult(
            outcome: .notPossible,
            referenceId: nil,
            referenceLabel: nil,
            differingBytes: nil,
            firstDiffOffset: nil,
            segments: [],
            note: "Kein Referenzvergleich in der Cycle-8 Minimal-Pipeline."
        )

        let (verdict, rationale) = FirmwareForensicScorer.score(
            crypto: crypto,
            comparison: comparison,
            evidence: evidence,
            hasPrimaryPayload: primaryData != nil || !loaded.files.isEmpty
        )

        let subjectSHA = primaryData.map { FirmwareDigest.sha256Hex($0) } ?? loaded.archiveDigest.sha256
        let encrypted = crypto.status == .confirmedByMetadata
            || crypto.status == .likelyByStructure

        let deep = FirmwareDeepAnalysisResult(
            schemaVersion: FirmwareDeepAnalysisResult.currentSchemaVersion,
            producedAt: Date(),
            sources: [.localDeterministic],
            subjectSHA256: subjectSHA,
            packageDisplayName: loaded.meta.displayName,
            models: loaded.meta.models,
            controllerType: loaded.meta.type,
            speedLimits: [],
            modeTransitions: [],
            inputHints: [],
            comboSummaries: [],
            notes: encrypted
                ? ["Lokal: verschlüsselte Payload — keine Decompile-/Limit-Extraktion."]
                : ["Lokal: PackageLoader + Crypto + BinaryStaticAnalyzer."],
            caveats: FirmwareDeepAnalysisResult.standardCaveats,
            quality: .init(
                hasDeterministicBasis: true,
                llmSchemaValidated: false,
                summary: encrypted
                    ? "Lokal unvollständig (Ciphertext)"
                    : "Lokale Deterministik"
            ),
            analysisLimitations: limits,
            analysisCompleteness: encrypted
                ? "INCOMPLETE_ENCRYPTED_LOCAL"
                : (crypto.status == .unknownFormat ? "FORMAT_UNSUPPORTED_LOCAL" : "LOCAL_STATIC")
        )

        var summaryParts: [String] = [verdict.shortLabel]
        if let t = loaded.meta.type { summaryParts.append(t) }
        if !loaded.meta.models.isEmpty { summaryParts.append(loaded.meta.models.joined(separator: "/")) }
        summaryParts.append(crypto.status == .plaintext ? "Klartext" : "verschlüsselt/unlesbar")
        summaryParts.append(fileName)

        let report = FirmwareForensicReport(
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
            summary: summaryParts.joined(separator: " · "),
            deepAnalysis: deep,
            serverArtifacts: nil
        )

        let uiStatus = FirmwareAnalysisJobUIStatusMapper.resolve(
            job: nil,
            crypto: crypto,
            localOnlyFallback: .completed
        )

        return Outcome(
            report: report,
            primaryData: primaryData,
            primaryPath: primaryPath,
            primaryRole: primaryRole,
            uiStatus: uiStatus
        )
    }

    /// Merge server deep-analysis into a local report; re-apply crypto gate metadata.
    static func mergingServerResult(
        into local: FirmwareForensicReport,
        job: FirmwareAnalysisJobStatus
    ) -> FirmwareForensicReport {
        var report = local
        if let result = job.result {
            report.deepAnalysis = result
        }
        report.serverArtifacts = FirmwareServerArtifacts(
            jobId: job.jobId,
            plaintextSaved: job.plaintextSaved,
            plaintextSHA256: job.plaintextSHA256,
            plaintextByteCount: nil,
            decompileSaved: job.decompileSaved,
            decompileExcerpt: nil
        )
        if job.state == .completed,
           job.plaintextSaved != true,
           (job.result == nil || (job.result?.sources.contains(where: {
               switch $0 {
               case .serverDecompile, .serverR2, .serverCapstone, .serverYara,
                    .serverEmulation, .serverAngr, .serverIvt, .serverLLM:
                   return true
               default: return false
               }
           }) != true)) {
            // Server "completed" without plaintext/deep sources — keep local limits honest.
            report.limits.append(
                "Server meldete Fertig ohne Klartext-/Decompile-Artefakt — kein erfolgreiches Decompile."
            )
        }
        return report
    }
}

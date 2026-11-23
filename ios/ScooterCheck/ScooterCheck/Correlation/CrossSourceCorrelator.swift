import Foundation

/// Reiner Adapter: korreliert BLE-/Dump-/ZIP-Snapshots ohne ZIP-Reparse oder Evidence-Lauf.
enum CrossSourceCorrelator {

    static func assess(_ snapshot: CrossSourceSnapshot) -> CrossSourceAssessment {
        var items: [CorrelationItem] = []
        var caveats: [String] = [CrossSourceSnapshot.zipNotInstalledCaveat]
        var attributionHints: [String] = []

        items.append(contentsOf: assessModelFamily(snapshot))
        items.append(contentsOf: assessFirmwareVersion(snapshot))
        items.append(contentsOf: assessImageDigestHint(snapshot, caveats: &caveats))

        let soft = ZipFindingSoftening.soften(snapshot.zipMeta?.findings ?? [])

        if snapshot.zipMeta == nil, snapshot.firmwareVersions == nil, snapshot.deviceTraits == nil {
            caveats.append("Keine Auslese- und keine ZIP-Quelle — Querverweis nicht möglich.")
        }

        if let forensic = snapshot.forensicStub {
            if let note = forensic.stockDiffNote?.trimmingCharacters(in: .whitespacesAndNewlines),
               !note.isEmpty {
                attributionHints.append("Forensik-Stub: \(note)")
            }
        }

        let summary = buildSummary(items: items)
        return CrossSourceAssessment(
            items: items,
            summary: summary,
            caveats: caveats,
            softZipFindings: soft,
            attributionHints: attributionHints
        )
    }

    // MARK: - modelFamily

    private static func assessModelFamily(_ snapshot: CrossSourceSnapshot) -> [CorrelationItem] {
        let zip = snapshot.zipMeta
        let traits = snapshot.deviceTraits
        let ble = snapshot.bleDevice

        let zipTokens = normalizedModelTokens(
            from: (zip?.models ?? []) + (zip?.compatibleBoards ?? []) + [zip?.displayName].compactMap { $0 }
        )
        let deviceHay = [
            traits?.profileLabel,
            traits?.modelLabel,
            ble?.model,
            ble?.listTitle
        ].compactMap { $0 }
        let deviceTokens = normalizedModelTokens(from: deviceHay)

        let hasZip = zip != nil && !(zipTokens.isEmpty && (zip?.displayName == nil))
        let hasDeviceSide = !deviceTokens.isEmpty || traits?.profileLabel != nil || traits?.modelLabel != nil

        if !hasZip && !hasDeviceSide {
            return [
                CorrelationItem(
                    id: "modelFamily-missing",
                    kind: .modelFamily,
                    epistemics: .incomplete,
                    title: "Modellfamilie — Quellen fehlen",
                    detail: "Weder ZIP-Modelle noch Profil/Modell-Label vorhanden.",
                    sources: [],
                    confidence: .low
                )
            ]
        }

        if hasZip && !hasDeviceSide {
            let tokenList = zipTokens.sorted().joined(separator: ", ")
            let named = tokenList.isEmpty ? "unbekannte Modelle" : tokenList
            return [
                CorrelationItem(
                    id: "modelFamily-zip-only",
                    kind: .modelFamily,
                    epistemics: .hypothesis,
                    title: "Modellfamilie nur aus ZIP",
                    detail: "ZIP nennt \(named) — ohne Auslese/Profil nicht bestätigt.",
                    sources: [.zip],
                    confidence: .low
                )
            ]
        }

        if !hasZip && hasDeviceSide {
            return [
                CorrelationItem(
                    id: "modelFamily-dump-only",
                    kind: .modelFamily,
                    epistemics: .incomplete,
                    title: "Modellfamilie — ZIP fehlt",
                    detail: "Profil/Label vorhanden, aber keine ZIP-Metadaten zum Abgleich.",
                    sources: deviceSources(ble: ble, traits: traits),
                    confidence: .low
                )
            ]
        }

        let overlap = zipTokens.intersection(deviceTokens)
        let bleSupports = ble?.isEScooterMediumOrHigher == true

        if !overlap.isEmpty && bleSupports {
            return [
                CorrelationItem(
                    id: "modelFamily-confirmed",
                    kind: .modelFamily,
                    epistemics: .confirmed,
                    title: "Modellfamilie stimmt überein",
                    detail: "Gemeinsame Tokens: \(overlap.sorted().joined(separator: ", ")). BLE-Kategorie E-Scooter (mind. mittel).",
                    sources: [.zip, .dump, .bleIdentity],
                    confidence: .high
                )
            ]
        }

        if !overlap.isEmpty {
            return [
                CorrelationItem(
                    id: "modelFamily-soft",
                    kind: .modelFamily,
                    epistemics: .hypothesis,
                    title: "Modellfamilie — weicher Treffer",
                    detail: "Token-Überlappung (\(overlap.sorted().joined(separator: ", "))), aber BLE-Kategorie/Konfidenz reicht nicht für Bestätigung.",
                    sources: [.zip, .dump],
                    confidence: .medium
                )
            ]
        }

        let zipList = zipTokens.sorted().joined(separator: ", ")
        let deviceList = deviceTokens.sorted().joined(separator: ", ")
        return [
            CorrelationItem(
                id: "modelFamily-conflict",
                kind: .modelFamily,
                epistemics: .hypothesis,
                title: "Modellfamilie — kein gemeinsamer Token",
                detail: "ZIP: \(zipList.isEmpty ? "—" : zipList); Gerät: \(deviceList.isEmpty ? "—" : deviceList).",
                sources: [.zip, .dump],
                confidence: .medium
            )
        ]
    }

    // MARK: - firmwareVersion

    private static func assessFirmwareVersion(_ snapshot: CrossSourceSnapshot) -> [CorrelationItem] {
        let versions = snapshot.firmwareVersions
        let zip = snapshot.zipMeta
        let dumpVersions = versions?.allNonEmpty ?? []
        let zipText = zip?.searchableText ?? ""

        let hasDump = !dumpVersions.isEmpty
        let hasZip = zip != nil && !zipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasDump && !hasZip {
            return [
                CorrelationItem(
                    id: "fwVersion-missing",
                    kind: .firmwareVersion,
                    epistemics: .incomplete,
                    title: "Firmware-Version — Quellen fehlen",
                    detail: "Weder Dump-FW-Strings noch ZIP-Metatext vorhanden.",
                    sources: [],
                    confidence: .low
                )
            ]
        }

        if !hasDump {
            return [
                CorrelationItem(
                    id: "fwVersion-no-dump",
                    kind: .firmwareVersion,
                    epistemics: .incomplete,
                    title: "Firmware-Version — Auslese fehlt",
                    detail: "ZIP vorhanden, aber keine fwVcu/fwMcu/fwBle aus der Auslese — kein bestätigter Abgleich.",
                    sources: [.zip],
                    confidence: .low
                )
            ]
        }

        if !hasZip {
            return [
                CorrelationItem(
                    id: "fwVersion-no-zip",
                    kind: .firmwareVersion,
                    epistemics: .incomplete,
                    title: "Firmware-Version — ZIP fehlt",
                    detail: "Dump-FW: \(dumpVersions.joined(separator: ", ")) — ohne ZIP kein Querverweis.",
                    sources: [.dump],
                    confidence: .low
                )
            ]
        }

        var exactHits: [String] = []
        var fuzzyHits: [String] = []
        for raw in dumpVersions {
            let exact = normalizeVersionToken(raw)
            if !exact.isEmpty, zipTextContainsExactVersion(zipText, version: exact) {
                exactHits.append(raw)
                continue
            }
            if let digits = digitOnlyVersion(raw),
               zipTextContainsDigitRun(zipText, digits: digits) {
                fuzzyHits.append(raw)
            }
        }

        if !exactHits.isEmpty {
            return [
                CorrelationItem(
                    id: "fwVersion-confirmed",
                    kind: .firmwareVersion,
                    epistemics: .confirmed,
                    title: "Firmware-Version stimmt überein",
                    detail: "Dump-Version(en) \(exactHits.joined(separator: ", ")) als Token in ZIP-Namen/Metadaten gefunden.",
                    sources: [.dump, .zip],
                    confidence: .high
                )
            ]
        }

        if !fuzzyHits.isEmpty {
            return [
                CorrelationItem(
                    id: "fwVersion-fuzzy",
                    kind: .firmwareVersion,
                    epistemics: .hypothesis,
                    title: "Firmware-Version — unscharfer Treffer",
                    detail: "Nur Ziffernfolge ohne Punktgrenzen für \(fuzzyHits.joined(separator: ", ")) — Hypothese, keine Bestätigung.",
                    sources: [.dump, .zip],
                    confidence: .low
                )
            ]
        }

        return [
            CorrelationItem(
                id: "fwVersion-conflict",
                kind: .firmwareVersion,
                epistemics: .hypothesis,
                title: "Firmware-Version — Konflikt / kein Treffer",
                detail: "Dump: \(dumpVersions.joined(separator: ", ")); ZIP-Text enthält keinen passenden Versions-Token.",
                sources: [.dump, .zip],
                confidence: .medium
            )
        ]
    }

    // MARK: - imageDigestHint

    private static func assessImageDigestHint(
        _ snapshot: CrossSourceSnapshot,
        caveats: inout [String]
    ) -> [CorrelationItem] {
        let zip = snapshot.zipMeta
        let liveHash = snapshot.forensicStub?.liveImageDigestHex?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let zip else {
            return [
                CorrelationItem(
                    id: "digest-no-zip",
                    kind: .imageDigestHint,
                    epistemics: .incomplete,
                    title: "Image-Digest — ZIP fehlt",
                    detail: "Kein Datei-MD5/Größe verfügbar.",
                    sources: [],
                    confidence: .low
                )
            ]
        }

        let md5 = zip.computedMd5?.lowercased()
        let size = zip.firmSizeBytes

        if md5 == nil && size == nil {
            return [
                CorrelationItem(
                    id: "digest-empty",
                    kind: .imageDigestHint,
                    epistemics: .incomplete,
                    title: "Image-Digest — keine Dateihashes",
                    detail: "ZIP ohne computedMd5/firmSizeBytes.",
                    sources: [.zip],
                    confidence: .low
                )
            ]
        }

        caveats.append("Image-Digest der Datei ist kein Nachweis einer Installation am Fahrzeug.")

        if let liveHash, !liveHash.isEmpty, let md5, md5 == liveHash {
            return [
                CorrelationItem(
                    id: "digest-file-match",
                    kind: .imageDigestHint,
                    epistemics: .hypothesis,
                    title: "Image-Digest — Datei↔Live-Hash gleich (nicht installiert)",
                    detail: "MD5 \(md5) stimmt mit Forensik-Stub überein. Das belegt nicht, dass die Datei geflasht ist.",
                    sources: [.zip, .forensicStub],
                    confidence: .medium
                )
            ]
        }

        var parts: [String] = []
        if let md5 { parts.append("MD5 \(md5)") }
        if let size { parts.append("\(size) Bytes") }
        if zip.md5Matches == true {
            parts.append("deklariert=berechnet (Datei-Integrität)")
        }
        parts.append("kein Live-Image-Hash verfügbar")

        return [
            CorrelationItem(
                id: "digest-zip-only",
                kind: .imageDigestHint,
                epistemics: .hypothesis,
                title: "Image-Digest — nur Dateiebene",
                detail: parts.joined(separator: "; ") + ".",
                sources: [.zip],
                confidence: .low
            )
        ]
    }

    // MARK: - Helpers

    private static func buildSummary(items: [CorrelationItem]) -> String {
        let c = items.filter { $0.epistemics == .confirmed }.count
        let h = items.filter { $0.epistemics == .hypothesis }.count
        let i = items.filter { $0.epistemics == .incomplete }.count
        return "Querverweis: \(c) bestätigt, \(h) Hypothese(n), \(i) unvollständig. ZIP ≠ installierte Firmware."
    }

    private static func deviceSources(
        ble: CorrelationBLEDeviceInfo?,
        traits: CorrelationDeviceIdTraits?
    ) -> [CorrelationSourceRef] {
        var s: [CorrelationSourceRef] = []
        if traits != nil { s.append(.dump) }
        if ble != nil { s.append(.bleIdentity) }
        return s
    }

    /// Normalisierte Modell-Tokens (kleingeschrieben, alphanumerisch, mind. 2 Zeichen).
    static func normalizedModelTokens(from strings: [String]) -> Set<String> {
        var out = Set<String>()
        for raw in strings {
            let lower = raw.lowercased()
            let parts = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            for part in parts {
                let t = String(part)
                guard t.count >= 2 else { continue }
                out.insert(t)
                if t.hasPrefix("max") && t.count > 3 {
                    out.insert("max")
                }
            }
            if lower.contains("g3") || lower.contains("max3") {
                out.insert("g3")
                out.insert("max3")
            }
            if lower.contains("g30") {
                out.insert("g30")
                out.insert("max")
            }
            if lower.contains("g2") {
                out.insert("g2")
            }
        }
        return out
    }

    static func normalizeVersionToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Exakter Versions-Token (z. B. `1.5.8`) als Ganzwort / mit Wortgrenzen im Text.
    static func zipTextContainsExactVersion(_ text: String, version: String) -> Bool {
        let hay = text.lowercased()
        let needle = version.lowercased()
        guard !needle.isEmpty else { return false }
        if hay.contains(needle) {
            return hasTokenBoundary(hay: hay, needle: needle)
        }
        return false
    }

    static func digitOnlyVersion(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 2 else { return nil }
        return String(digits)
    }

    static func zipTextContainsDigitRun(_ text: String, digits: String) -> Bool {
        let compact = text.lowercased().filter { $0.isNumber || $0.isLetter }
        return compact.contains(digits)
    }

    private static func hasTokenBoundary(hay: String, needle: String) -> Bool {
        guard let range = hay.range(of: needle) else { return false }
        let beforeOK: Bool = {
            if range.lowerBound == hay.startIndex { return true }
            let prev = hay[hay.index(before: range.lowerBound)]
            return !prev.isNumber && prev != "."
        }()
        let afterOK: Bool = {
            if range.upperBound == hay.endIndex { return true }
            let next = hay[range.upperBound]
            return !next.isNumber && next != "."
        }()
        return beforeOK && afterOK
    }
}

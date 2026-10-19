import Foundation

/// Regelbasierte Offline-Identifikation aus Advertisement-Merkmalen.
/// Keine erfundenen Felder, kein RSSI als Identitätsnachweis, kein automatischer
/// Schluss von Hersteller → Geräteklasse.
enum BLEIdentificationEngine {

    struct Input: Equatable, Sendable {
        var deviceId: UUID
        var displayName: String
        var localName: String?
        var manufacturerDataHex: String?
        var serviceUUIDs: [String]
        var serviceDataHexByUUID: [String: String]
        var txPower: Int?
        var isConnectable: Bool?
        var looksLikeScooterHint: Bool
        var modelLabel: String?
        var modelBadge: String?
    }

    static func analyze(_ input: Input, catalog: BluetoothCompanyCatalog = .shared) -> BLEIdentificationResult {
        var evidence: [IdentificationEvidence] = []
        var contradictions: [IdentificationEvidence] = []

        let companyId = BLEManufacturerParsing.companyId(fromManufacturerHex: input.manufacturerDataHex)
        let manufacturerName = companyId.flatMap { catalog.name(forCompanyId: $0) }

        if let companyId {
            if let manufacturerName {
                evidence.append(
                    IdentificationEvidence(
                        id: "mfg-id",
                        title: "Bluetooth Company Identifier",
                        detail: String(format: "0x%04X → %@", companyId, manufacturerName)
                    )
                )
            } else {
                evidence.append(
                    IdentificationEvidence(
                        id: "mfg-id-unknown",
                        title: "Unbekannte Company Identifier",
                        detail: String(format: "0x%04X — nicht in lokaler SIG-Datenbank", companyId)
                    )
                )
            }
        } else if input.manufacturerDataHex != nil {
            evidence.append(
                IdentificationEvidence(
                    id: "mfg-raw",
                    title: "Manufacturer Data vorhanden",
                    detail: "Company Identifier konnte nicht gelesen werden (Payload zu kurz oder Format unklar)."
                )
            )
        }

        let services = input.serviceUUIDs.map { BLEKnownServiceUUID.shortForm($0) }
        if !services.isEmpty {
            evidence.append(
                IdentificationEvidence(
                    id: "services",
                    title: "Service UUIDs",
                    detail: services.prefix(8).joined(separator: ", ")
                        + (services.count > 8 ? "…" : "")
                )
            )
        }

        // Dokumentierte Vendor-Muster (separate DB) — nur Evidenz, keine Auto-Klasse allein aus CID
        let vendorCatalog = BLEVendorPatternCatalog.shared
        if let companyId {
            for pattern in vendorCatalog.patterns(matchingCompanyId: companyId) where !pattern.aloneImpliesCategory {
                evidence.append(
                    IdentificationEvidence(
                        id: "vendor-\(pattern.id)",
                        title: "Musterkatalog: \(pattern.id)",
                        detail: pattern.evidence
                    )
                )
            }
        }
        for uuid in input.serviceUUIDs {
            for pattern in vendorCatalog.patterns(matchingServiceUUID: uuid) {
                if evidence.contains(where: { $0.id == "vendor-\(pattern.id)" }) { continue }
                evidence.append(
                    IdentificationEvidence(
                        id: "vendor-\(pattern.id)",
                        title: "Service-Muster: \(pattern.id)",
                        detail: pattern.evidence
                    )
                )
            }
        }

        // — Geräteklasse (nie nur aus Hersteller) —
        let categoryDecision = classifyCategory(
            input: input,
            companyId: companyId,
            services: services,
            evidence: &evidence,
            contradictions: &contradictions
        )

        // — Modell —
        var model = input.modelLabel
        if let model {
            evidence.append(
                IdentificationEvidence(
                    id: "model-hint",
                    title: "Modellhinweis aus Name/Serial",
                    detail: model
                )
            )
        }

        // Hersteller allein ≠ Modell
        if model == nil, companyId != nil {
            evidence.append(
                IdentificationEvidence(
                    id: "no-model",
                    title: "Modell nicht bestimmbar",
                    detail: "Herstellerkennung allein reicht nicht für eine Modellzuordnung."
                )
            )
        }

        let protocolProfile = protocolProfileLabel(services: services, companyId: companyId)
        if let protocolProfile {
            evidence.append(
                IdentificationEvidence(
                    id: "protocol",
                    title: "Kommunikationsprofil",
                    detail: protocolProfile
                )
            )
        }

        let confidence = confidenceLevel(
            manufacturer: manufacturerName,
            category: categoryDecision.category,
            model: model,
            categoryStrength: categoryDecision.strength,
            evidenceCount: evidence.filter(\.supports).count,
            hasContradiction: !contradictions.isEmpty
        )

        let radarEligible = categoryDecision.category == .eScooter
            && (categoryDecision.strength == .high || categoryDecision.strength == .medium)
            && contradictions.isEmpty

        let listTitle = makeListTitle(
            displayName: input.displayName,
            manufacturer: manufacturerName,
            category: categoryDecision.category,
            model: model,
            confidence: confidence
        )
        let listSubtitle = makeListSubtitle(
            companyId: companyId,
            manufacturer: manufacturerName,
            category: categoryDecision.category,
            model: model
        )

        return BLEIdentificationResult(
            id: UUID(),
            deviceId: input.deviceId,
            manufacturer: manufacturerName,
            manufacturerCompanyId: companyId,
            deviceCategory: categoryDecision.category,
            model: model,
            protocolProfile: protocolProfile,
            confidence: confidence,
            evidence: evidence,
            contradictions: contradictions,
            source: .local,
            analyzedAt: Date(),
            listTitle: listTitle,
            listSubtitle: listSubtitle,
            radarEligibleScooter: radarEligible,
            onlineSourceNote: nil,
            onlineFetchedAt: nil
        )
    }

    static func input(from device: ScannedDevice) -> Input {
        Input(
            deviceId: device.id,
            displayName: device.bleListDisplayName,
            localName: device.cryptoName.isEmpty ? nil : device.cryptoName,
            manufacturerDataHex: device.manufacturerDataHex,
            serviceUUIDs: device.serviceUUIDs,
            serviceDataHexByUUID: device.serviceDataHexByUUID ?? [:],
            txPower: device.txPower,
            isConnectable: device.isConnectable,
            looksLikeScooterHint: device.looksLikeScooter,
            modelLabel: device.modelLabel,
            modelBadge: device.modelBadge
        )
    }

    // MARK: - Category rules

    private enum Strength { case high, medium, low, none }

    private struct CategoryDecision {
        var category: BLEDeviceCategory
        var strength: Strength
    }

    private static func classifyCategory(
        input: Input,
        companyId: UInt16?,
        services: [String],
        evidence: inout [IdentificationEvidence],
        contradictions: inout [IdentificationEvidence]
    ) -> CategoryDecision {
        let name = (input.localName ?? "").uppercased()
        let hasNinebotUART = input.serviceUUIDs.contains {
            $0.uppercased().contains("6E400001") && $0.uppercased().contains("696E65626F74")
        }
        let hasNordicUART = input.serviceUUIDs.contains {
            let u = $0.uppercased().replacingOccurrences(of: "-", with: "")
            return u.contains("6E400001B5A3F393E0A9E50E24DCCA9E")
        }

        // Apple Continuity / typische Apple-Dienste → nicht Scooter
        if companyId == BLECompanyId.apple {
            evidence.append(
                IdentificationEvidence(
                    id: "apple-org",
                    title: "Organisation: Apple",
                    detail: "Company Identifier 0x004C. Geräteklasse bleibt unbestimmt, sofern keine weiteren Merkmale vorliegen."
                )
            )
            if name.contains("TV") || name.contains("APPLE TV") {
                return CategoryDecision(category: .television, strength: .medium)
            }
            if name.contains("WATCH") {
                return CategoryDecision(category: .smartwatch, strength: .medium)
            }
            if name.contains("AIRPOD") || name.contains("BEATS") {
                return CategoryDecision(category: .audio, strength: .medium)
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        // Samsung — nie automatisch Scooter
        if companyId == BLECompanyId.samsung {
            evidence.append(
                IdentificationEvidence(
                    id: "samsung-org",
                    title: "Organisation: Samsung",
                    detail: "Company Identifier 0x0075 identifiziert die Organisation, nicht automatisch ein Endgerät."
                )
            )
            if name.contains("TV") || name.contains("QLED") || name.contains("SAMSUNG") && name.contains("AU") {
                return CategoryDecision(category: .television, strength: .medium)
            }
            contradictions.append(
                IdentificationEvidence(
                    id: "samsung-not-scooter",
                    title: "Kein Scooter-Hinweis",
                    detail: "Samsung-Company-ID allein begründet keine E-Scooter-Klassifikation.",
                    supports: false
                )
            )
            return CategoryDecision(category: .unknown, strength: .low)
        }

        // Estimote / Beacon-Dienste
        if companyId == BLECompanyId.estimote {
            return CategoryDecision(category: .beacon, strength: .medium)
        }

        // Ninebot company ID + UART = starker Scooter-Hinweis
        if companyId == BLECompanyId.ninebot {
            evidence.append(
                IdentificationEvidence(
                    id: "ninebot-org",
                    title: "Organisation: Ninebot",
                    detail: "Company Identifier 0x0F1F (Ninebot Changzhou)."
                )
            )
            if hasNinebotUART || input.modelLabel != nil {
                evidence.append(
                    IdentificationEvidence(
                        id: "ninebot-scooter",
                        title: "Scooter-Merkmale",
                        detail: hasNinebotUART
                            ? "Ninebot-UART-Service UUID erkannt."
                            : "Modellhinweis aus Name/Serial vorhanden."
                    )
                )
                return CategoryDecision(category: .eScooter, strength: .high)
            }
            // Nur Company ID: möglicher Scooter, aber nicht radar-eligible high
            evidence.append(
                IdentificationEvidence(
                    id: "ninebot-class-uncertain",
                    title: "Geräteklasse unsicher",
                    detail: "Ninebot stellt auch Nicht-Scooter-Produkte her; ohne UART/Modell kein sicherer Scooter."
                )
            )
            return CategoryDecision(category: .unknown, strength: .low)
        }

        // Xiaomi: Company ID allein ≠ Scooter (viele Produkte)
        if companyId == BLECompanyId.xiaomi {
            evidence.append(
                IdentificationEvidence(
                    id: "xiaomi-org",
                    title: "Organisation: Xiaomi",
                    detail: "Company Identifier 0x038F."
                )
            )
            if input.modelLabel != nil || (hasNordicUART && input.looksLikeScooterHint && looksLikeXiaomiScooterName(name)) {
                evidence.append(
                    IdentificationEvidence(
                        id: "xiaomi-scooter",
                        title: "Scooter-Hinweise",
                        detail: "Modell-/Namensmuster und/oder UART in Kombination mit Scooter-Heuristik."
                    )
                )
                return CategoryDecision(category: .eScooter, strength: .medium)
            }
            if hasNordicUART && !input.looksLikeScooterHint {
                contradictions.append(
                    IdentificationEvidence(
                        id: "nordic-generic",
                        title: "Generischer Nordic UART",
                        detail: "Nordic UART wird von vielen Gerätetypen genutzt — allein kein Scooter-Beweis.",
                        supports: false
                    )
                )
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        // Ninebot UART ohne Company ID (manche Adv. ohne Manufacturer Data)
        if hasNinebotUART {
            evidence.append(
                IdentificationEvidence(
                    id: "ninebot-uart-only",
                    title: "Ninebot-UART-Service",
                    detail: "Dokumentierte Ninebot-Service-UUID ohne Company Identifier im Advertisement."
                )
            )
            return CategoryDecision(category: .eScooter, strength: .high)
        }

        // Bestehende Name/Serial-Heuristik nur mit zusätzlichem Signal verstärken
        if input.modelLabel != nil {
            evidence.append(
                IdentificationEvidence(
                    id: "ble-model-hint",
                    title: "Lokaler Modellkatalog",
                    detail: input.modelLabel!
                )
            )
            return CategoryDecision(category: .eScooter, strength: .medium)
        }

        if input.looksLikeScooterHint, hasNordicUART {
            evidence.append(
                IdentificationEvidence(
                    id: "name-plus-nordic",
                    title: "Namensheuristik + Nordic UART",
                    detail: "Beide Signale zusammen — mittlerer Scooter-Hinweis; kein alleiniger Name."
                )
            )
            return CategoryDecision(category: .eScooter, strength: .medium)
        }

        if input.looksLikeScooterHint {
            evidence.append(
                IdentificationEvidence(
                    id: "name-only",
                    title: "Nur Namensheuristik",
                    detail: "Ohne Service-/Manufacturer-Bestätigung bleibt die Klasse unsicher."
                )
            )
            return CategoryDecision(category: .unknown, strength: .low)
        }

        // Audio / Fitness generische GATT
        if services.contains("180D") || services.contains("1814") || services.contains("1816") {
            return CategoryDecision(category: .sensor, strength: .low)
        }

        return CategoryDecision(category: .unknown, strength: .none)
    }

    private static func looksLikeXiaomiScooterName(_ name: String) -> Bool {
        name.contains("MI SCOOTER")
            || name.contains("M365")
            || name.contains("PRO 2")
            || name.contains("ESSENTIAL")
            || name.contains("1S")
            || name.contains("XIAOMI")
    }

    private static func protocolProfileLabel(services: [String], companyId: UInt16?) -> String? {
        var parts: [String] = []
        if services.contains(where: { $0.contains("6E40") || $0.count > 8 }) {
            if services.contains(where: { BLEKnownServiceUUID.normalize($0).contains("696E65626F74") }) {
                parts.append("Ninebot UART")
            } else if services.contains(where: {
                BLEKnownServiceUUID.normalize($0).contains("6E400001B5A3F393E0A9E50E24DCCA9E")
            }) {
                parts.append("Nordic UART")
            }
        }
        if services.contains("180A") { parts.append("Device Information") }
        if companyId == BLECompanyId.apple { parts.append("Apple manufacturer payload") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func confidenceLevel(
        manufacturer: String?,
        category: BLEDeviceCategory,
        model: String?,
        categoryStrength: Strength,
        evidenceCount: Int,
        hasContradiction: Bool
    ) -> BLEIdentificationConfidence {
        if hasContradiction, category == .eScooter {
            return .low
        }
        if model != nil, categoryStrength == .high {
            return .high
        }
        if manufacturer != nil, categoryStrength == .high {
            return .high
        }
        if manufacturer != nil, category != .unknown, categoryStrength == .medium {
            return .medium
        }
        if manufacturer != nil || categoryStrength == .medium {
            return .medium
        }
        if manufacturer != nil || evidenceCount > 0 {
            return .low
        }
        return .unknown
    }

    private static func makeListTitle(
        displayName: String,
        manufacturer: String?,
        category: BLEDeviceCategory,
        model: String?,
        confidence: BLEIdentificationConfidence
    ) -> String {
        if let model {
            return model
        }
        if category == .eScooter, confidence == .high || confidence == .medium {
            if let manufacturer {
                return "Möglicher E-Scooter (\(shortManufacturer(manufacturer)))"
            }
            return "Möglicher E-Scooter"
        }
        if let manufacturer, category != .unknown, category != .eScooter {
            return "\(shortManufacturer(manufacturer)) – \(category.label)"
        }
        if let manufacturer {
            return "\(shortManufacturer(manufacturer)) – Modell unbekannt"
        }
        if category != .unknown {
            return "Mögliches \(category.label)"
        }
        if displayName.hasPrefix("Ohne Namen") {
            return "Unbekanntes BLE-Gerät"
        }
        return displayName
    }

    private static func makeListSubtitle(
        companyId: UInt16?,
        manufacturer: String?,
        category: BLEDeviceCategory,
        model: String?
    ) -> String? {
        var bits: [String] = []
        if let companyId {
            bits.append(String(format: "CID 0x%04X", companyId))
        }
        if let manufacturer, model != nil {
            bits.append(shortManufacturer(manufacturer))
        }
        if category != .unknown, model == nil {
            bits.append(category.label)
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private static func shortManufacturer(_ name: String) -> String {
        name
            .replacingOccurrences(of: ", Inc.", with: "")
            .replacingOccurrences(of: " Co. Ltd.", with: "")
            .replacingOccurrences(of: " Co., Ltd.", with: "")
            .replacingOccurrences(of: " (Changzhou) Tech Co., Ltd.", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

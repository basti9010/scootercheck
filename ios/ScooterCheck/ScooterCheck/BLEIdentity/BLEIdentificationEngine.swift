import Foundation

/// Regelbasierte Offline-Identifikation aus Advertisement-Merkmalen.
/// Gilt für **alle** BLE-Geräte (E-Scooter und Nicht-Scooter).
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

        // Dokumentierte Vendor-Muster — nur Evidenz, keine Auto-Klasse allein aus CID
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

        let categoryDecision = classifyCategory(
            input: input,
            companyId: companyId,
            services: services,
            evidence: &evidence,
            contradictions: &contradictions
        )

        let model = input.modelLabel
        if let model {
            evidence.append(
                IdentificationEvidence(
                    id: "model-hint",
                    title: "Modellhinweis aus Name/Serial",
                    detail: model
                )
            )
        }

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
            model: model,
            localName: input.localName
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
        let name = (input.localName ?? input.displayName).uppercased()
        let hasNinebotUART = input.serviceUUIDs.contains {
            $0.uppercased().contains("6E400001") && $0.uppercased().contains("696E65626F74")
        }
        let hasNordicUART = input.serviceUUIDs.contains {
            let u = $0.uppercased().replacingOccurrences(of: "-", with: "")
            return u.contains("6E400001B5A3F393E0A9E50E24DCCA9E")
        }

        // —— Starke Scooter-Signale zuerst (dürfen Nicht-Scooter-Regeln nicht überstimmen) ——
        if hasNinebotUART {
            evidence.append(
                IdentificationEvidence(
                    id: "ninebot-uart",
                    title: "Ninebot-UART-Service",
                    detail: "Dokumentierte Ninebot-Service-UUID."
                )
            )
            return CategoryDecision(category: .eScooter, strength: .high)
        }

        if companyId == BLECompanyId.ninebot {
            evidence.append(
                IdentificationEvidence(
                    id: "ninebot-org",
                    title: "Organisation: Ninebot",
                    detail: "Company Identifier 0x0F1F (Ninebot Changzhou)."
                )
            )
            if input.modelLabel != nil {
                return CategoryDecision(category: .eScooter, strength: .high)
            }
            evidence.append(
                IdentificationEvidence(
                    id: "ninebot-class-uncertain",
                    title: "Geräteklasse unsicher",
                    detail: "Ninebot stellt auch Nicht-Scooter-Produkte her; ohne UART/Modell kein sicherer Scooter."
                )
            )
            // Fall-through: kein Scooter, aber auch kein Fake-Modell
        }

        if companyId == BLECompanyId.xiaomi {
            evidence.append(
                IdentificationEvidence(
                    id: "xiaomi-org",
                    title: "Organisation: Xiaomi",
                    detail: "Company Identifier 0x038F — Organisation, nicht Produktklasse."
                )
            )
            if input.modelLabel != nil
                || (hasNordicUART && input.looksLikeScooterHint && looksLikeXiaomiScooterName(name)) {
                return CategoryDecision(category: .eScooter, strength: .medium)
            }
            if let nonScooter = classifyXiaomiNonScooter(name: name, evidence: &evidence) {
                return nonScooter
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
        }

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
                    detail: "Beide Signale zusammen — mittlerer Scooter-Hinweis."
                )
            )
            return CategoryDecision(category: .eScooter, strength: .medium)
        }

        if input.looksLikeScooterHint {
            evidence.append(
                IdentificationEvidence(
                    id: "name-only",
                    title: "Nur Namensheuristik",
                    detail: "Ohne Service-/Manufacturer-Bestätigung bleibt die Klasse unsicher — kein Radar-Scooter."
                )
            )
            // weiter: ggf. Nicht-Scooter-Merkmale
        }

        // —— Nicht-Scooter: Organisation + Name / Dienste ——
        if companyId == BLECompanyId.apple {
            evidence.append(
                IdentificationEvidence(
                    id: "apple-org",
                    title: "Organisation: Apple",
                    detail: "Company Identifier 0x004C."
                )
            )
            if let d = classifyApple(name: name, services: services, evidence: &evidence) {
                return d
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        if companyId == BLECompanyId.samsung {
            evidence.append(
                IdentificationEvidence(
                    id: "samsung-org",
                    title: "Organisation: Samsung",
                    detail: "Company Identifier 0x0075 — keine automatische Scooter-Klassifikation."
                )
            )
            contradictions.append(
                IdentificationEvidence(
                    id: "samsung-not-scooter",
                    title: "Kein Scooter-Hinweis",
                    detail: "Samsung-Company-ID allein begründet keine E-Scooter-Klassifikation.",
                    supports: false
                )
            )
            if let d = classifySamsung(name: name, evidence: &evidence) {
                return d
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        if companyId == BLECompanyId.estimote {
            evidence.append(
                IdentificationEvidence(
                    id: "estimote-org",
                    title: "Organisation: Estimote",
                    detail: "Company Identifier 0x015D — Beacon-Familie."
                )
            )
            return CategoryDecision(category: .beacon, strength: .medium)
        }

        if companyId == BLECompanyId.bose || companyId == BLECompanyId.sony {
            evidence.append(
                IdentificationEvidence(
                    id: "audio-org",
                    title: "Audio-Herstellerkennung",
                    detail: "Organisation bekannt; Geräteklasse nur mit Namens-/Servicehinweis belastbar."
                )
            )
            if looksLikeAudioName(name) || services.contains(where: { $0.hasPrefix("11") }) {
                return CategoryDecision(category: .audio, strength: .medium)
            }
            // Bose/Sony überwiegend Audio — ohne Namen nur schwacher Hinweis, nicht als Fakt
            return CategoryDecision(category: .audio, strength: .low)
        }

        if companyId == BLECompanyId.garmin || companyId == BLECompanyId.fitbit {
            evidence.append(
                IdentificationEvidence(
                    id: "wearable-org",
                    title: "Wearable-Herstellerkennung",
                    detail: "Organisation bekannt; Modell nur mit Namenshinweis."
                )
            )
            if looksLikeWatchName(name) {
                return CategoryDecision(category: .smartwatch, strength: .medium)
            }
            return CategoryDecision(category: .wearable, strength: .low)
        }

        if companyId == BLECompanyId.google {
            evidence.append(
                IdentificationEvidence(
                    id: "google-org",
                    title: "Organisation: Google",
                    detail: "Company Identifier 0x00E0."
                )
            )
            if let d = classifyGoogle(name: name, evidence: &evidence) {
                return d
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        if companyId == BLECompanyId.microsoft {
            evidence.append(
                IdentificationEvidence(
                    id: "ms-org",
                    title: "Organisation: Microsoft",
                    detail: "Company Identifier 0x0006."
                )
            )
            if name.contains("SURFACE") || name.contains("XBOX") || name.contains("KEYBOARD") || name.contains("MOUSE") {
                return CategoryDecision(category: .computer, strength: .medium)
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        if companyId == BLECompanyId.lg {
            evidence.append(
                IdentificationEvidence(
                    id: "lg-org",
                    title: "Organisation: LG Electronics",
                    detail: "Company Identifier 0x00C4."
                )
            )
            if name.contains("TV") || name.contains("OLED") || name.contains("WEBOS") {
                return CategoryDecision(category: .television, strength: .medium)
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        if companyId == BLECompanyId.espressif {
            evidence.append(
                IdentificationEvidence(
                    id: "espressif-org",
                    title: "Organisation: Espressif (Chip)",
                    detail: "Chip-Hersteller — typisch IoT/Smart-Home, kein Endprodukt-Beweis."
                )
            )
            if looksLikeSmartHomeName(name) {
                return CategoryDecision(category: .smartHome, strength: .medium)
            }
            return CategoryDecision(category: .unknown, strength: .low)
        }

        if companyId == BLECompanyId.nordic {
            evidence.append(
                IdentificationEvidence(
                    id: "nordic-org",
                    title: "Organisation: Nordic Semiconductor",
                    detail: "Chip-Hersteller — viele Endgeräteklassen; allein keine Produktklasse."
                )
            )
        }

        // —— Generische GATT- / Namensregeln (herstellerunabhängig) ——
        if let gatt = classifyFromGATT(services: services, evidence: &evidence) {
            return gatt
        }

        if let byName = classifyFromNameAlone(name: name, evidence: &evidence) {
            return byName
        }

        return CategoryDecision(category: .unknown, strength: .none)
    }

    // MARK: Non-scooter helpers

    private static func classifyApple(
        name: String,
        services: [String],
        evidence: inout [IdentificationEvidence]
    ) -> CategoryDecision? {
        if services.contains(BLEKnownServiceUUID.exposureNotification)
            || services.contains(where: { $0.uppercased().contains("FD6F") }) {
            evidence.append(
                IdentificationEvidence(
                    id: "apple-ens",
                    title: "Exposure Notification UUID",
                    detail: "Typisch für Smartphones — kein Scooter."
                )
            )
            return CategoryDecision(category: .smartphone, strength: .medium)
        }
        if name.contains("APPLE TV") || name.contains("TV") && name.contains("APPLE") {
            return CategoryDecision(category: .television, strength: .medium)
        }
        if name.contains("WATCH") || name.contains("APPLE WATCH") {
            return CategoryDecision(category: .smartwatch, strength: .medium)
        }
        if name.contains("AIRPOD") || name.contains("BEATS") || name.contains("HOMEPOD") {
            return CategoryDecision(category: .audio, strength: .medium)
        }
        if name.contains("IPHONE") || name.contains("IPAD") || name.contains("MACBOOK") || name.contains("IMAC") {
            return CategoryDecision(category: name.contains("IPHONE") || name.contains("IPAD") ? .smartphone : .computer, strength: .medium)
        }
        return nil
    }

    private static func classifySamsung(name: String, evidence: inout [IdentificationEvidence]) -> CategoryDecision? {
        if name.contains("TV") || name.contains("QLED") || name.contains("OLED")
            || (name.contains("SAMSUNG") && name.contains("AU")) {
            evidence.append(
                IdentificationEvidence(
                    id: "samsung-tv-name",
                    title: "Namenshinweis Fernseher",
                    detail: "Local Name enthält TV-/Display-Muster."
                )
            )
            return CategoryDecision(category: .television, strength: .medium)
        }
        if name.contains("WATCH") || name.contains("GALAXY WATCH") || name.contains("GEAR") {
            return CategoryDecision(category: .smartwatch, strength: .medium)
        }
        if name.contains("BUDS") || name.contains("GALAXY BUDS") {
            return CategoryDecision(category: .audio, strength: .medium)
        }
        if name.contains("GALAXY") || name.contains("SM-") {
            return CategoryDecision(category: .smartphone, strength: .low)
        }
        return nil
    }

    private static func classifyXiaomiNonScooter(
        name: String,
        evidence: inout [IdentificationEvidence]
    ) -> CategoryDecision? {
        if name.contains("MI BAND") || name.contains("MIBAND") || name.contains("REDMI WATCH")
            || name.contains("AMAZFIT") {
            evidence.append(
                IdentificationEvidence(
                    id: "xiaomi-wearable-name",
                    title: "Wearable-Namensmuster",
                    detail: "Passt zu Fitness-Band/Watch — nicht E-Scooter."
                )
            )
            return CategoryDecision(category: .wearable, strength: .medium)
        }
        if name.contains("AIRPURIFIER") || name.contains("ROBOT") || name.contains("VACUUM")
            || name.contains("SMART HOME") || name.contains("YEELIGHT") {
            return CategoryDecision(category: .smartHome, strength: .medium)
        }
        if name.contains("EARPHONE") || name.contains("BUDS") || name.contains("HEADSET") {
            return CategoryDecision(category: .audio, strength: .medium)
        }
        return nil
    }

    private static func classifyGoogle(name: String, evidence: inout [IdentificationEvidence]) -> CategoryDecision? {
        if name.contains("CHROMECAST") || name.contains("GOOGLE TV") || name.contains("ANDROID TV") {
            return CategoryDecision(category: .television, strength: .medium)
        }
        if name.contains("NEST") || name.contains("HOME") {
            return CategoryDecision(category: .smartHome, strength: .medium)
        }
        if name.contains("PIXEL BUDS") || name.contains("BUDS") {
            return CategoryDecision(category: .audio, strength: .medium)
        }
        if name.contains("PIXEL") {
            return CategoryDecision(category: .smartphone, strength: .low)
        }
        return nil
    }

    private static func classifyFromGATT(
        services: [String],
        evidence: inout [IdentificationEvidence]
    ) -> CategoryDecision? {
        let upper = services.map { $0.uppercased() }
        if upper.contains(BLEKnownServiceUUID.eddystone)
            || upper.contains(where: { $0.contains("FEAA") }) {
            evidence.append(
                IdentificationEvidence(
                    id: "eddystone",
                    title: "Eddystone-Service",
                    detail: "Bluetooth-Beacon-Profil (FEAA)."
                )
            )
            return CategoryDecision(category: .beacon, strength: .medium)
        }
        if upper.contains(BLEKnownServiceUUID.exposureNotification)
            || upper.contains(where: { $0.contains("FD6F") }) {
            evidence.append(
                IdentificationEvidence(
                    id: "ens",
                    title: "Exposure Notification",
                    detail: "Typisch Smartphone — kein Scooter."
                )
            )
            return CategoryDecision(category: .smartphone, strength: .medium)
        }
        if upper.contains(BLEKnownServiceUUID.humanInterfaceDevice) {
            evidence.append(
                IdentificationEvidence(
                    id: "hid",
                    title: "HID-Service (1812)",
                    detail: "Human Interface Device — Tastatur/Maus/Controller."
                )
            )
            return CategoryDecision(category: .computer, strength: .medium)
        }
        if upper.contains(BLEKnownServiceUUID.heartRate)
            || upper.contains(BLEKnownServiceUUID.runningSpeedCadence)
            || upper.contains(BLEKnownServiceUUID.cyclingSpeedCadence)
            || upper.contains(BLEKnownServiceUUID.pulseOximeter)
            || upper.contains(BLEKnownServiceUUID.bloodPressure)
            || upper.contains(BLEKnownServiceUUID.glucose)
            || upper.contains(BLEKnownServiceUUID.weightScale) {
            evidence.append(
                IdentificationEvidence(
                    id: "fitness-gatt",
                    title: "Fitness-/Gesundheits-GATT",
                    detail: "Standardisierte SIG-Dienste (z. B. Heart Rate, CSC)."
                )
            )
            return CategoryDecision(category: .sensor, strength: .medium)
        }
        if upper.contains(BLEKnownServiceUUID.environmentalSensing)
            || upper.contains(BLEKnownServiceUUID.automationIO) {
            return CategoryDecision(category: .smartHome, strength: .low)
        }
        return nil
    }

    private static func classifyFromNameAlone(
        name: String,
        evidence: inout [IdentificationEvidence]
    ) -> CategoryDecision? {
        guard !name.isEmpty, !name.hasPrefix("OHNE NAMEN") else { return nil }
        if looksLikeTVName(name) {
            evidence.append(
                IdentificationEvidence(
                    id: "name-tv",
                    title: "Namenshinweis Fernseher",
                    detail: "Local Name enthält TV-/Display-Muster (ohne Hersteller-Bestätigung schwach)."
                )
            )
            return CategoryDecision(category: .television, strength: .low)
        }
        if looksLikeAudioName(name) {
            return CategoryDecision(category: .audio, strength: .low)
        }
        if looksLikeWatchName(name) {
            return CategoryDecision(category: .smartwatch, strength: .low)
        }
        if looksLikeSmartHomeName(name) {
            return CategoryDecision(category: .smartHome, strength: .low)
        }
        if name.contains("IBEACON") || name.contains("BEACON") || name.contains("TILE") {
            return CategoryDecision(category: .beacon, strength: .low)
        }
        return nil
    }

    private static func looksLikeXiaomiScooterName(_ name: String) -> Bool {
        name.contains("MI SCOOTER")
            || name.contains("M365")
            || name.contains("PRO 2")
            || name.contains("ESSENTIAL")
            || name.contains("1S")
            || name.contains("XIAOMI") && name.contains("SCOOTER")
    }

    private static func looksLikeTVName(_ name: String) -> Bool {
        name.contains("TV") || name.contains("QLED") || name.contains("OLED")
            || name.contains("WEBOS") || name.contains("BRAVIA") || name.contains("FIRETV")
    }

    private static func looksLikeAudioName(_ name: String) -> Bool {
        name.contains("AIRPOD") || name.contains("BUDS") || name.contains("HEADSET")
            || name.contains("HEADPHONE") || name.contains("SPEAKER") || name.contains("SOUNDBAR")
            || name.contains("BEATS") || name.contains("WH-") || name.contains("WF-")
            || name.contains("BOSE") || name.contains("JBL")
    }

    private static func looksLikeWatchName(_ name: String) -> Bool {
        name.contains("WATCH") || name.contains("BAND") || name.contains("FITBIT")
            || name.contains("GARMIN") || name.contains("VERSA") || name.contains("CHARGE")
    }

    private static func looksLikeSmartHomeName(_ name: String) -> Bool {
        name.contains("SHELLY") || name.contains("PHILIPS HUE") || name.contains("HUE ")
            || name.contains("SMARTPLUG") || name.contains("SMART BULB") || name.contains("TASMOTA")
            || name.contains("ESPHOME") || name.contains("YEELIGHT") || name.contains("SWITCHBOT")
            || name.contains("VALETUDO") || name.contains("HOMEKIT")
    }

    private static func protocolProfileLabel(services: [String], companyId: UInt16?) -> String? {
        var parts: [String] = []
        if services.contains(where: {
            BLEKnownServiceUUID.normalize($0).contains("696E65626F74")
        }) {
            parts.append("Ninebot UART")
        } else if services.contains(where: {
            BLEKnownServiceUUID.normalize($0).contains("6E400001B5A3F393E0A9E50E24DCCA9E")
        }) {
            parts.append("Nordic UART")
        }
        if services.contains("180A") { parts.append("Device Information") }
        if services.contains("1812") { parts.append("HID") }
        if services.contains("180D") { parts.append("Heart Rate") }
        if services.contains(where: { $0.uppercased().contains("FEAA") }) { parts.append("Eddystone") }
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
        if category != .unknown, categoryStrength == .medium {
            return .medium
        }
        if manufacturer != nil || categoryStrength == .medium || categoryStrength == .low {
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
        model: String?,
        localName: String?
    ) -> String? {
        var bits: [String] = []
        if let companyId {
            bits.append(String(format: "CID 0x%04X", companyId))
        }
        if let manufacturer, model != nil {
            bits.append(shortManufacturer(manufacturer))
        }
        if category != .unknown {
            bits.append(category.label)
        } else if manufacturer == nil {
            bits.append("Klasse unbekannt")
        }
        if let localName, !localName.isEmpty,
           manufacturer != nil || category != .unknown {
            let short = localName.count > 28 ? String(localName.prefix(28)) + "…" : localName
            if !bits.contains(where: { localName.localizedCaseInsensitiveContains($0) }) {
                bits.append(short)
            }
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private static func shortManufacturer(_ name: String) -> String {
        name
            .replacingOccurrences(of: ", Inc.", with: "")
            .replacingOccurrences(of: " Co. Ltd.", with: "")
            .replacingOccurrences(of: " Co., Ltd.", with: "")
            .replacingOccurrences(of: " Electronics Co. Ltd.", with: "")
            .replacingOccurrences(of: " (Changzhou) Tech Co., Ltd.", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

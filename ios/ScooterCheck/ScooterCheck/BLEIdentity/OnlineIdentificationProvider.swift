import Foundation

/// Datensparsame Online-Identifikation.
///
/// Ohne konfiguriertes Backend werden **keine** Ergebnisse simuliert.
/// Erwartete Backend-URL (optional, Info.plist / UserDefaults):
/// `BLE_IDENTIFICATION_ENDPOINT` — POST JSON mit technischen Kennungen, Antwort gemäß Schema.
enum OnlineIdentificationProvider {

    struct Query: Sendable {
        var companyId: UInt16?
        var serviceUUIDs: [String]
        var localNamePrefix: String?
        var advertisingStructureKey: String
    }

    enum Outcome: Sendable {
        case unavailable(reason: String)
        case result(BLEIdentificationResult)
    }

    private struct RequestBody: Codable {
        var companyId: String?
        var serviceUUIDs: [String]
        var namePrefix: String?
        var structureKey: String
        var clientVersion: Int
    }

    private struct ResponseBody: Codable {
        var manufacturer: String?
        var deviceCategory: String?
        var model: String?
        var confidence: String?
        var sourceNote: String?
        var evidence: [EvidenceDTO]?
    }

    private struct EvidenceDTO: Codable {
        var title: String
        var detail: String
    }

    /// Lookup — ohne Endpoint: ehrliche Unavailability-Meldung.
    static func lookup(_ query: Query) async -> Outcome {
        guard let endpoint = configuredEndpoint() else {
            return .unavailable(
                reason: "Online-Identifikation ist aktiviert, aber kein Backend konfiguriert (BLE_IDENTIFICATION_ENDPOINT). Lokale Analyse bleibt verfügbar."
            )
        }
        guard let url = URL(string: endpoint) else {
            return .unavailable(reason: "Ungültige Backend-URL für Online-Identifikation.")
        }

        let body = RequestBody(
            companyId: query.companyId.map { String(format: "0x%04X", $0) },
            serviceUUIDs: Array(query.serviceUUIDs.prefix(12)),
            namePrefix: query.localNamePrefix,
            structureKey: query.advertisingStructureKey,
            clientVersion: 1
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 12
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable(reason: "Ungültige Serverantwort.")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .unavailable(reason: "Online-Dienst antwortete mit HTTP \(http.statusCode).")
            }
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            return .result(mapResponse(decoded, query: query))
        } catch {
            return .unavailable(reason: "Online-Recherche fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private static func configuredEndpoint() -> String? {
        if let plist = Bundle.main.object(forInfoDictionaryKey: "BLE_IDENTIFICATION_ENDPOINT") as? String,
           !plist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let stored = UserDefaults.standard.string(forKey: "bleIdentification.endpoint"),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func mapResponse(_ dto: ResponseBody, query: Query) -> BLEIdentificationResult {
        let category = BLEDeviceCategory(rawValue: dto.deviceCategory ?? "") ?? {
            switch (dto.deviceCategory ?? "").lowercased() {
            case "e-scooter", "escooter", "scooter": return .eScooter
            case "tv", "television": return .television
            case "audio": return .audio
            case "smartphone", "phone": return .smartphone
            case "smartwatch", "watch": return .smartwatch
            case "smart-home", "smarthome": return .smartHome
            case "sensor": return .sensor
            case "beacon": return .beacon
            default: return .unknown
            }
        }()

        let confidence = BLEIdentificationConfidence(rawValue: dto.confidence ?? "low") ?? .low
        let evidence = (dto.evidence ?? []).map {
            IdentificationEvidence(title: $0.title, detail: $0.detail)
        }

        return BLEIdentificationResult(
            id: UUID(),
            deviceId: UUID(),
            manufacturer: dto.manufacturer,
            manufacturerCompanyId: query.companyId,
            deviceCategory: category,
            model: dto.model,
            protocolProfile: nil,
            confidence: confidence,
            evidence: evidence.isEmpty
                ? [IdentificationEvidence(title: "Online-Hinweis", detail: dto.sourceNote ?? "Externe Recherche")]
                : evidence,
            contradictions: [],
            source: .online,
            analyzedAt: Date(),
            listTitle: dto.model ?? dto.manufacturer ?? "Online-Treffer",
            listSubtitle: dto.sourceNote,
            radarEligibleScooter: false,
            onlineSourceNote: dto.sourceNote ?? "Backend-Identifikation",
            onlineFetchedAt: Date()
        )
    }
}

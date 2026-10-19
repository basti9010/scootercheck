import Foundation

/// Online-Protokollrecherche — ohne Endpoint keine erfundenen Treffer.
enum OnlineProtocolDiscoveryService {

    struct Query: Sendable {
        var manufacturerHint: String?
        var modelHint: String?
        var serviceUUIDs: [String]
        var companyId: UInt16?
        var localNamePrefix: String?
    }

    enum Outcome: Sendable {
        /// Verifizierte, signierte Profile können in die Registry übernommen werden.
        case profiles(Data, signatureHex: String?)
        /// Nur Recherchehinweis — nicht für automatische Diagnose.
        case researchHint(title: String, detail: String, sourceUrl: String?)
        case unavailable(reason: String)
    }

    private struct RequestBody: Codable {
        var manufacturerHint: String?
        var modelHint: String?
        var serviceUUIDs: [String]
        var companyId: String?
        var namePrefix: String?
        var clientVersion: Int
        var wantSignedProfiles: Bool
    }

    private struct HintResponse: Codable {
        var title: String?
        var detail: String?
        var sourceUrl: String?
        var signature: String?
    }

    static func discover(_ query: Query) async -> Outcome {
        guard let endpoint = configuredEndpoint() else {
            return .unavailable(
                reason: "Online-Protokollsuche aktiv, aber kein Backend konfiguriert (SCOOTER_PROTOCOL_DISCOVERY_ENDPOINT). Es werden keine Treffer simuliert."
            )
        }
        guard let url = URL(string: endpoint) else {
            return .unavailable(reason: "Ungültige Backend-URL für Protokolldiscovery.")
        }

        let body = RequestBody(
            manufacturerHint: query.manufacturerHint,
            modelHint: query.modelHint,
            serviceUUIDs: Array(query.serviceUUIDs.prefix(12)),
            companyId: query.companyId.map { String(format: "0x%04X", $0) },
            namePrefix: query.localNamePrefix.map { String($0.prefix(24)) },
            clientVersion: 1,
            wantSignedProfiles: true
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unavailable(reason: "Ungültige Serverantwort.")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .unavailable(reason: "Protokollsuche antwortete mit HTTP \(http.statusCode).")
            }

            let signature = http.value(forHTTPHeaderField: "X-ScooterCheck-Signature")
                ?? http.value(forHTTPHeaderField: "X-Profile-Signature")

            // Vollständige Profildatei?
            if (try? JSONDecoder().decode(ScooterDiagnosticProfileFile.self, from: data)) != nil {
                return .profiles(data, signatureHex: signature)
            }

            let hint = try JSONDecoder().decode(HintResponse.self, from: data)
            let title = hint.title ?? "Recherchehinweis"
            let detail = hint.detail ?? "Server lieferte keinen validierten Profilinhalt."
            return .researchHint(title: title, detail: detail, sourceUrl: hint.sourceUrl)
        } catch {
            return .unavailable(reason: "Online-Protokollsuche fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    static func configuredEndpoint() -> String? {
        if let plist = Bundle.main.object(forInfoDictionaryKey: "SCOOTER_PROTOCOL_DISCOVERY_ENDPOINT") as? String,
           !plist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ud = UserDefaults.standard.string(forKey: "SCOOTER_PROTOCOL_DISCOVERY_ENDPOINT")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let ud, !ud.isEmpty { return ud }
        return nil
    }
}

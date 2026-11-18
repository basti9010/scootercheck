import Foundation

/// Katalog der in ScooterHacking Utility gelisteten Modelle inkl. ScooterCheck-Auslesbarkeit.
struct SupportedScooterModel: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var profileFamily: String
    var stack: String
    var readable: Bool
    var firmwareArchive: String?
    var hwProtocol: String?
}

struct SupportedScooterBrand: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var models: [SupportedScooterModel]
}

struct SupportedScooterModelsFile: Codable, Sendable {
    var version: Int
    var updatedAt: String
    var source: String
    var sourceUrl: String?
    var note: String?
    var brands: [SupportedScooterBrand]
}

enum SupportedScooterModelsCatalog {
    static let shared: SupportedScooterModelsFile = loadBundled() ?? emptyFallback()

    static var allModels: [SupportedScooterModel] {
        shared.brands.flatMap(\.models)
    }

    static var readableCount: Int {
        allModels.filter(\.readable).count
    }

    private static func loadBundled() -> SupportedScooterModelsFile? {
        guard let url = Bundle.main.url(forResource: "supported_scooter_models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SupportedScooterModelsFile.self, from: data) else {
            return nil
        }
        return file
    }

    private static func emptyFallback() -> SupportedScooterModelsFile {
        SupportedScooterModelsFile(
            version: 0,
            updatedAt: "fallback",
            source: "Embedded empty fallback",
            sourceUrl: nil,
            note: "Bundle JSON missing",
            brands: []
        )
    }
}

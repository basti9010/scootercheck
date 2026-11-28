import Foundation

/// Non-secret profile cache so a previously valid session can unlock local features offline.
protocol AuthUserCaching: AnyObject {
    func loadUser() -> AuthUser?
    func saveUser(_ user: AuthUser)
    func deleteUser()
}

final class UserDefaultsAuthUserCache: AuthUserCaching {
    static let defaultsKey = "scootercheck.auth.cached_user"

    private let key: String
    private let defaults: UserDefaults

    init(key: String = UserDefaultsAuthUserCache.defaultsKey, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func loadUser() -> AuthUser? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    func saveUser(_ user: AuthUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        defaults.set(data, forKey: key)
    }

    func deleteUser() {
        defaults.removeObject(forKey: key)
    }
}

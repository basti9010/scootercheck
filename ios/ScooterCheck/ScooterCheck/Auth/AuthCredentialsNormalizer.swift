import Foundation

/// Login helpers for paste / Caps-Lock quirks (esp. Hetzner console & iOS paste).
enum AuthCredentialsNormalizer {
    /// Trim + lowercase email (server also matches NOCASE).
    static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Trim accidental whitespace/newlines from password managers / paste.
    static func normalizedPassword(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Swap A↔a for every letter. Used once as login retry when Caps Lock inverted a paste.
    static func toggledLetterCase(_ raw: String) -> String {
        String(raw.map { ch in
            if ch.isUppercase {
                return Character(ch.lowercased())
            }
            if ch.isLowercase {
                let upper = ch.uppercased()
                return upper.count == 1 ? Character(upper) : ch
            }
            return ch
        })
    }

    static func isWrongCredentialsMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let lower = message.lowercased()
        return lower.contains("e-mail oder passwort")
            || lower.contains("passwort falsch")
            || lower.contains("unauthorized")
    }

    static func isWrongCredentials(_ error: AuthAPIError?) -> Bool {
        if error?.kind == .invalidCredentials { return true }
        return isWrongCredentialsMessage(error?.message)
    }
}

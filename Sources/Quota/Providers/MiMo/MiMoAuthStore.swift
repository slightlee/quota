import Foundation
import Security

/// The Xiaomi provider entry written by MiMoCode.
struct MiMoCodeAccount: Equatable {
    var baseURL: URL
}

/// Reads MiMoCode's local account and Quota's Xiaomi console session cookie.
///
/// MiMoCode stores the Token Plan API key in `auth.json`, but Xiaomi's quota
/// endpoint is protected by the web console session and rejects that `tp-...`
/// key. Quota therefore only uses MiMoCode to discover the signed-in Xiaomi
/// account/region; the console cookie is stored separately in the macOS
/// Keychain.
final class MiMoAuthStore {
    static let shared = MiMoAuthStore()

    static let keychainService = "Quota-MiMo-session"
    static let keychainAccount = "platform.xiaomimimo.com"

    private struct AuthEntry: Decodable {
        struct Metadata: Decodable {
            var baseURL: String?

            private enum CodingKeys: String, CodingKey {
                case baseURL = "base_url"
            }
        }

        var key: String?
        var metadata: Metadata?
    }

    private let fileManager: FileManager
    private let authFileURLs: [URL]
    private let environment: [String: String]
    private let keychainReader: () -> String?
    private let keychainWriter: (String?) throws -> Void

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychainReader: (() -> String?)? = nil,
        keychainWriter: ((String?) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment

        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = []
        if let xdgDataHome = environment["XDG_DATA_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !xdgDataHome.isEmpty {
            candidates.append(
                URL(fileURLWithPath: xdgDataHome, isDirectory: true)
                    .appendingPathComponent("mimocode/auth.json")
            )
        }
        candidates.append(home.appendingPathComponent(".local/share/mimocode/auth.json"))
        candidates.append(
            home.appendingPathComponent("Library/Application Support/mimocode/auth.json")
        )
        self.authFileURLs = candidates

        self.keychainReader = keychainReader ?? Self.readKeychainCookie
        self.keychainWriter = keychainWriter ?? Self.writeKeychainCookie
    }

    /// Confirms MiMoCode has a Xiaomi account and returns its configured region.
    func loadMiMoCodeAccount() throws -> MiMoCodeAccount {
        guard let data = authFileURLs.lazy.compactMap(loadData).first else {
            throw MiMoQuotaError.mimoCodeNotSignedIn
        }

        let entries: [String: AuthEntry]
        do {
            entries = try JSONDecoder().decode([String: AuthEntry].self, from: data)
        } catch {
            throw MiMoQuotaError.invalidMiMoCodeAuth
        }

        guard let entry = entries["xiaomi"],
              let key = entry.key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw MiMoQuotaError.mimoCodeNotSignedIn
        }

        let baseURLString = entry.metadata?.baseURL?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "https://token-plan-cn.xiaomimimo.com/v1"
        guard let baseURL = URL(string: baseURLString?.isEmpty == false ? baseURLString! : fallback) else {
            throw MiMoQuotaError.invalidMiMoCodeAuth
        }
        return MiMoCodeAccount(baseURL: baseURL)
    }

    /// Environment override is useful for `swift run`; packaged apps use Keychain.
    func loadSessionCookie() throws -> String {
        let rawValue = environment["XIAOMI_MIMO_SESSION_COOKIE"] ?? keychainReader()
        guard let cookie = Self.normalizeCookie(rawValue), !cookie.isEmpty else {
            throw MiMoQuotaError.sessionCookieMissing
        }
        return cookie
    }

    func savedSessionCookie() -> String {
        Self.normalizeCookie(keychainReader()) ?? ""
    }

    func saveSessionCookie(_ value: String) throws {
        let normalized = Self.normalizeCookie(value)
        try keychainWriter(normalized?.isEmpty == false ? normalized : nil)
    }

    private func loadData(from url: URL) -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func normalizeCookie(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value.removeFirst("cookie:".count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A Cookie request header must remain one line.
        guard !value.contains("\n"), !value.contains("\r") else { return nil }
        return value
    }

    private static func readKeychainCookie() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychainCookie(_ cookie: String?) throws {
        if let cookie {
            let data = Data(cookie.utf8)
            let updateStatus = SecItemUpdate(
                keychainQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )

            if updateStatus == errSecItemNotFound {
                var item = keychainQuery
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                    throw MiMoQuotaError.keychainWriteFailed
                }
            } else if updateStatus != errSecSuccess {
                throw MiMoQuotaError.keychainWriteFailed
            }
        } else {
            let status = SecItemDelete(keychainQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw MiMoQuotaError.keychainWriteFailed
            }
        }
    }

    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }
}

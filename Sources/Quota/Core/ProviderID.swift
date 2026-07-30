import Foundation

/// Stable machine identifier for a quota data source.
///
/// Providers own their user-facing names through `QuotaProvider.displayName`.
/// Keep this type open so adding a provider does not require editing core
/// architecture code just to add another enum case.
struct ProviderID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    static let codex = ProviderID(rawValue: "codex")
    static let grok = ProviderID(rawValue: "grok")
    static let claude = ProviderID(rawValue: "claude")
    static let mimo = ProviderID(rawValue: "mimo")
}

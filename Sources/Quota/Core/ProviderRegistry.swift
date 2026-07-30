import Foundation

/// Owns the list of available providers and is the single composition root.
///
/// ## Adding a provider
/// Implement `QuotaProvider`, then append an instance in `makeDefault(...)`.
/// Keep MenuBar / Touch Bar / notifications on `ProviderQuotaState` only so they
/// do not need edits for each new model.
final class ProviderRegistry {
    private(set) var providers: [any QuotaProvider]

    init(providers: [any QuotaProvider]) {
        self.providers = providers
    }

    var enabledProviders: [any QuotaProvider] {
        providers.filter(\.isEnabled)
    }

    var providerIDs: [ProviderID] {
        providers.map(\.id)
    }

    var settingsOptions: [ProviderSettingsOption] {
        providers.map { Self.settingsOption(for: $0) }
    }

    /// Enabled providers in the user's display order (popup tabs / refresh).
    func enabledProviders(configuration: ProviderSettingsConfiguration) -> [any QuotaProvider] {
        let orderedIDs = configuration.orderedEnabledIDs(availableIDs: providerIDs)
        return orderedIDs.compactMap { id in
            guard let provider = provider(id: id), provider.isEnabled else { return nil }
            return provider
        }
    }

    /// Primary provider = first enabled in order (leftmost tab; Touch Bar when available).
    func primaryProvider(configuration: ProviderSettingsConfiguration) -> (any QuotaProvider)? {
        enabledProviders(configuration: configuration).first
    }

    func provider(id: ProviderID) -> (any QuotaProvider)? {
        providers.first { $0.id == id }
    }

    func invalidateAllConnections() {
        for provider in providers {
            provider.invalidateConnection()
        }
    }

    func stopAll() {
        for provider in providers {
            provider.stop()
        }
    }

    static func settingsOption(for provider: any QuotaProvider) -> ProviderSettingsOption {
        ProviderSettingsOption(
            id: provider.id,
            displayName: provider.displayName,
            iconResourceName: provider.iconResourceName,
            tabIconResourceName: provider.tabIconResourceName,
            fallbackGlyph: provider.fallbackGlyph,
            accentColorHex: provider.accentColorHex
        )
    }

    /// App wiring. Register new providers here only.
    static func makeDefault(
        proxySettingsStore: ProxySettingsStore = .shared,
        appMetadata: AppMetadata = .current
    ) -> ProviderRegistry {
        let codex = CodexProvider(
            proxySettingsStore: proxySettingsStore,
            appMetadata: appMetadata
        )
        let grok = GrokProvider(proxySettingsStore: proxySettingsStore)
        let claude = ClaudeProvider(proxySettingsStore: proxySettingsStore)
        let mimo = MiMoProvider(proxySettingsStore: proxySettingsStore)
        return ProviderRegistry(providers: [codex, grok, claude, mimo])
    }
}

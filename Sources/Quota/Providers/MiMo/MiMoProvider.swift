import Foundation

/// Xiaomi MiMo provider: reads Token Plan credits for the MiMoCode account.
final class MiMoProvider: QuotaProvider {
    let id: ProviderID = .mimo
    let displayName = "MiMo"
    let iconResourceName: String? = "ProviderIconMiMo"
    let tabIconResourceName: String? = "TabIconMiMo"
    let fallbackGlyph = "Mi"
    let accentColorHex = "#FF6900"

    private let proxySettingsStore: ProxySettingsStore
    private var client: MiMoUsageClient

    init(proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = MiMoUsageClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }

    init(client: MiMoUsageClient, proxySettingsStore: ProxySettingsStore = .shared) {
        self.proxySettingsStore = proxySettingsStore
        self.client = client
    }

    func fetch(completion: @escaping (Result<ProviderQuotaState, Error>) -> Void) {
        client.fetchUsage { [displayName] result in
            switch result {
            case .success(let fetchResult):
                do {
                    let identity = ProviderIdentity(
                        displayName: displayName,
                        plan: fetchResult.detail?.displayPlanName
                    )
                    completion(.success(
                        try fetchResult.response.makeProviderState(
                            identity: identity,
                            resetsAt: fetchResult.detail?.resetDate(
                                timeZone: fetchResult.timeZone
                            )
                        )
                    ))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func stop() {}

    func invalidateConnection() {
        client = MiMoUsageClient(
            proxyConfiguration: proxySettingsStore.configuration
        )
    }
}

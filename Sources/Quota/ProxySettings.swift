import Foundation

enum ProxyMode: String, CaseIterable {
    case automatic
    case manual
    case disabled

    var displayTitle: String {
        switch self {
        case .automatic:
            return "自动"
        case .manual:
            return "手动"
        case .disabled:
            return "关闭"
        }
    }
}

struct ProxyConfiguration: Equatable {
    var mode: ProxyMode
    var proxyURL: String
}

final class ProxySettingsStore {
    static let shared = ProxySettingsStore()

    private let defaults: UserDefaults
    private let modeKey = "proxy.mode"
    private let proxyURLKey = "proxy.url"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: ProxyConfiguration {
        get {
            let mode = ProxyMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .automatic
            let proxyURL = defaults.string(forKey: proxyURLKey) ?? ""
            return ProxyConfiguration(mode: mode, proxyURL: proxyURL)
        }
        set {
            defaults.set(newValue.mode.rawValue, forKey: modeKey)
            defaults.set(newValue.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: proxyURLKey)
        }
    }
}

import CFNetwork
import Foundation

struct ProxyEnvironmentBuilder {
    private static let proxyEnvironmentKeys = [
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy"
    ]

    func build(configuration: ProxyConfiguration, baseEnvironment: [String: String]) -> [String: String] {
        var environment = baseEnvironment
        let proxyKeys = Self.proxyEnvironmentKeys

        switch configuration.mode {
        case .automatic:
            if !proxyKeys.contains(where: { environment[$0]?.isEmpty == false }) {
                let systemEnvironment = Self.systemProxyEnvironment()
                for (key, value) in systemEnvironment {
                    environment[key] = value
                }
            }
        case .manual:
            let proxyURL = configuration.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !proxyURL.isEmpty {
                Self.applyProxy(proxyURL, to: &environment)
            }
            // Clear any bypass list left by automatic mode.
            environment.removeValue(forKey: "NO_PROXY")
            environment.removeValue(forKey: "no_proxy")
        case .disabled:
            for key in proxyKeys {
                environment.removeValue(forKey: key)
            }
            // Force child processes to bypass all proxies.
            environment["NO_PROXY"] = "*"
            environment["no_proxy"] = "*"
        }

        return environment
    }

    private static func applyProxy(_ proxyURL: String, to environment: inout [String: String]) {
        for key in proxyEnvironmentKeys {
            if key.lowercased().contains("no_proxy") {
                continue
            }
            environment[key] = proxyURL
        }
    }

    private static func systemProxyEnvironment() -> [String: String] {
        guard let settingsUnmanaged = CFNetworkCopySystemProxySettings() else {
            return [:]
        }

        guard let settings = settingsUnmanaged.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        var environment: [String: String] = [:]

        if let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPPort as String] as? NSNumber,
           (settings[kCFNetworkProxiesHTTPEnable as String] as? NSNumber)?.intValue != 0 {
            applyHTTPProxy(host: host, port: port.intValue, into: &environment)
        }

        if let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPSPort as String] as? NSNumber,
           (settings[kCFNetworkProxiesHTTPSEnable as String] as? NSNumber)?.intValue != 0 {
            applyHTTPProxy(host: host, port: port.intValue, into: &environment)
        }

        if let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesSOCKSPort as String] as? NSNumber,
           (settings[kCFNetworkProxiesSOCKSEnable as String] as? NSNumber)?.intValue != 0 {
            applySOCKSProxy(host: host, port: port.intValue, into: &environment)
        }

        if let exceptions = settings[kCFNetworkProxiesExceptionsList as String] as? [String] {
            applyBypassList(exceptions, into: &environment)
        }

        if let excludeSimpleHostnames = settings[kCFNetworkProxiesExcludeSimpleHostnames as String] as? NSNumber,
           excludeSimpleHostnames.intValue != 0 {
            applyBypassList(["localhost", "127.0.0.1", "::1"], into: &environment)
        }

        return environment
    }

    private static func applyHTTPProxy(host: String, port: Int, into environment: inout [String: String]) {
        let proxyURL = "http://\(host):\(port)"
        environment["HTTP_PROXY"] = proxyURL
        environment["HTTPS_PROXY"] = proxyURL
        environment["ALL_PROXY"] = proxyURL
        environment["http_proxy"] = proxyURL
        environment["https_proxy"] = proxyURL
        environment["all_proxy"] = proxyURL
    }

    private static func applySOCKSProxy(host: String, port: Int, into environment: inout [String: String]) {
        let proxyURL = "socks5://\(host):\(port)"
        environment["HTTP_PROXY"] = proxyURL
        environment["HTTPS_PROXY"] = proxyURL
        environment["ALL_PROXY"] = proxyURL
        environment["http_proxy"] = proxyURL
        environment["https_proxy"] = proxyURL
        environment["all_proxy"] = proxyURL
    }

    private static func applyBypassList(_ hosts: [String], into environment: inout [String: String]) {
        let bypass = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")

        guard !bypass.isEmpty else { return }

        if let existing = environment["NO_PROXY"], !existing.isEmpty {
            environment["NO_PROXY"] = existing + "," + bypass
        } else {
            environment["NO_PROXY"] = bypass
        }

        if let existing = environment["no_proxy"], !existing.isEmpty {
            environment["no_proxy"] = existing + "," + bypass
        } else {
            environment["no_proxy"] = bypass
        }
    }
}

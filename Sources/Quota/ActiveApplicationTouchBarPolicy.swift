import AppKit

struct ActiveApplicationInfo: Equatable {
    var bundleIdentifier: String?
    var localizedName: String?
}

struct ActiveApplicationTouchBarPolicy {
    private let allowedBundleIdentifiers: Set<String>
    private let allowedApplicationNames: Set<String>

    init(
        allowedBundleIdentifiers: Set<String> = [
            "com.openai.codex",
            "com.apple.Terminal"
        ],
        allowedApplicationNames: Set<String> = [
            "Codex"
        ]
    ) {
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
        self.allowedApplicationNames = allowedApplicationNames
    }

    func shouldShow(for application: ActiveApplicationInfo) -> Bool {
        if let bundleIdentifier = application.bundleIdentifier,
           allowedBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if let localizedName = application.localizedName,
           allowedApplicationNames.contains(localizedName) {
            return true
        }

        return false
    }
}

import Foundation

struct AppMetadata {
    var name: String
    var version: String

    static let current = AppMetadata(bundle: .main)

    init(bundle: Bundle) {
        self.name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Quota"
        self.version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

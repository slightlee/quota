import Foundation

// MARK: - Wire types (Xiaomi MiMo Token Plan console API)

/// Decoded payload of `GET /api/v1/tokenPlan/usage`.
struct MiMoUsageResponse: Decodable {
    var code: Int
    var message: String?
    var data: MiMoUsageData?
}

struct MiMoUsageData: Decodable {
    var monthUsage: MiMoUsageGroup?
    var usage: MiMoUsageGroup?

    private enum CodingKeys: String, CodingKey {
        case monthUsage
        case monthUsageSnake = "month_usage"
        case usage
    }

    init(monthUsage: MiMoUsageGroup? = nil, usage: MiMoUsageGroup? = nil) {
        self.monthUsage = monthUsage
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monthUsage = try container.decodeIfPresent(MiMoUsageGroup.self, forKey: .monthUsage)
            ?? container.decodeIfPresent(MiMoUsageGroup.self, forKey: .monthUsageSnake)
        usage = try container.decodeIfPresent(MiMoUsageGroup.self, forKey: .usage)
    }
}

struct MiMoUsageGroup: Decodable {
    var items: [MiMoUsageItem]?
    var percent: Double?

    private enum CodingKeys: String, CodingKey {
        case items
        case percent
    }

    init(items: [MiMoUsageItem]? = nil, percent: Double? = nil) {
        self.items = items
        self.percent = percent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([MiMoUsageItem].self, forKey: .items)
        percent = container.decodeFlexibleDoubleIfPresent(forKey: .percent)
    }
}

struct MiMoUsageItem: Decodable {
    var name: String
    var used: Double
    var limit: Double
    var percent: Double?

    private enum CodingKeys: String, CodingKey {
        case name
        case used
        case limit
        case percent
    }

    init(name: String, used: Double, limit: Double, percent: Double? = nil) {
        self.name = name
        self.used = used
        self.limit = limit
        self.percent = percent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        used = container.decodeFlexibleDoubleIfPresent(forKey: .used) ?? 0
        limit = container.decodeFlexibleDoubleIfPresent(forKey: .limit) ?? 0
        percent = container.decodeFlexibleDoubleIfPresent(forKey: .percent)
    }
}

/// Decoded payload of `GET /api/v1/tokenPlan/detail`.
struct MiMoPlanDetailResponse: Decodable {
    var code: Int
    var message: String?
    var data: MiMoPlanDetail?
}

struct MiMoPlanDetail: Decodable {
    var planName: String?
    /// The console returns this in the timezone requested through `x-timezone`.
    /// Current live shape: `2026-08-24 23:59:59`.
    var currentPeriodEnd: String?

    func resetDate(timeZone: TimeZone = .current) -> Date? {
        guard let currentPeriodEnd else { return nil }

        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.timeZone = timeZone
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = localFormatter.date(from: currentPeriodEnd) {
            return date
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso8601.date(from: currentPeriodEnd)
            ?? ISO8601DateFormatter().date(from: currentPeriodEnd)
    }

    var displayPlanName: String? {
        let value = planName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

enum MiMoWindowID {
    static let tokenPlan = "token-plan"
}

// MARK: - Mapping -> ProviderQuotaState

extension MiMoUsageResponse {
    func makeProviderState(
        identity: ProviderIdentity,
        resetsAt: Date? = nil,
        now: Date = Date()
    ) throws -> ProviderQuotaState {
        guard code == 0 else {
            throw MiMoQuotaError.apiError(code, message)
        }

        let quotaNames: Set<String> = [
            "plan_total_token",
            "compensation_total_token",
        ]
        let quotaItems = (data?.usage?.items ?? []).filter {
            quotaNames.contains($0.name) && $0.limit > 0
        }
        guard !quotaItems.isEmpty else {
            throw MiMoQuotaError.missingQuotaData
        }

        let total = quotaItems.reduce(0) { $0 + max(0, $1.limit) }
        let used = quotaItems.reduce(0) {
            $0 + min(max(0, $1.used), max(0, $1.limit))
        }
        guard total > 0 else {
            throw MiMoQuotaError.missingQuotaData
        }

        let usedPercent = (used / total * 100).clamped(to: 0...100)
        let remaining = max(0, total - used)
        let window = QuotaWindow(
            id: MiMoWindowID.tokenPlan,
            title: L.mimoTokenPlanTitle,
            usedPercent: usedPercent,
            remainingPercent: (100 - usedPercent).clamped(to: 0...100),
            resetsAt: resetsAt,
            isAvailable: true
        )

        return ProviderQuotaState(
            providerID: .mimo,
            identity: identity,
            windows: [window],
            badges: [.text("\(Self.formatCredits(remaining)) Credits")],
            updatedAt: now,
            sourceLabel: "token-plan-console"
        )
    }

    private static func formatCredits(_ value: Double) -> String {
        let absolute = abs(value)
        let scaled: Double
        let suffix: String
        switch absolute {
        case 1_000_000_000...:
            scaled = value / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            scaled = value / 1_000_000
            suffix = "M"
        case 1_000...:
            scaled = value / 1_000
            suffix = "K"
        default:
            return String(Int(value.rounded()))
        }

        let formatted = scaled >= 100
            ? String(format: "%.0f", scaled)
            : String(format: "%.1f", scaled)
                .replacingOccurrences(of: ".0", with: "")
        return formatted + suffix
    }
}

// MARK: - Errors

enum MiMoQuotaError: LocalizedError {
    case mimoCodeNotSignedIn
    case invalidMiMoCodeAuth
    case sessionCookieMissing
    case unauthorized
    case invalidResponse
    case missingQuotaData
    case apiError(Int, String?)
    case requestFailed(Int)
    case keychainWriteFailed

    var errorDescription: String? {
        switch self {
        case .mimoCodeNotSignedIn:
            return L.mimoCodeNotSignedIn
        case .invalidMiMoCodeAuth:
            return L.mimoCodeInvalidAuth
        case .sessionCookieMissing:
            return L.mimoCookieMissing
        case .unauthorized:
            return L.mimoUnauthorized
        case .invalidResponse, .missingQuotaData:
            return L.invalidResponse
        case .apiError(let code, let message):
            let detail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return detail.isEmpty
                ? L.mimoRequestFailed(code)
                : "\(L.mimoRequestFailed(code)): \(detail)"
        case .requestFailed(let statusCode):
            return L.mimoRequestFailed(statusCode)
        case .keychainWriteFailed:
            return L.mimoKeychainWriteFailed
        }
    }
}

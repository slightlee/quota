import Foundation

struct RateLimitDisplayState: Equatable {
    var fiveHour: LimitWindowDisplay
    var weekly: LimitWindowDisplay
    var updatedAt: Date
}

struct LimitWindowDisplay: Equatable {
    var kind: LimitWindowKind
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?

    var title: String {
        switch kind {
        case .fiveHour:
            return L.fiveHourTitle
        case .weekly:
            return L.weeklyTitle
        }
    }

    var resetText: String {
        guard let resetsAt else {
            return "\(L.reset) --"
        }

        Self.resetFormatter.locale = L.locale
        return "\(L.reset) " + Self.resetFormatter.string(from: resetsAt)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

enum LimitWindowKind: Equatable {
    case fiveHour
    case weekly
}

struct GetAccountRateLimitsResponse: Decodable {
    var rateLimits: RateLimitSnapshot
}

struct AccountResponse: Decodable {
    var account: AccountInfo
}

struct AccountInfo: Decodable {
    var planType: String?
}

struct RateLimitSnapshot: Decodable {
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
}

struct RateLimitWindow: Decodable {
    var usedPercent: Double
    var windowDurationMins: Int?
    var resetsAt: TimeInterval?
}

extension GetAccountRateLimitsResponse {
    func displayState(now: Date = Date()) throws -> RateLimitDisplayState {
        guard let primary = rateLimits.primary, let secondary = rateLimits.secondary else {
            throw CodexQuotaError.missingRateLimitWindow
        }

        return RateLimitDisplayState(
            fiveHour: primary.display(kind: .fiveHour),
            weekly: secondary.display(kind: .weekly),
            updatedAt: now
        )
    }
}

private extension RateLimitWindow {
    func display(kind: LimitWindowKind) -> LimitWindowDisplay {
        let used = usedPercent.clamped(to: 0...100)
        return LimitWindowDisplay(
            kind: kind,
            usedPercent: used,
            remainingPercent: (100 - used).clamped(to: 0...100),
            resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum CodexQuotaError: LocalizedError {
    case codexBinaryMissing
    case missingRateLimitWindow
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .codexBinaryMissing:
            return L.codexBinaryMissing
        case .missingRateLimitWindow:
            return L.missingRateLimitWindow
        case .invalidResponse:
            return L.invalidResponse
        case .rpcError(let message):
            return message
        }
    }
}

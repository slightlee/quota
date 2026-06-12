import Foundation

struct RateLimitDisplayState: Equatable {
    var fiveHour: LimitWindowDisplay
    var weekly: LimitWindowDisplay
    var updatedAt: Date
}

struct LimitWindowDisplay: Equatable {
    var title: String
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?

    var resetText: String {
        guard let resetsAt else {
            return "重置 --"
        }

        return "重置 " + Self.resetFormatter.string(from: resetsAt)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
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
            fiveHour: primary.display(title: "5小时"),
            weekly: secondary.display(title: "周限额"),
            updatedAt: now
        )
    }
}

private extension RateLimitWindow {
    func display(title: String) -> LimitWindowDisplay {
        let used = usedPercent.clamped(to: 0...100)
        return LimitWindowDisplay(
            title: title,
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
            return "未找到 Codex 可执行文件"
        case .missingRateLimitWindow:
            return "额度响应缺少窗口数据"
        case .invalidResponse:
            return "无法解析 Codex 响应"
        case .rpcError(let message):
            return message
        }
    }
}

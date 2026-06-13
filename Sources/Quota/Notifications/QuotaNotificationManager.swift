import AppKit
import Foundation
import UserNotifications

// MARK: - 阈值定义

/// 通知阈值级别，按严重程度升序排列
private enum NotifyThreshold: Int, CaseIterable, Comparable {
    case warning = 0   // 20% — 轻度提醒
    case urgent = 1    // 10% — 紧急
    case critical = 2  //  5% — 严重

    var percent: Double {
        switch self {
        case .warning:  return 20
        case .urgent:   return 10
        case .critical: return 5
        }
    }

    var emoji: String {
        switch self {
        case .warning:  return "🟡"
        case .urgent:   return "🔴"
        case .critical: return "🔴"
        }
    }

    var usesAlert: Bool {
        self == .urgent || self == .critical
    }

    static func < (lhs: NotifyThreshold, rhs: NotifyThreshold) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 系统通知授权状态。
private enum NotificationAuthorizationState {
    case pending
    case authorized
    case denied
}

private struct PendingNotification {
    var content: UNMutableNotificationContent
    var fiveCrossed: [NotifyThreshold]
    var weeklyCrossed: [NotifyThreshold]
}

// MARK: - QuotaNotificationManager

/// 低配额通知管理器
///
/// 监听配额变化，在任一窗口跌破阈值时发送合并通知。
/// 每个阈值级别对每个窗口只通知一次，配额恢复后重置。
@MainActor
final class QuotaNotificationManager: RateLimitServiceObserver {
    /// 是否运行在 .app bundle 中（UNUserNotificationCenter 需要 bundle 环境）
    private let available: Bool
    private let center: UNUserNotificationCenter?
    /// 用户通知授权状态；首次安装启动时授权请求是异步完成的。
    private var authorizationState: NotificationAuthorizationState = .pending
    private var pendingNotification: PendingNotification?
    private var hasPromptedEnableNotifications = false

    /// 每个窗口已通知的最高阈值
    private var fiveHourNotified: NotifyThreshold?
    private var weeklyNotified: NotifyThreshold?

    private let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    init() {
        let isBundle = Bundle.main.bundleURL.pathExtension == "app"
        if isBundle {
            self.available = true
            self.center = UNUserNotificationCenter.current()
            requestAuthorization()
        } else {
            self.available = false
            self.center = nil
            debugLog("[Quota] notifications: running without bundle, will log to stderr")
        }
    }

    // MARK: - RateLimitServiceObserver

    func rateLimitService(_ service: RateLimitService, didUpdate state: RateLimitDisplayState) {
        debugLog("[Quota] notification manager received update")
        checkAndNotify(state: state)
    }

    func rateLimitService(_ service: RateLimitService, didFail error: Error, lastState: RateLimitDisplayState?) {
        // 通知失败时不处理，等待下次刷新
    }

    // MARK: - 通知逻辑

    private func checkAndNotify(state: RateLimitDisplayState) {
        let fiveRemaining = state.fiveHour.remainingPercent
        let weeklyRemaining = state.weekly.remainingPercent

        debugLog("[Quota] checkAndNotify: 5h=\(Int(fiveRemaining))%, weekly=\(Int(weeklyRemaining))%, authorization=\(authorizationState)")

        // 配额恢复检测：剩余超过 50% 说明已进入新窗口
        if fiveRemaining > 50 {
            fiveHourNotified = nil
        }
        if weeklyRemaining > 50 {
            weeklyNotified = nil
        }

        // 检查是否有新的阈值需要通知
        let fiveCrossed = findNewCrossedThresholds(remaining: fiveRemaining, notified: fiveHourNotified)
        let weeklyCrossed = findNewCrossedThresholds(remaining: weeklyRemaining, notified: weeklyNotified)

        debugLog("[Quota] thresholds crossed: 5h=\(fiveCrossed), weekly=\(weeklyCrossed), 5hNotified=\(String(describing: fiveHourNotified)), weeklyNotified=\(String(describing: weeklyNotified))")

        guard !fiveCrossed.isEmpty || !weeklyCrossed.isEmpty else {
            debugLog("[Quota] no new thresholds crossed, skip notification")
            return
        }

        // 确定通知严重程度（取两者中最紧急的）
        let maxThreshold = max(
            fiveCrossed.max() ?? .warning,
            weeklyCrossed.max() ?? .warning
        )

        // 构建并发送合并通知
        let content = buildNotificationContent(
            state: state,
            fiveCrossed: fiveCrossed,
            weeklyCrossed: weeklyCrossed,
            severity: maxThreshold
        )
        let pending = PendingNotification(
            content: content,
            fiveCrossed: fiveCrossed,
            weeklyCrossed: weeklyCrossed
        )

        debugLog("[Quota] scheduling notification: title=\(content.title)")
        scheduleNotification(pending) { [weak self] delivered in
            guard let self, delivered else { return }
            self.markDelivered(pending)
        }
    }

    /// 查找该窗口新跌破的阈值（从低到高扫描，返回所有新级别）
    private func findNewCrossedThresholds(remaining: Double, notified: NotifyThreshold?) -> [NotifyThreshold] {
        NotifyThreshold.allCases.filter { threshold in
            remaining < threshold.percent && (notified == nil || threshold > notified!)
        }
    }

    // MARK: - 构建通知内容

    private func buildNotificationContent(
        state: RateLimitDisplayState,
        fiveCrossed: [NotifyThreshold],
        weeklyCrossed: [NotifyThreshold],
        severity: NotifyThreshold
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        // 标题：突出最紧急的窗口
        content.title = buildTitle(
            fiveCrossed: fiveCrossed,
            weeklyCrossed: weeklyCrossed,
            severity: severity
        )

        // 正文：两个窗口的详细状态
        content.body = buildBody(
            state: state,
            fiveCrossed: fiveCrossed,
            weeklyCrossed: weeklyCrossed
        )

        // Alert 样式需要有 sound 才能弹窗
        if severity.usesAlert {
            content.sound = .default
        }

        return content
    }

    private func buildTitle(
        fiveCrossed: [NotifyThreshold],
        weeklyCrossed: [NotifyThreshold],
        severity: NotifyThreshold
    ) -> String {
        switch (fiveCrossed.isEmpty, weeklyCrossed.isEmpty) {
        case (false, true):
            return "\(severity.emoji) 5小时额度\(severityLabel(severity))！"
        case (true, false):
            return "\(severity.emoji) 周限额\(severityLabel(severity))！"
        default:
            return "\(severity.emoji) 额度\(severityLabel(severity))！"
        }
    }

    private func buildBody(
        state: RateLimitDisplayState,
        fiveCrossed: [NotifyThreshold],
        weeklyCrossed: [NotifyThreshold]
    ) -> String {
        let fivePercent = Int(state.fiveHour.remainingPercent.rounded())
        let weeklyPercent = Int(state.weekly.remainingPercent.rounded())
        let fiveMarker = fiveCrossed.isEmpty ? "" : " ⚠️"
        let weeklyMarker = weeklyCrossed.isEmpty ? "" : " ⚠️"
        let fiveReset = state.fiveHour.resetsAt.map { "  重置 \(resetFormatter.string(from: $0))" } ?? ""
        let weeklyReset = state.weekly.resetsAt.map { "  重置 \(resetFormatter.string(from: $0))" } ?? ""

        return "5小时 \(fivePercent)%\(fiveMarker)\(fiveReset)\n周限额 \(weeklyPercent)%\(weeklyMarker)\(weeklyReset)"
    }

    // MARK: - 辅助方法

    private func severityLabel(_ threshold: NotifyThreshold) -> String {
        switch threshold {
        case .warning:  return "偏低"
        case .urgent:   return "紧急"
        case .critical: return "严重不足"
        }
    }

    // MARK: - 发送通知

    private func scheduleNotification(
        _ pending: PendingNotification,
        completion: @escaping (Bool) -> Void
    ) {
        let content = pending.content

        if let center, authorizationState == .authorized {
            debugLog("[Quota] sending via UNUserNotificationCenter...")
            let request = UNNotificationRequest(
                identifier: "quota-low-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                Task { @MainActor in
                    if let error {
                        debugLog("[Quota] notification delivery error: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        debugLog("[Quota] notification delivered successfully")
                        completion(true)
                    }
                }
            }
        } else if available && authorizationState == .pending {
            debugLog("[Quota] notification authorization pending, defer delivery")
            pendingNotification = pending
            completion(false)
        } else if available {
            debugLog("[Quota] notification not authorized, rechecking system settings")
            recheckAuthorizationAndSchedule(pending, completion: completion)
        } else {
            debugLog("[Quota] ── 通知预览 ──")
            debugLog("[Quota] 标题: \(content.title)")
            debugLog("[Quota] 正文: \(content.body)")
            debugLog("[Quota] ────────────")
            completion(true)
        }
    }

    private func recheckAuthorizationAndSchedule(
        _ pending: PendingNotification,
        completion: @escaping (Bool) -> Void
    ) {
        guard let center else {
            promptEnableNotificationsIfNeeded()
            completion(false)
            return
        }

        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }

                self.authorizationState = Self.authorizationState(from: settings.authorizationStatus)
                debugLog("[Quota] notification authorization recheck: \(settings.authorizationStatus)")

                if self.authorizationState == .authorized {
                    self.scheduleNotification(pending, completion: completion)
                } else {
                    self.promptEnableNotificationsIfNeeded()
                    completion(false)
                }
            }
        }
    }

    private func deliverPendingNotificationIfNeeded() {
        guard let pendingNotification else { return }

        self.pendingNotification = nil
        debugLog("[Quota] delivering deferred notification: title=\(pendingNotification.content.title)")
        scheduleNotification(pendingNotification) { [weak self] delivered in
            guard let self, delivered else { return }
            self.markDelivered(pendingNotification)
        }
    }

    private func markDelivered(_ pending: PendingNotification) {
        if let highest = pending.fiveCrossed.max() {
            fiveHourNotified = highest
        }
        if let highest = pending.weeklyCrossed.max() {
            weeklyNotified = highest
        }
    }

    private static func authorizationState(from status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .pending
        @unknown default:
            return .denied
        }
    }

    private func requestAuthorization() {
        guard let center else { return }

        // 先检查当前授权状态，已拒绝过的不会再次弹出系统确认框
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    self.authorizationState = Self.authorizationState(from: settings.authorizationStatus)
                    self.deliverPendingNotificationIfNeeded()
                }
            case .denied:
                DispatchQueue.main.async {
                    self.authorizationState = Self.authorizationState(from: settings.authorizationStatus)
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                    DispatchQueue.main.async {
                        guard let self else { return }

                        if let error {
                            debugLog("[Quota] notification authorization error: \(error.localizedDescription)")
                        }

                        self.authorizationState = granted ? .authorized : .denied
                        debugLog("[Quota] notification authorization: \(granted ? "granted" : "denied")")

                        if granted {
                            self.deliverPendingNotificationIfNeeded()
                        }
                    }
                }
            @unknown default:
                DispatchQueue.main.async {
                    self.authorizationState = .denied
                }
            }
        }
    }

    private func promptEnableNotificationsIfNeeded() {
        guard !hasPromptedEnableNotifications else { return }
        hasPromptedEnableNotifications = true
        promptEnableNotifications()
    }

    /// 弹窗提示用户开启通知权限
    private func promptEnableNotifications() {
        let alert = NSAlert()
        alert.messageText = "需要通知权限"
        alert.informativeText = "Quota 需要发送通知来提醒你额度不足。\n请在系统设置中开启 Quota 的通知权限。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后设置")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

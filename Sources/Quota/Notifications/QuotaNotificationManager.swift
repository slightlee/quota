import AppKit
import Foundation
import UserNotifications

// MARK: - Threshold Definitions

/// Notification threshold levels ordered by severity.
private enum NotifyThreshold: Int, CaseIterable, Comparable {
    case warning = 0   // 20% — warning
    case urgent = 1    // 10% — urgent
    case critical = 2  //  5% — critical

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

/// System notification authorization state.
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

/// Low-quota notification manager.
///
/// Observes quota changes and sends one combined notification when either window
/// crosses a threshold. Each threshold is notified once per window and resets
/// after quota recovery.
@MainActor
final class QuotaNotificationManager: RateLimitServiceObserver {
    /// Whether the app is running inside a .app bundle required by UNUserNotificationCenter.
    private let available: Bool
    private let center: UNUserNotificationCenter?
    /// User notification authorization state; first-launch authorization is asynchronous.
    private var authorizationState: NotificationAuthorizationState = .pending
    private var pendingNotification: PendingNotification?
    private var hasPromptedEnableNotifications = false

    /// Highest notified threshold per quota window.
    private var fiveHourNotified: NotifyThreshold?
    private var weeklyNotified: NotifyThreshold?

    private let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
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
        // Ignore failures here and wait for the next refresh.
    }

    // MARK: - Notification Logic

    private func checkAndNotify(state: RateLimitDisplayState) {
        let fiveRemaining = state.fiveHour.remainingPercent
        let weeklyRemaining = state.weekly.remainingPercent

        debugLog("[Quota] checkAndNotify: 5h=\(Int(fiveRemaining))%, weekly=\(Int(weeklyRemaining))%, authorization=\(authorizationState)")

        // Treat remaining quota above 50% as a new quota window.
        if fiveRemaining > 50 {
            fiveHourNotified = nil
        }
        if weeklyRemaining > 50 {
            weeklyNotified = nil
        }

        // Check whether new thresholds need notification.
        let fiveCrossed = findNewCrossedThresholds(remaining: fiveRemaining, notified: fiveHourNotified)
        let weeklyCrossed = findNewCrossedThresholds(remaining: weeklyRemaining, notified: weeklyNotified)

        debugLog("[Quota] thresholds crossed: 5h=\(fiveCrossed), weekly=\(weeklyCrossed), 5hNotified=\(String(describing: fiveHourNotified)), weeklyNotified=\(String(describing: weeklyNotified))")

        guard !fiveCrossed.isEmpty || !weeklyCrossed.isEmpty else {
            debugLog("[Quota] no new thresholds crossed, skip notification")
            return
        }

        // Use the most severe threshold crossed by either window.
        let maxThreshold = max(
            fiveCrossed.max() ?? .warning,
            weeklyCrossed.max() ?? .warning
        )

        // Build and send one combined notification.
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

    /// Finds newly crossed thresholds for a quota window.
    private func findNewCrossedThresholds(remaining: Double, notified: NotifyThreshold?) -> [NotifyThreshold] {
        NotifyThreshold.allCases.filter { threshold in
            remaining < threshold.percent && (notified == nil || threshold > notified!)
        }
    }

    // MARK: - Notification Content

    private func buildNotificationContent(
        state: RateLimitDisplayState,
        fiveCrossed: [NotifyThreshold],
        weeklyCrossed: [NotifyThreshold],
        severity: NotifyThreshold
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        // Title highlights the most urgent quota window.
        content.title = buildTitle(
            fiveCrossed: fiveCrossed,
            weeklyCrossed: weeklyCrossed,
            severity: severity
        )

        // Body includes detailed status for both quota windows.
        content.body = buildBody(
            state: state,
            fiveCrossed: fiveCrossed,
            weeklyCrossed: weeklyCrossed
        )

        // Alert-style notifications need a sound to pop up.
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
        L.lowQuotaTitle(
            fiveCrossed: !fiveCrossed.isEmpty,
            weeklyCrossed: !weeklyCrossed.isEmpty,
            severity: severityLabel(severity),
            emoji: severity.emoji
        )
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
        resetFormatter.locale = L.locale
        let fiveReset = state.fiveHour.resetsAt.map { "  \(L.reset) \(resetFormatter.string(from: $0))" } ?? ""
        let weeklyReset = state.weekly.resetsAt.map { "  \(L.reset) \(resetFormatter.string(from: $0))" } ?? ""

        return "\(L.fiveHourTitle) \(fivePercent)%\(fiveMarker)\(fiveReset)\n\(L.weeklyTitle) \(weeklyPercent)%\(weeklyMarker)\(weeklyReset)"
    }

    // MARK: - Helpers

    private func severityLabel(_ threshold: NotifyThreshold) -> String {
        switch threshold {
        case .warning:
            return L.severityWarning
        case .urgent:
            return L.severityUrgent
        case .critical:
            return L.severityCritical
        }
    }

    // MARK: - Delivery

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
            debugLog("[Quota] ── notification preview ──")
            debugLog("[Quota] title: \(content.title)")
            debugLog("[Quota] body: \(content.body)")
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

        // Check current authorization first; denied apps cannot show the system prompt again.
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

    /// Prompts the user to enable notification permission.
    private func promptEnableNotifications() {
        let alert = NSAlert()
        alert.messageText = L.notificationPermissionTitle
        alert.informativeText = L.notificationPermissionMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.openSystemSettings)
        alert.addButton(withTitle: L.later)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

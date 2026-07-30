import Foundation
import Testing
@testable import Quota

private let sampleMiMoUsageJSON = """
{
  "code": 0,
  "data": {
    "usage": {
      "percent": 25,
      "items": [
        {
          "name": "plan_total_token",
          "used": 1000000000,
          "limit": 4100000000,
          "percent": 24.39
        },
        {
          "name": "compensation_total_token",
          "used": 100000000,
          "limit": 300000000,
          "percent": 33.33
        }
      ]
    },
    "monthUsage": {
      "items": [
        {
          "name": "month_total_token",
          "used": 1100000000,
          "limit": 4400000000,
          "percent": 25
        }
      ]
    }
  }
}
"""

@Test func decodesAndMapsMiMoTokenPlanCredits() throws {
    let response = try JSONDecoder().decode(
        MiMoUsageResponse.self,
        from: Data(sampleMiMoUsageJSON.utf8)
    )

    let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    let detail = MiMoPlanDetail(
        planName: "Lite",
        currentPeriodEnd: "2026-08-24 23:59:59"
    )
    let reset = try #require(detail.resetDate(timeZone: timeZone))
    let state = try response.makeProviderState(
        identity: ProviderIdentity(displayName: "MiMo", plan: "Token Plan"),
        resetsAt: reset,
        now: Date(timeIntervalSince1970: 10)
    )

    #expect(state.providerID == ProviderID.mimo)
    #expect(state.identity.plan == "Token Plan")
    #expect(state.windows.count == 1)
    #expect(state.windows[0].id == MiMoWindowID.tokenPlan)
    #expect(abs(state.windows[0].usedPercent - 25) < 0.0001)
    #expect(abs(state.windows[0].remainingPercent - 75) < 0.0001)
    #expect(state.windows[0].resetsAt == reset)
    #expect(state.badges == [.text("3.3B Credits")])
    #expect(state.sourceLabel == "token-plan-console")
}

@Test func decodesMiMoPlanDetailResetInRequestedTimezone() throws {
    let json = """
    {
      "code": 0,
      "message": "",
      "data": {
        "planName": "Lite Monthly",
        "currentPeriodEnd": "2026-08-24 23:59:59"
      }
    }
    """
    let response = try JSONDecoder().decode(
        MiMoPlanDetailResponse.self,
        from: Data(json.utf8)
    )
    let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    let date = try #require(response.data?.resetDate(timeZone: timeZone))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: date
    )

    #expect(response.data?.displayPlanName == "Lite Monthly")
    #expect(components.year == 2026)
    #expect(components.month == 8)
    #expect(components.day == 24)
    #expect(components.hour == 23)
    #expect(components.minute == 59)
    #expect(components.second == 59)
}

@Test func ignoresUnrelatedMiMoUsageRows() throws {
    let response = MiMoUsageResponse(
        code: 0,
        message: nil,
        data: MiMoUsageData(
            usage: MiMoUsageGroup(
                items: [
                    MiMoUsageItem(
                        name: "month_total_token",
                        used: 99,
                        limit: 100,
                        percent: 99
                    ),
                    MiMoUsageItem(
                        name: "plan_total_token",
                        used: 20,
                        limit: 100,
                        percent: 20
                    ),
                ],
                percent: nil
            )
        )
    )

    let state = try response.makeProviderState(
        identity: ProviderIdentity(displayName: "MiMo", plan: nil)
    )
    #expect(state.windows[0].usedPercent == 20)
    #expect(state.windows[0].remainingPercent == 80)
}

@Test func throwsWhenMiMoQuotaRowsAreMissing() {
    let response = MiMoUsageResponse(
        code: 0,
        message: nil,
        data: MiMoUsageData(usage: MiMoUsageGroup(items: [], percent: nil))
    )

    #expect(throws: MiMoQuotaError.self) {
        _ = try response.makeProviderState(
            identity: ProviderIdentity(displayName: "MiMo", plan: nil)
        )
    }
}

@Test func readsMiMoCodeXiaomiAccountAndNormalizesCookie() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-mimo-auth-\(UUID().uuidString)")
    let authDirectory = home.appendingPathComponent(".local/share/mimocode")
    try FileManager.default.createDirectory(
        at: authDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: home) }

    let payload = """
    {
      "xiaomi": {
        "type": "api",
        "key": "tp-test",
        "metadata": {
          "uid": "test-user",
          "base_url": "https://token-plan-sgp.xiaomimimo.com/v1"
        }
      }
    }
    """
    try Data(payload.utf8).write(to: authDirectory.appendingPathComponent("auth.json"))

    let store = MiMoAuthStore(
        homeDirectory: home,
        environment: ["XIAOMI_MIMO_SESSION_COOKIE": " Cookie: a=1; b=2 "],
        keychainReader: { nil },
        keychainWriter: { _ in }
    )

    let account = try store.loadMiMoCodeAccount()
    #expect(account.baseURL.absoluteString == "https://token-plan-sgp.xiaomimimo.com/v1")
    #expect(try store.loadSessionCookie() == "a=1; b=2")
}

@Test func MiMoCookieFallsBackToKeychain() throws {
    let store = MiMoAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: [:],
        keychainReader: { "session=from-keychain" },
        keychainWriter: { _ in }
    )
    #expect(try store.loadSessionCookie() == "session=from-keychain")
    #expect(store.savedSessionCookie() == "session=from-keychain")
}

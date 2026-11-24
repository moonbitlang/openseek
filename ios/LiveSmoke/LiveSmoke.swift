import XCTest

final class LiveSmoke: XCTestCase {
    @MainActor func testHostedConsoleOpensSystemSignInAndCanRetryAfterCancel() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.moonbit.seekmoon.ios.prototype")
        app.launch()
        let login = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Sign in", "登录", "登入"])).firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 100), "Use a signed-out simulator with access to SeekMoon")
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            login.tap()
            let alert = system.alerts.firstMatch.waitForExistence(timeout: 6) ? system.alerts.firstMatch : app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "Expected a system authentication prompt")
            XCTAssertTrue(alert.label.localizedCaseInsensitiveContains("moonbitlang.com"), alert.label)
            let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
            XCTAssertTrue(cancel.exists); cancel.tap()
            XCTAssertTrue(login.waitForExistence(timeout: 50))
        }
    }
}

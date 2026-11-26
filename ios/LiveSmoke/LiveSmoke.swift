import XCTest

final class LiveSmoke: XCTestCase {
    @MainActor func testChatKeyboardKeepsHeaderAndRestoresComposer() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.moonbit.seekmoon.ios.prototype")
        app.launch()
        let editor = app.webViews.textViews.firstMatch
        let login = app.buttons["welcome.github"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in editor.exists || login.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 100), .completed)
        if login.exists { throw XCTSkip("The keyboard scenario needs a signed-in chat.") }
        let header = app.buttons["navigation.open"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let headerY = header.frame.midY
        let restingY = editor.frame.midY
        let draft = editor.value as? String
        for _ in 0..<3 {
            editor.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let tutorial = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Speed up your typing")).firstMatch
            if tutorial.exists { app.buttons["Continue"].tap() }
            XCTAssertEqual(header.frame.midY, headerY, accuracy: 2)
            XCTAssertLessThan(editor.frame.midY, restingY - 100)
            let done = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier == %@",
                ["Done", "完成", "Dismiss keyboard", "Hide keyboard", "收起键盘"], "Done")).firstMatch
            XCTAssertTrue(done.exists, app.toolbars.debugDescription)
            XCTAssertLessThan(done.frame.midY - editor.frame.midY, 140)
            XCTAssertLessThan(editor.frame.midY, done.frame.midY)
            keepScreenshot(app, name: "Keyboard open")
            done.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertEqual(app.webViews.textViews.count, 1)
            XCTAssertEqual(header.frame.midY, headerY, accuracy: 2)
            XCTAssertEqual(editor.frame.midY, restingY, accuracy: 2)
            XCTAssertEqual(editor.value as? String, draft)
        }
        keepScreenshot(app, name: "Keyboard dismissed")
    }

    @MainActor func testHostedConsoleEntry() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.moonbit.seekmoon.ios.prototype")
        app.launch()
        let login = app.buttons["welcome.github"]
        let navigation = app.buttons["navigation.open"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            login.exists || navigation.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 100), .completed)
        if login.exists {
            verifySignIn(app)
        } else {
            verifyNavigation(app, navigation: navigation)
        }
    }

    @MainActor private func verifySignIn(_ app: XCUIApplication) {
        keepScreenshot(app, name: "Welcome")
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for login in [app.buttons["welcome.email"], app.buttons["welcome.github"]] {
            XCTAssertTrue(login.exists)
            login.tap()
            let alert = system.alerts.firstMatch.waitForExistence(timeout: 6) ? system.alerts.firstMatch : app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "Expected a system authentication prompt")
            XCTAssertTrue(alert.label.localizedCaseInsensitiveContains("moonbitlang.com"), alert.label)
            let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
            XCTAssertTrue(cancel.exists); cancel.tap()
            XCTAssertTrue(login.waitForExistence(timeout: 50))
        }
    }

    @MainActor private func verifyNavigation(_ app: XCUIApplication, navigation: XCUIElement) {
        let close = app.buttons["navigation.close"]
        let newChat = app.buttons["navigation.newCloud"]
        keepScreenshot(app, name: "Chat menu")
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let attach = app.webViews.buttons.matching(NSPredicate(format: "label IN %@",
            ["Attach files", "添加附件", "Attach images", "添加图片"])).firstMatch
        if attach.exists {
            attach.tap()
            let choice = app.buttons.matching(NSPredicate(format: "label IN %@",
                ["Photo Library", "Choose File", "Choose Files", "照片图库", "照片图书馆", "选取文件", "选择文件"])).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 6))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.30)).tap()
            XCTAssertTrue(choice.waitForNonExistence(timeout: 5))
        }
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        keepScreenshot(app, name: "Composer with keyboard")
        navigation.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(newChat.exists)
        XCTAssertFalse(app.buttons["navigation.manage"].exists)
        XCTAssertEqual(close.frame.midX, app.frame.width * 0.55 - 24, accuracy: 3)
        keepScreenshot(app, name: "Left sidebar")
        let importChat = app.buttons["navigation.importCloud"]
        let workspaces = app.buttons["navigation.workspaces"]
        XCTAssertTrue(importChat.isEnabled)
        XCTAssertGreaterThan(importChat.frame.midY, newChat.frame.midY)
        XCTAssertLessThan(importChat.frame.midY, workspaces.frame.midY)
        importChat.tap()
        let json = app.webViews.buttons.matching(NSPredicate(format: "label IN %@", ["Import JSON file", "导入 JSON 文件"])).firstMatch
        let link = app.webViews.textFields.firstMatch
        XCTAssertTrue(json.waitForExistence(timeout: 6))
        XCTAssertTrue(link.isHittable)
        XCTAssertFalse(navigation.isHittable)
        keepScreenshot(app, name: "Cloud import")
        link.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(link.isHittable)
        XCTAssertLessThanOrEqual(link.frame.maxY, app.keyboards.firstMatch.frame.minY)
        keepScreenshot(app, name: "Cloud link keyboard")
        let closeImport = app.webViews.buttons.matching(NSPredicate(format: "label IN %@",
            ["Close imported history", "关闭导入历史", "Close", "关闭"])).firstMatch
        closeImport.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        navigation.tap()
        app.buttons["navigation.workspaces"].tap()
        XCTAssertTrue(newChat.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.46)).tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.006, dy: 0.46))
        let inside = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.46))
        edge.press(forDuration: 0.08, thenDragTo: inside)
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        inside.press(forDuration: 0.08, thenDragTo: edge)
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))

        navigation.tap()
        let filter = app.textFields["navigation.search"]
        filter.tap()
        filter.typeText("qzxv-58927")
        XCTAssertFalse(newChat.exists)
        let empty = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["No matching conversations.", "没有匹配的对话。"])).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        let clear = app.buttons.matching(NSPredicate(format: "label IN %@", ["Clear search", "清除搜索"])).firstMatch
        clear.tap()
        let chat = app.buttons.matching(identifier: "navigation.recentChat").firstMatch
        if chat.exists {
            let prefix = chat.label.prefix(while: { $0.isASCII && $0.isLetter }).prefix(4)
            if !prefix.isEmpty {
                filter.typeText(String(prefix))
                XCTAssertTrue(chat.waitForExistence(timeout: 5))
            }
            chat.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            XCTAssertTrue(navigation.waitForExistence(timeout: 10))
            navigation.press(forDuration: 0.8)
            let export = app.buttons.matching(NSPredicate(format: "label IN %@", ["Export", "Export conversation", "导出", "导出对话"])).firstMatch
            XCTAssertTrue(export.waitForExistence(timeout: 5))
            keepScreenshot(app, name: "Conversation actions")
            export.tap()
            let dismiss = app.webViews.buttons.matching(NSPredicate(format: "label IN %@",
                ["Close export dialog", "关闭导出对话框", "Close", "关闭"])).firstMatch
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            dismiss.tap()
            XCTAssertTrue(navigation.waitForExistence(timeout: 5))
            edge.press(forDuration: 0.08, thenDragTo: inside)
            XCTAssertTrue(close.waitForExistence(timeout: 5))
        }
        let gear = app.buttons["navigation.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        let download = app.buttons.matching(NSPredicate(format: "label IN %@", ["Download apps", "下载客户端"])).firstMatch
        XCTAssertFalse(download.exists)
        let identity = app.staticTexts["navigation.account"]
        XCTAssertTrue(identity.exists)
        let name = identity.label
        identity.tap()
        XCTAssertTrue(gear.isHittable)
        XCTAssertFalse(app.buttons["navigation.account"].exists)
        gear.tap()
        let home = app.buttons["settings.close"]
        let account = app.buttons["settings-tab-account"]
        let general = app.buttons["settings-tab-general"]
        XCTAssertTrue(home.waitForExistence(timeout: 6))
        XCTAssertTrue(account.isHittable && general.isHittable)
        XCTAssertTrue(account.label.contains(name))
        XCTAssertLessThan(account.frame.midY, general.frame.midY)
        let improve = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Help improve SeekMoon", "帮助改进 SeekMoon"])).firstMatch
        XCTAssertTrue(improve.waitForExistence(timeout: 8))
        keepScreenshot(app, name: "Unified settings")

        func back() {
            let button = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(button.isHittable)
            button.tap()
        }
        account.tap()
        let logout = app.buttons.matching(NSPredicate(format: "label IN %@", ["Sign out", "退出登录"])).firstMatch
        XCTAssertTrue(logout.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["settings.sections"].exists)
        keepScreenshot(app, name: "Account")
        back()
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.tap()
        let theme = app.buttons["settings.control.theme-select"]
        XCTAssertTrue(theme.waitForExistence(timeout: 6))
        keepScreenshot(app, name: "General")
        theme.tap()
        XCTAssertTrue(theme.waitForNonExistence(timeout: 5))
        back()
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        back()
        app.buttons["settings-tab-devices"].tap()
        let refresh = app.buttons.matching(NSPredicate(format: "label IN %@", ["Refresh", "刷新"])).firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 8))
        refresh.tap()
        keepScreenshot(app, name: "Devices")
        back()
        app.buttons["settings-tab-archived-chats"].tap()
        let archives = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@",
            "archived conversation", "已归档")).firstMatch
        XCTAssertTrue(archives.waitForExistence(timeout: 8))
        keepScreenshot(app, name: "Archive")
        back()
        XCTAssertTrue(account.waitForExistence(timeout: 8))
        home.tap()
        XCTAssertTrue(navigation.waitForExistence(timeout: 8))
        XCTAssertTrue(editor.exists)
        navigation.tap()

        let skills = app.buttons["navigation.skills"]
        XCTAssertTrue(skills.waitForExistence(timeout: 5))
        skills.tap()
        let closeSkills = app.buttons["skills.close"]
        XCTAssertTrue(closeSkills.waitForExistence(timeout: 8))
        closeSkills.tap()
        navigation.tap()

        XCTAssertFalse(app.buttons["navigation.manage"].exists)
        newChat.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let status = app.webViews.staticTexts.matching(NSPredicate(format: "label IN %@", ["Ready", "就绪", "New chat", "新建对话"]))
        XCTAssertEqual(status.count, 0)
        keepScreenshot(app, name: "Minimal chat header")
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    }

    @MainActor func testSkillsFromNewChat() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.moonbit.seekmoon.ios.prototype")
        app.launch()
        let navigation = app.buttons["navigation.open"]
        let login = app.buttons["welcome.github"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in navigation.exists || login.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 100), .completed)
        if login.exists { throw XCTSkip("The skills catalog needs a signed-in chat.") }
        navigation.tap()
        app.buttons["navigation.newCloud"].tap()
        let greeting = app.webViews.staticTexts.matching(NSPredicate(format: "label IN %@", ["欢迎回来", "Welcome back"])).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 8))
        XCTAssertEqual(greeting.frame.midY, app.frame.midY, accuracy: app.frame.height * 0.08)
        keepScreenshot(app, name: "Chat greeting")

        navigation.tap()
        app.buttons["navigation.skills"].tap()
        let close = app.buttons["skills.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["skills.refresh"].exists)
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.exists)
        let catalog = app.webViews.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Discover", "发现")).firstMatch
        let firstSkill = catalog.buttons.firstMatch
        XCTAssertTrue(firstSkill.waitForExistence(timeout: 60))
        let name = firstSkill.label
        keepScreenshot(app, name: "Skills catalog")
        tabs.buttons.element(boundBy: 1).tap()
        let installed = app.webViews.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Installed", "已安装")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout: 8))
        tabs.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(firstSkill.waitForExistence(timeout: 8))
        let search = app.webViews.descendants(matching: .any).matching(NSPredicate(
            format: "(elementType == %d OR elementType == %d) AND (label CONTAINS[c] %@ OR label CONTAINS %@)",
            XCUIElement.ElementType.searchField.rawValue, XCUIElement.ElementType.textField.rawValue, "Search", "搜索")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name)
        let skill = catalog.buttons.matching(identifier: name).firstMatch
        XCTAssertTrue(skill.waitForExistence(timeout: 10))
        skill.tap()
        XCTAssertTrue(tabs.waitForNonExistence(timeout: 5))
        keepScreenshot(app, name: "Skill detail")
        close.tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    }

    @MainActor private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

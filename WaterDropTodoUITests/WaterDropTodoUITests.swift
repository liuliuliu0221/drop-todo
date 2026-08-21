//
//  WaterDropTodoUITests.swift
//  WaterDropTodoUITests
//
//  Created by 羽 on 2026/8/19.
//

import XCTest

final class WaterDropTodoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    @MainActor
    func testExample() throws {
        let app = launchApp()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testListRowTransitionReachesScreenBottom() throws {
#if DEBUG
        let app = launchApp()

        let button = app.buttons["transition.list"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        if !button.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        button.tap()

        let status = app.descendants(matching: .any)
            .matching(identifier: "transition.status")
            .firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        let completed = NSPredicate(format: "label BEGINSWITH %@", "完成：SwiftUI 列表行")
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: completed, object: status)],
            timeout: 5
        )
        XCTAssertEqual(result, .completed, "实际状态：\(status.label)")
        XCTAssertTrue(status.label.contains("落点误差="))
#else
        throw XCTSkip("Release 构建不包含跨窗口动画调试入口；该路径由 Debug + Address Sanitizer 专项覆盖。")
#endif
    }

    @MainActor
    func testQuickCaptureKeepsInputOnValidationFailure() throws {
        let app = launchApp(usesDefaultDeadline: false)
        app.buttons["main.newTask"].tap()

        let title = app.textFields["quickCapture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("保留这段输入")
        app.buttons["quickCapture.save"].tap()

        XCTAssertTrue(app.staticTexts["quickCapture.error"].waitForExistence(timeout: 2))
        XCTAssertEqual(title.value as? String, "保留这段输入")
        app.buttons["取消"].click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testQuickCapturePersistsThenCloses() throws {
        let app = launchApp()
        app.buttons["main.newTask"].tap()

        let title = app.textFields["quickCapture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText("UI 创建任务")

        app.buttons["quickCapture.save"].tap()

        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["UI 创建任务"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOptionTOpensSingleQuickCapturePanel() throws {
        let app = launchApp()

        app.typeKey("t", modifierFlags: .option)
        let title = app.textFields["quickCapture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))

        app.typeKey("t", modifierFlags: .option)
        XCTAssertEqual(
            app.textFields.matching(identifier: "quickCapture.title").count,
            1
        )
    }

    @MainActor
    func testQuickCapturePresentationP95IsWithinBudget() throws {
        let app = launchApp(extraArguments: ["--ui-testing-performance"])
        var samples: [Double] = []

        for _ in 0..<20 {
            app.typeKey("t", modifierFlags: .option)
            let latency = app.staticTexts["quickCapture.latency"]
            XCTAssertTrue(latency.waitForExistence(timeout: 2))
            let rawValue = (latency.value as? String) ?? latency.label
            guard let milliseconds = Double(rawValue) else {
                XCTFail("无法解析快速创建延迟：label=\(latency.label) value=\(String(describing: latency.value))")
                return
            }
            samples.append(milliseconds)

            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(latency.waitForNonExistence(timeout: 2))
        }

        let ordered = samples.sorted()
        let percentileIndex = max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)
        let p95 = ordered[percentileIndex]
        let attachment = XCTAttachment(
            string: "samples_ms=\(samples)\np95_ms=\(p95)"
        )
        attachment.name = "Quick Capture Presentation Latency"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(p95, 300, "⌥T 到输入就绪 P95=\(p95)ms")
    }

    @MainActor
    func testEditCompleteAndClearCompletedHistory() throws {
        let app = launchApp()
        createTask(named: "等待编辑", in: app)

        app.buttons["编辑"].firstMatch.tap()
        let editTitle = app.textFields["edit.title"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 3))
        editTitle.click()
        editTitle.typeKey("a", modifierFlags: .command)
        editTitle.typeText("编辑后任务")
        app.buttons["edit.save"].tap()

        XCTAssertTrue(app.staticTexts["编辑后任务"].waitForExistence(timeout: 3))
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["编辑后任务"].waitForNonExistence(timeout: 3))

        app.radioButtons["已完成"].tap()
        XCTAssertTrue(app.staticTexts["编辑后任务"].waitForExistence(timeout: 3))
        app.buttons["tasks.clearCompleted"].tap()
        let confirmClear = app.buttons["tasks.confirmClearCompleted"]
        XCTAssertTrue(confirmClear.waitForExistence(timeout: 2))
        confirmClear.tap()
        XCTAssertTrue(app.staticTexts["编辑后任务"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testCompletionBuildsGardenAndClearingHistoryKeepsIt() throws {
        let app = launchApp()
        createTask(named: "种下一片草", in: app)

        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["种下一片草"].waitForNonExistence(timeout: 3))
        app.radioButtons["已完成"].tap()
        app.buttons["tasks.clearCompleted"].tap()
        XCTAssertTrue(app.buttons["tasks.confirmClearCompleted"].waitForExistence(timeout: 2))
        app.buttons["tasks.confirmClearCompleted"].tap()

        app.buttons["设置"].tap()
        let gardenTotal = app.descendants(matching: .any)["settings.garden.total"]
        XCTAssertTrue(gardenTotal.waitForExistence(timeout: 3))
        XCTAssertEqual(gardenTotal.label, "花园完成积累 1")
        XCTAssertFalse(app.buttons["settings.aquarium.toggle"].exists)
        XCTAssertFalse(app.buttons["settings.aquarium.adjust"].exists)
    }

    @MainActor
    func testCancelRequiresConfirmation() throws {
        let app = launchApp()
        createTask(named: "等待取消", in: app)

        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["等待取消"].exists)
        let confirmCancel = app.buttons["确认取消"]
        XCTAssertTrue(confirmCancel.waitForExistence(timeout: 2))
        confirmCancel.tap()
        XCTAssertTrue(app.staticTexts["等待取消"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testTaskSurvivesApplicationRelaunch() throws {
        let storeID = "WaterDropTodo-UITests-Relaunch-\(UUID().uuidString)"
        var app = launchApp(storeID: storeID)
        createTask(named: "重启后仍存在", in: app)
        app.terminate()

        app = launchApp(storeID: storeID)
        XCTAssertTrue(app.staticTexts["重启后仍存在"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRuinedTaskCanBeRecalledAfterTenConsecutiveClicks() throws {
        let app = launchApp(extraArguments: ["--ui-testing-seed-ruin"])
        app.radioButtons["时间废墟"].click()
        let title = app.staticTexts["稳定性测试废墟"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))

        let recall = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "召回 稳定性测试废墟")
        ).firstMatch
        XCTAssertTrue(recall.waitForExistence(timeout: 2))
        for _ in 0..<10 { recall.click() }

        let preset = app.buttons["30 分钟后"]
        XCTAssertTrue(preset.waitForExistence(timeout: 2))
        preset.click()
        app.buttons["ruins.confirmRecall"].click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))

        app.radioButtons["进行中"].click()
        XCTAssertTrue(app.staticTexts["稳定性测试废墟"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testBurnRequiresConfirmationAndRemovesOnlyRuin() throws {
        let app = launchApp(extraArguments: ["--ui-testing-seed-ruin"])
        app.radioButtons["时间废墟"].click()
        let title = app.staticTexts["稳定性测试废墟"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))

        app.buttons["焚毁"].click()
        let confirm = app.buttons["ruins.confirmBurn"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
    }

    @MainActor
    private func launchApp(
        storeID: String = "WaterDropTodo-UITests-\(UUID().uuidString)",
        extraArguments: [String] = [],
        usesDefaultDeadline: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // Explicitly terminate the previous process before assigning this test's
        // isolated store. This also disposes auxiliary NSPanel accessibility state.
        app.terminate()
        app.launchArguments.append("--skip-device-gate")
        app.launchArguments.append("--ui-testing")
        app.launchArguments.append("--ui-testing-store=\(storeID)")
        if usesDefaultDeadline {
            app.launchArguments.append("--ui-testing-default-deadline")
        }
        app.launchArguments.append(contentsOf: extraArguments)
        app.launch()
        XCTAssertTrue(app.windows["水滴待办"].waitForExistence(timeout: 3))
        let newTaskButton = app.buttons["main.newTask"]
        XCTAssertTrue(newTaskButton.waitForExistence(timeout: 3))
        let ready = NSPredicate(format: "enabled == true")
        let readyResult = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: ready, object: newTaskButton)],
            timeout: 3
        )
        XCTAssertEqual(readyResult, .completed, "任务系统未在预期时间内就绪")
        return app
    }

    @MainActor
    private func createTask(named name: String, in app: XCUIApplication) {
        app.buttons["main.newTask"].tap()
        let title = app.textFields["quickCapture.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.click()
        title.typeText(name)
        app.buttons["quickCapture.save"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 3))
    }

}

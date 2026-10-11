import XCTest

@MainActor
final class Salle215UITests: XCTestCase {
    private var app: XCUIApplication!

    func testCaptureWebsiteScreens() throws {
        guard let output = ProcessInfo.processInfo.environment["WEBSITE_SCREENSHOTS"] else {
            throw XCTSkip("Set WEBSITE_SCREENSHOTS to refresh the website images")
        }
        func capture(_ name: String) throws {
            try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        launch(["--demo", "-AppleInterfaceStyle", "Light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 10))
        try capture("overview")
        app.buttons["metric-errors"].tap()
        XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 5))
        try capture("error-rate")
        app.buttons["Close"].tap()
        selectTab("Traces")
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
        try capture("traces")
        app.buttons["trace-7F3A"].tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 5))
        try capture("trace")
        selectTab("Review")
        XCTAssertTrue(app.buttons["rateGood"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["reviewSources"].value as? String, "Collapsed")
        try capture("review")
        app.buttons["needsWork"].tap()
        XCTAssertTrue(app.staticTexts["feedbackTrace"].waitForExistence(timeout: 5))
        app.swipeUp(velocity: .slow)
        scrollTo(app.buttons["reason-Incomplete"])
        app.buttons["reason-Incomplete"].tap()
        try capture("feedback")
        app.buttons["Cancel"].tap()
        selectTab("Prompts")
        app.buttons["prompt-support/answer"].tap()
        scrollTo(app.buttons["comparePrompt"])
        app.buttons["comparePrompt"].tap()
        XCTAssertTrue(app.navigationBars["Changes"].waitForExistence(timeout: 5))
        try capture("prompt-changes")
        selectTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a8f2\n")
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
        try capture("search")
    }

    func testCaptureAppStoreScreens() throws {
        guard let output = ProcessInfo.processInfo.environment["APP_STORE_SCREENSHOTS"] else {
            throw XCTSkip("Set APP_STORE_SCREENSHOTS to capture submission assets")
        }
        func capture(_ name: String) throws {
            try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        launch()
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 10))
        try capture("01-overview")
        app.buttons["metric-errors"].tap()
        XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 5))
        try capture("02-error-rate")
        app.buttons["Close"].tap()
        selectTab("Traces")
        try capture("03-traces")
        app.buttons["trace-7F3A"].tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 5))
        try capture("04-trace-detail")
        selectTab("Review")
        XCTAssertTrue(app.buttons["rateGood"].waitForExistence(timeout: 5))
        try capture("05-review")
        selectTab("Prompts")
        app.buttons["prompt-support/answer"].tap()
        XCTAssertTrue(app.buttons["comparePrompt"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["comparePrompt"])
        app.buttons["comparePrompt"].tap()
        XCTAssertTrue(app.navigationBars["Changes"].waitForExistence(timeout: 5))
        try capture("06-prompt-changes")
    }

    func testCaptureLightScreenReview() throws {
        guard let output = ProcessInfo.processInfo.environment["LIGHT_REVIEW_OUTPUT"] else {
            throw XCTSkip("Set LIGHT_REVIEW_OUTPUT to capture the screen gallery")
        }
        func capture(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1)
            try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
        launch([])
        XCTAssertTrue(app.buttons["connectLangfuse"].waitForExistence(timeout: 10))
        try capture("01-welcome")
        app.buttons["connectLangfuse"].tap()
        XCTAssertTrue(app.textFields["langfuseHost"].waitForExistence(timeout: 5))
        try capture("02-connection"); back()
        app.buttons["exploreSample"].tap()
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 5))
        try capture("04-overview")
        app.swipeUp(); try capture("05-overview-bottom"); app.swipeDown()
        for (kind, name) in [("errors", "06-error-rate"), ("latency", "07-latency"), ("spend", "08-spend"), ("quality", "09-quality")] {
            scrollTo(app.buttons["metric-" + kind]); app.buttons["metric-" + kind].tap()
            XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 5))
            try capture(name); app.buttons["Close"].tap()
        }
        if ProcessInfo.processInfo.environment["SCREEN_REVIEW_METRICS_ONLY"] == "1" { return }
        selectTab("Traces"); try capture("10-traces")
        app.buttons["filter-error"].tap(); try capture("11-traces-errors")
        app.buttons["filter-slow"].tap(); try capture("12-traces-slow")
        app.buttons["filter-all"].tap()
        app.buttons["trace-7F3A"].tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 5))
        try capture("13-trace-error")
        scrollTo(app.buttons["span-7F3A.4"]); try capture("14-trace-timeline")
        app.buttons["span-7F3A.4"].tap()
        XCTAssertTrue(app.navigationBars["Step"].waitForExistence(timeout: 5))
        try capture("15-step-error"); app.swipeUp(); try capture("16-step-content"); back()
        scrollTo(app.buttons["relatedSession"]); app.buttons["relatedSession"].tap()
        XCTAssertTrue(app.navigationBars["Session"].waitForExistence(timeout: 5))
        try capture("17-session"); back(); back()
        app.buttons["trace-9C2B"].tap()
        try capture("18-trace-success"); back()
        selectTab("Review"); try capture("19-review")
        app.swipeUp(); try capture("20-review-context")
        app.buttons["needsWork"].tap()
        XCTAssertTrue(app.staticTexts["feedbackTrace"].waitForExistence(timeout: 5))
        app.buttons["reason-Incomplete"].tap(); try capture("21-review-feedback")
        app.buttons["Cancel"].tap()
        app.buttons["rateGood"].tap(); try capture("22-review-saved")
        app.buttons["rateGood"].tap(); app.buttons["rateGood"].tap()
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 5))
        try capture("23-review-complete")
        selectTab("Prompts"); try capture("24-prompts")
        app.buttons["prompt-support/answer"].tap(); try capture("25-prompt-production")
        app.segmentedControls["promptVersion"].buttons["v13 · staging"].tap()
        try capture("26-prompt-staging")
        scrollTo(app.buttons["comparePrompt"]); try capture("27-prompt-bottom")
        app.buttons["comparePrompt"].tap()
        XCTAssertTrue(app.navigationBars["Changes"].waitForExistence(timeout: 5))
        try capture("28-prompt-changes")
        app.swipeUp(); try capture("29-prompt-changes-bottom")
        selectTab("Search"); try capture("30-search")
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("a8f2\n")
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
        try capture("31-search-results")
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "no-such-trace\n")
        XCTAssertTrue(app.staticTexts["No matching traces"].waitForExistence(timeout: 5))
        try capture("32-search-empty")
        // Search expands the native tab bar; relaunch the sample for the project-menu capture.
        app.terminate(); launch()
        app.buttons["projectMenu"].tap(); try capture("33-project-menu")
        app.terminate()
        launch([], fixture: "data")
        XCTAssertTrue(app.buttons["metric-latency"].waitForExistence(timeout: 10))
        try capture("34-live-overview")
        app.buttons["projectMenu"].tap(); try capture("35-live-project-menu")
        app.buttons["Change environment"].tap()
        XCTAssertTrue(app.navigationBars["Environment"].waitForExistence(timeout: 5))
        try capture("36-environment")
        app.terminate(); launch([], fixture: "empty")
        XCTAssertTrue(app.descendants(matching: .any)["overviewEmpty"].waitForExistence(timeout: 10))
        try capture("37-overview-empty")
        selectTab("Traces"); try capture("38-live-traces-empty")
        selectTab("Review"); try capture("39-live-review-empty")
        selectTab("Prompts"); try capture("40-live-prompts")
        app.terminate(); launch([], fixture: "limit")
        XCTAssertTrue(app.descendants(matching: .any)["metricsRateLimit"].firstMatch.waitForExistence(timeout: 10))
        try capture("41-overview-limit")
    }

    func testCaptureUIReview() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let envPath = environment["REVIEW_ENV_PATH"], let output = environment["REVIEW_OUTPUT"] else {
            throw XCTSkip("Set REVIEW_ENV_PATH and REVIEW_OUTPUT to capture the live review")
        }
        let text = try String(contentsOfFile: envPath, encoding: .utf8)
        var values: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "export ", with: "")
            guard !line.hasPrefix("#"), let split = line.firstIndex(of: "=") else { continue }
            values[String(line[..<split]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        func capture(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.5)
            let shot = app.screenshot()
            try shot.pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["connectLangfuse"].waitForExistence(timeout: 10))
        try capture("01-welcome")
        app.buttons["connectLangfuse"].tap()
        let host = app.textFields["langfuseHost"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        try capture("03-connection")
        let base = try XCTUnwrap(values["LANGFUSE_BASE_URL"] ?? values["LANGFUSE_HOST"])
        XCTAssertEqual(host.value as? String, base)
        app.textFields["langfusePublicKey"].tap(); app.textFields["langfusePublicKey"].typeText(try XCTUnwrap(values["LANGFUSE_PUBLIC_KEY"]))
        app.secureTextFields["langfuseSecretKey"].tap(); app.secureTextFields["langfuseSecretKey"].typeText(try XCTUnwrap(values["LANGFUSE_SECRET_KEY"]))
        app.secureTextFields["langfuseSecretKey"].typeText("\n")
        app.swipeUp()
        scrollTo(app.buttons["submitConnection"]); app.buttons["submitConnection"].tap()
        XCTAssertTrue(app.buttons["metric-latency"].waitForExistence(timeout: 45), app.staticTexts["connectionError"].exists ? app.staticTexts["connectionError"].label : "Connection did not finish")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        // Wait until metric data settles rather than capturing the initial progress view.
        _ = app.descendants(matching: .any)["overviewLoading"].waitForNonExistence(timeout: 45)
        try capture("04-overview")
        app.swipeUp(); try capture("05-overview-bottom"); app.swipeDown()
        for (kind, name) in [("errors", "06-error-rate"), ("latency", "07-latency"), ("spend", "08-spend"), ("quality", "09-quality")] {
            let metric = app.buttons["metric-" + kind]
            scrollTo(metric); metric.tap()
            XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 3)
            try capture(name)
            app.buttons["Close"].tap()
        }
        tab("Traces").tap(); try capture("10-traces")
        let trace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trace-' ")).firstMatch
        if trace.waitForExistence(timeout: 10) {
            let traceID = String(trace.identifier.dropFirst(6))
            trace.tap()
            XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 30))
            try capture("11-trace-detail")
            let step = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'span-' ")).firstMatch
            scrollTo(step)
            if step.exists && step.isHittable {
                try capture("12-trace-timeline"); step.tap()
                XCTAssertTrue(app.navigationBars["Step"].waitForExistence(timeout: 5))
                try capture("13-step-detail"); app.swipeUp(); try capture("14-step-content"); back()
            }
            let session = app.buttons["relatedSession"]
            scrollTo(session)
            if session.exists && session.isHittable {
                session.tap(); XCTAssertTrue(app.navigationBars["Session"].waitForExistence(timeout: 5))
                Thread.sleep(forTimeInterval: 3); try capture("15-session"); back()
            }
            tab("Search").tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            try capture("16-search")
            // Exact trace-ID search avoids assumptions about project naming.
            app.buttons["Search in, Step name"].tap()
            if app.buttons["Trace ID"].waitForExistence(timeout: 3) { app.buttons["Trace ID"].tap() }
            field.tap(); field.typeText(traceID)
            if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
            Thread.sleep(forTimeInterval: 4); try capture("17-search-results")
        }
        tab("Review").tap(); Thread.sleep(forTimeInterval: 5)
        try capture("18-review"); app.swipeUp(); try capture("19-review-controls")
        // Do not press score submission or undo buttons in the real project.
        let needsWork = app.buttons["Needs work"]
        for _ in 0..<12 { if needsWork.isHittable { break }; app.swipeUp() }
        if needsWork.isHittable { needsWork.tap(); try capture("20-review-feedback") }
        tab("Prompts").tap(); Thread.sleep(forTimeInterval: 4); try capture("21-prompts")
        let prompt = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'prompt-' ")).firstMatch
        if prompt.waitForExistence(timeout: 10) {
            prompt.tap(); XCTAssertTrue(app.navigationBars["Prompt"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 4); try capture("22-prompt-detail")
            let compare = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Compare v'")).firstMatch
            for _ in 0..<12 { if compare.isHittable { break }; app.swipeUp() }
            if compare.isHittable {
                try capture("23-prompt-bottom"); compare.tap()
                XCTAssertTrue(app.navigationBars["Changes"].waitForExistence(timeout: 10))
                Thread.sleep(forTimeInterval: 3); try capture("24-prompt-changes")
            }
        }
        tab("Overview").tap()
        app.buttons["projectMenu"].tap(); try capture("25-project-menu")
        app.buttons["Change environment"].tap()
        XCTAssertTrue(app.navigationBars["Environment"].waitForExistence(timeout: 5)); try capture("26-environment")
    }

    func testCaptureUIReviewStates() throws {
        guard let output = ProcessInfo.processInfo.environment["REVIEW_OUTPUT"] else {
            throw XCTSkip("Set REVIEW_OUTPUT to capture the review states")
        }
        launch([], fixture: "empty")
        XCTAssertTrue(app.descendants(matching: .any)["overviewEmpty"].waitForExistence(timeout: 10))
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent("27-overview-empty.png"))
        app.terminate()
        launch([], fixture: "limit")
        XCTAssertTrue(app.descendants(matching: .any)["metricsRateLimit"].firstMatch.waitForExistence(timeout: 10))
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent("28-overview-limit.png"))
    }

    func testCachedOverviewSurvivesRateLimitedRefresh() throws {
        launch([], fixture: "cached-limit")
        XCTAssertTrue(app.staticTexts["3.2s"].waitForExistence(timeout: 10))
        // Production refreshes are spaced by one minute; the fixture obeys the same rule.
        Thread.sleep(forTimeInterval: 61)
        app.buttons["refreshOverview"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["metricsRateLimit"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3.2s"].exists)
        XCTAssertTrue(app.staticTexts["Last available vitals"].exists)
        XCTAssertFalse(app.staticTexts["Unavailable"].exists)
        if let output = ProcessInfo.processInfo.environment["LIGHT_REVIEW_OUTPUT"] {
            try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent("42-overview-cached-limit.png"))
        }
    }

    private func launch(_ arguments: [String] = ["--demo"], fixture: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + arguments
        if let fixture { app.launchEnvironment["SALLE215_LIVE_FIXTURE"] = fixture }
        app.launch()
    }

    func testQualityScoreSelectionAndDetail() {
        launch(["-AppleLocale", "en_US"], fixture: "quality")
        let picker = app.buttons["qualityScorePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        scrollTo(picker)
        XCTAssertTrue(app.staticTexts["62.5%"].exists)
        attachScreenshot("Quality score picker in Vitals")
        picker.tap()
        let search = app.textFields["qualityScoreSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["qualityScore-cart_expected:BOOLEAN"].isSelected)
        attachScreenshot("Quality score choices")
        search.tap()
        search.typeText("no-such-score")
        XCTAssertTrue(app.staticTexts["No matching scores"].waitForExistence(timeout: 5))
        app.buttons["Clear search"].tap()
        search.typeText("NuMeRiC")
        XCTAssertFalse(app.buttons["qualityScore-cart_expected:BOOLEAN"].exists)
        app.buttons["qualityScore-cart_expected:NUMERIC"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4.2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["12 numeric scores"].exists)
        XCTAssertFalse(app.staticTexts["metricValue"].exists)
        app.buttons["metric-quality"].tap()
        XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["metricValue"].label, "4.2")
        XCTAssertTrue(app.staticTexts["cart_expected · 12 numeric scores"].exists)
        app.buttons["Close"].tap()
        picker.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["qualityScore-cart_expected:NUMERIC"].isSelected)
        search.tap()
        search.typeText("support_answer")
        app.buttons["qualityScore-support_answer_relevance_and_completeness:NUMERIC"].tap()
        XCTAssertTrue(app.staticTexts["0.9"].waitForExistence(timeout: 5))
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["qualityScore-support_answer_relevance_and_completeness:NUMERIC"].isSelected)
        app.buttons["Close"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0.9"].exists)
        attachScreenshot("Quality score with a long name")
    }

    func testQualityScorePickerAtAccessibilityTextSizes() {
        launch(["-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], fixture: "quality")
        let picker = app.buttons["qualityScorePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        scrollTo(picker)
        picker.tap()
        let choice = app.buttons["qualityScore-support_answer_relevance_and_completeness:NUMERIC"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        scrollTo(choice)
        XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
        XCTAssertLessThanOrEqual(choice.frame.maxX, app.frame.maxX)
        attachScreenshot("Quality score sheet at accessibility text size")
        choice.tap()
        scrollTo(picker)
        XCTAssertTrue(picker.isHittable)
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        XCTAssertLessThanOrEqual(picker.frame.height, app.frame.height / 3)
        XCTAssertGreaterThanOrEqual(picker.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(picker.frame.maxX, app.frame.maxX)
        scrollTo(app.buttons["metric-quality"])
        app.buttons["metric-quality"].tap()
        XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["metricValue"].label, "0.9")
        app.buttons["Close"].tap()
        attachScreenshot("Quality score at accessibility text size")
    }

    func testLiveOverviewTraceAndSession() {
        launch([], fixture: "data")
        XCTAssertTrue(app.buttons["metric-latency"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3.2s"].waitForExistence(timeout: 10))
        app.buttons["metric-latency"].tap()
        XCTAssertTrue(app.staticTexts["metricValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["metricValue"].label, "3.2s")
        app.buttons["Close"].tap()
        tab("Traces").tap()
        app.buttons["trace-trace-live"].tap()
        XCTAssertTrue(app.staticTexts["Live answer"].waitForExistence(timeout: 10))
        scrollTo(app.buttons["relatedSession"])
        app.buttons["relatedSession"].tap()
        XCTAssertTrue(app.navigationBars["Session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trace-trace-live"].waitForExistence(timeout: 5))
    }

    func testLivePromptVersionsAndReviewUndo() throws {
        launch([], fixture: "data")
        XCTAssertTrue(tab("Prompts").waitForExistence(timeout: 10))
        tab("Prompts").tap()
        XCTAssertTrue(app.buttons["prompt-folder/live"].waitForExistence(timeout: 10))
        app.buttons["prompt-folder/live"].tap()
        XCTAssertTrue(app.staticTexts["Original prompt."].waitForExistence(timeout: 10))
        try captureForReport("45-live-prompt")
        tab("Review").tap()
        XCTAssertTrue(app.staticTexts["Live answer"].waitForExistence(timeout: 10))
        try captureForReport("43-live-review")
        app.buttons["Needs work"].tap()
        XCTAssertTrue(app.buttons["Save rating"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["Save rating"])
        try captureForReport("44-live-review-feedback")
        scrollTo(app.buttons["Cancel feedback"])
        app.buttons["Cancel feedback"].tap()
        scrollTo(app.buttons["Good"])
        app.buttons["Good"].tap()
        XCTAssertTrue(app.buttons["Undo saved review"].waitForExistence(timeout: 10))
        app.buttons["Undo saved review"].tap()
        XCTAssertTrue(app.buttons["Good"].waitForExistence(timeout: 10))
    }

    private func captureForReport(_ name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["LIGHT_REVIEW_OUTPUT"] else { return }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
    }

    func testLiveServerSearch() {
        launch([], fixture: "data")
        XCTAssertTrue(tab("Search").waitForExistence(timeout: 10))
        tab("Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Live agent")
        XCTAssertTrue(app.buttons["trace-trace-live"].waitForExistence(timeout: 10))
        app.buttons["trace-trace-live"].tap()
        XCTAssertTrue(app.staticTexts["Live answer"].waitForExistence(timeout: 10))
    }

    func testLiveOverviewEmptyAndRateLimit() throws {
        launch([], fixture: "empty")
        XCTAssertTrue(app.descendants(matching: .any)["overviewEmpty"].waitForExistence(timeout: 10))
        tab("Review").tap()
        XCTAssertTrue(app.staticTexts["No traces to review"].waitForExistence(timeout: 5))
        try captureForReport("39-live-review-empty")
        app.terminate()
        launch([], fixture: "limit")
        XCTAssertTrue(app.descendants(matching: .any)["metricsRateLimit"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["0.8%"].exists)
    }

    private func tab(_ title: String) -> XCUIElement {
        let phoneTab = app.tabBars.buttons[title]
        if phoneTab.exists { return phoneTab }
        // iPad's floating tabs are exposed as cells instead of a TabBar.
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    func testConnectionFormValidatesBeforeNetworking() {
        launch([])
        app.buttons["connectLangfuse"].tap()
        let host = app.textFields["langfuseHost"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["submitConnection"].isEnabled)
        host.tap()
        host.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "https://cloud.langfuse.com".count) + "http://example.com")
        XCTAssertTrue((host.value as? String)?.hasPrefix("http://") == true)
        app.textFields["langfusePublicKey"].tap()
        app.textFields["langfusePublicKey"].typeText("pk-test")
        app.secureTextFields["langfuseSecretKey"].tap()
        app.secureTextFields["langfuseSecretKey"].typeText("sk-test")
        app.keyboards.buttons["Done"].tap()
        scrollTo(app.buttons["submitConnection"])
        app.buttons["submitConnection"].tap()
        XCTAssertTrue(app.staticTexts["connectionError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["connectionError"].label.contains("HTTPS"))
        attachScreenshot("Langfuse connection")
    }

    func testOnboardingAndTimeRanges() {
        launch([])
        app.buttons["exploreSample"].tap()
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 5))
        app.segmentedControls["timeRange"].buttons["1H"].tap()
        XCTAssertTrue(app.staticTexts["1.2"].exists)
        app.segmentedControls["timeRange"].buttons["7D"].tap()
        XCTAssertTrue(app.staticTexts["0.6"].exists)
        attachScreenshot("Overview")
    }

    func testMetricSheetRoutesToFailedTraces() {
        launch()
        app.buttons["metric-errors"].tap()
        XCTAssertTrue(app.navigationBars["Error rate"].waitForExistence(timeout: 5))
        let chart = app.descendants(matching: .any)["metricTrend"].firstMatch
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        // The selected value remains readable after the user releases the chart.
        let inspected = app.staticTexts["metricValue"].label
        XCTAssertTrue(inspected.hasSuffix("%"))
        XCTAssertEqual(app.staticTexts["metricValue"].label, inspected)
        app.buttons["metricAction"].tap()
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trace-B41C"].exists)
        XCTAssertFalse(app.buttons["trace-9C2B"].exists)
        app.buttons["filter-all"].tap()
        XCTAssertTrue(app.buttons["trace-9C2B"].exists)
        app.buttons["filter-slow"].tap()
        XCTAssertTrue(app.buttons["trace-2E91"].exists)
        XCTAssertTrue(app.buttons["trace-7F3A"].exists)
        XCTAssertFalse(app.buttons["trace-9C2B"].exists)
        XCTAssertFalse(app.buttons["trace-B41C"].exists)
        app.buttons["trace-2E91"].tap()
        selectTab("Overview")
        app.buttons["metric-errors"].tap()
        app.buttons["metricAction"].tap()
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["traceTitle"].exists)
    }

    func testAttentionOpensOnlyMatchingTraces() {
        launch()
        app.buttons["attention-slow-summarize-thread"].tap()
        XCTAssertTrue(app.buttons["trace-2E91"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["trace-7F3A"].exists)
        attachScreenshot("Traces for one attention item")
        app.buttons["clearTraceName"].tap()
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
    }

    func testTraceTimelineAndRelatedSession() {
        launch()
        selectTab("Traces")
        app.buttons["trace-7F3A"].tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Provider timeout"].exists)
        app.buttons["openFailedStep"].tap()
        XCTAssertTrue(app.navigationBars["Step"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo(app.buttons["span-7F3A.4"])
        app.buttons["span-7F3A.4"].tap()
        XCTAssertTrue(app.navigationBars["Step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Primary model"].exists)
        XCTAssertTrue(app.staticTexts["\(1204.formatted()) in · 0 out"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo(app.buttons["relatedSession"])
        app.buttons["relatedSession"].tap()
        XCTAssertTrue(app.navigationBars["Session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trace-9C2B"].exists)
        attachScreenshot("Session")
    }

    func testTracesLoadAsYouScroll() throws {
        launch(["-AppleLocale", "en_US"], fixture: "trace-list")
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 10))
        selectTab("Traces")
        let count = app.staticTexts["traceLoadedCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "12 loaded")
        XCTAssertFalse(app.buttons["loadMoreObservations"].exists)
        XCTAssertFalse(app.buttons["Load more traces"].exists)
        XCTAssertTrue(app.buttons["trace-list-0"].isHittable)
        try captureTraceDesign("trace-list-readable")
        let scroll = app.scrollViews["traceScroll"]
        // The next page must not load merely because the list was constructed.
        XCTAssertFalse(app.buttons["trace-list-12"].exists)
        for _ in 0..<5 {
            if app.buttons["trace-list-12"].isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(app.buttons["trace-list-12"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["trace-list-0"].isHittable, "Appending must preserve the scroll position")
        for _ in 0..<6 {
            if app.buttons["trace-list-25"].isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(app.buttons["trace-list-25"].isHittable)
        XCTAssertFalse(app.otherElements["tracePaginationLoading"].exists, "Exhausted pages must stop loading")
        for _ in 0..<8 { scroll.swipeDown() }
        XCTAssertEqual(count.label, "26 loaded")
        XCTAssertEqual(app.buttons["filter-error"].label, "Errors 2")
        app.buttons["filter-error"].tap()
        XCTAssertTrue(app.buttons["trace-list-12"].isHittable)
        XCTAssertFalse(app.buttons["trace-list-0"].exists)
    }

    func testTracePaginationErrorNeedsExplicitRetry() {
        launch(["-AppleLocale", "en_US"], fixture: "trace-list-retry")
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 10))
        selectTab("Traces")
        let scroll = app.scrollViews["traceScroll"]
        let retry = app.buttons["retryTracePagination"]
        for _ in 0..<6 {
            if retry.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        scroll.swipeUp()
        XCTAssertTrue(app.staticTexts["tracePaginationError"].exists)
        XCTAssertFalse(app.buttons["trace-list-12"].exists, "Scrolling must not retry a failed request")
        retry.tap()
        XCTAssertTrue(app.buttons["trace-list-12"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["tracePaginationError"].exists)
    }

    func testEmptyTraceFilterContinuesAcrossPagesAtLargeText() throws {
        launch(["-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], fixture: "trace-list")
        XCTAssertTrue(app.buttons["metric-errors"].waitForExistence(timeout: 10))
        selectTab("Traces")
        XCTAssertTrue(app.buttons["filter-error"].waitForExistence(timeout: 5))
        app.buttons["filter-error"].tap()
        let match = app.buttons["trace-list-12"]
        XCTAssertTrue(match.waitForExistence(timeout: 10), "A filter must search later loaded pages when the first page has no matches")
        scrollTo(match)
        XCTAssertTrue(match.isHittable)
        XCTAssertLessThanOrEqual(match.frame.maxX, app.frame.maxX)
        try captureTraceDesign("trace-list-large-text")
        for _ in 0..<4 { app.scrollViews["traceScroll"].swipeUp() }
        XCTAssertFalse(app.otherElements["tracePaginationLoading"].exists)
        app.scrollViews["traceScroll"].swipeDown()
        app.scrollViews["traceScroll"].swipeDown()
        XCTAssertEqual(app.buttons["filter-error"].label, "Errors 2")
    }

    func testConversationFirstTraceDetail() throws {
        launch(["-AppleLocale", "en_US"], fixture: "trace-detail")
        tab("Traces").tap()
        app.buttons["trace-2966b30641238103ed2c9d5e4dc24c6"].tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["traceTitle"].label, "Customer message")
        XCTAssertEqual(app.staticTexts["traceInput"].label, "Trou noir capitaine")
        XCTAssertEqual(app.staticTexts["traceOutput"].label, "Tu commandes à emporter ou en livraison ?")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'v2 browse'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Good"].waitForExistence(timeout: 5))
        attachScreenshot("Conversation-first trace")
        try captureTraceDesign("trace-detail-conversation")
        app.buttons["traceFullOutput"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'v2 browse | Reset'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["traceFullOutput"].tap()
        app.buttons["copyTraceOutput"].tap()
        XCTAssertEqual(app.buttons["copyTraceOutput"].label, "Copied")
        let child = app.buttons["span-turn"]
        scrollTo(child)
        XCTAssertTrue(child.isHittable)
        XCTAssertEqual(child.value as? String, "Starts at 55 ms, duration 646 ms")
        XCTAssertGreaterThanOrEqual(child.frame.width, app.buttons["span-root"].frame.width)
        attachScreenshot("Full-width execution timeline")
        try captureTraceDesign("trace-detail-execution")
        child.tap()
        XCTAssertTrue(app.navigationBars["Step"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["conversation-turn"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let details = app.buttons["traceDetails"]
        scrollTo(details); details.tap()
        XCTAssertTrue(app.navigationBars["Trace details"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["traceID"].label, "2966b30641238103ed2c9d5e4dc24c6")
        XCTAssertTrue(app.staticTexts["Steps within the loaded 7-day period. Older steps may be outside this window."].exists)
        app.buttons["copyTraceID"].tap()
        XCTAssertEqual(app.buttons["copyTraceID"].label, "Copied")
        attachScreenshot("Trace metadata")
        try captureTraceDesign("trace-detail-metadata")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Trace details"].waitForNonExistence(timeout: 5))
    }

    func testTraceScoresAndTranscriptAtAccessibilityTextSize() throws {
        launch(["-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], fixture: "trace-scores")
        tab("Traces").tap()
        app.buttons["trace-2966b30641238103ed2c9d5e4dc24c6"].tap()
        XCTAssertTrue(app.staticTexts["traceOutput"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["traceOutput"].label, "Tu commandes à emporter ou en livraison ?")
        let output = app.buttons["traceFullOutput"]
        scrollTo(output); output.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Earlier user turn'")).firstMatch.exists)
        scrollTo(output); output.tap()
        for text in ["False", "0.87", "Evaluator note", "Good", "On-topic"] {
            let element = app.staticTexts[text]
            scrollTo(element)
            XCTAssertTrue(element.exists)
            XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
        }
        let child = app.buttons["span-turn"]
        scrollTo(child)
        XCTAssertTrue(child.isHittable)
        XCTAssertGreaterThanOrEqual(child.frame.height, 44)
        attachScreenshot("Trace timeline at accessibility text size")
        try captureTraceDesign("trace-detail-large-text")
        child.tap()
        XCTAssertTrue(app.navigationBars["Step"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let details = app.buttons["traceDetails"]
        scrollTo(details)
        XCTAssertLessThanOrEqual(details.frame.height, 90)
        try captureTraceDesign("trace-detail-large-text-footer")
        details.tap()
        XCTAssertTrue(app.staticTexts["traceID"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.staticTexts["traceID"].frame.maxX, app.frame.maxX)
    }

    private func captureTraceDesign(_ name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["TRACE_DESIGN_OUTPUT"] else { return }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
    }

    func testReviewFeedbackUndoAndCompletion() throws {
        launch()
        selectTab("Review")
        let sources = app.buttons["reviewSources"]
        XCTAssertEqual(sources.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["Reset links are valid for 30 minutes."].exists)
        XCTAssertLessThanOrEqual(app.buttons["rateGood"].frame.maxY, sources.frame.minY)
        try captureReviewDesign("review-a-implemented")
        sources.tap()
        XCTAssertTrue(app.staticTexts["Reset links are valid for 30 minutes."].exists)
        try captureReviewDesign("review-a-sources")
        sources.tap()
        let reviewTrace = app.buttons["reviewTrace"]
        XCTAssertEqual(reviewTrace.value as? String, "7C1D")
        app.buttons["rateGood"].tap()
        XCTAssertEqual(reviewTrace.value as? String, "9C2B")
        XCTAssertEqual(sources.value as? String, "Collapsed")
        app.buttons["undoReview"].tap()
        XCTAssertEqual(reviewTrace.value as? String, "7C1D")
        app.buttons["needsWork"].tap()
        XCTAssertTrue(app.staticTexts["feedbackTrace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["feedbackTrace"].label.contains("7C1D"))
        app.buttons["reason-Incomplete"].tap()
        try captureForReport("21-review-feedback")
        scrollTo(app.textFields["reviewComment"])
        app.textFields["reviewComment"].tap()
        app.textFields["reviewComment"].typeText("Mention link expiry")
        app.buttons["submitReview"].tap()
        XCTAssertTrue(reviewTrace.waitForExistence(timeout: 5))
        XCTAssertEqual(reviewTrace.value as? String, "9C2B")
        attachScreenshot("Review")
        app.buttons["rateGood"].tap()
        app.buttons["rateGood"].tap()
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 5))
        app.buttons["undoReview"].tap()
        XCTAssertEqual(reviewTrace.value as? String, "D0E4")
        reviewTrace.tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["rateGood"].tap()
        XCTAssertTrue(app.buttons["undoReview"].waitForNonExistence(timeout: 8))
        selectTab("Traces")
        app.buttons["trace-7C1D"].tap()
        let rating = app.descendants(matching: .any)["traceRating"].firstMatch
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        XCTAssertTrue(rating.label.contains("Needs work"))
        XCTAssertTrue(rating.label.contains("Mention link expiry"))
    }

    func testPromptVersionsAndComparison() {
        launch()
        selectTab("Prompts")
        app.buttons["prompt-support/answer"].tap()
        app.segmentedControls["promptVersion"].buttons["v13 · staging"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "mention link expiry")).firstMatch.exists)
        scrollTo(app.buttons["comparePrompt"])
        app.buttons["comparePrompt"].tap()
        XCTAssertTrue(app.navigationBars["Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["User message unchanged"].exists)
        attachScreenshot("Prompt changes")
    }

    func testReviewControlsStackAtAccessibilityTextSizes() throws {
        launch(["--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        selectTab("Review")
        let needsWork = app.buttons["needsWork"], good = app.buttons["rateGood"]
        XCTAssertTrue(needsWork.waitForExistence(timeout: 5))
        scrollTo(good)
        XCTAssertTrue(needsWork.isHittable)
        XCTAssertTrue(good.isHittable)
        XCTAssertLessThanOrEqual(needsWork.frame.maxY, good.frame.minY)
        XCTAssertLessThanOrEqual(good.frame.maxX, app.frame.maxX)
        attachScreenshot("Review controls at the largest text size")
        try captureReviewDesign("review-a-large-text")
        good.tap()
        XCTAssertEqual(app.buttons["reviewTrace"].value as? String, "9C2B")
        XCTAssertTrue(app.staticTexts["Can I change my email address?"].isHittable)
        try captureReviewDesign("review-a-next-answer-large-text")
    }

    func testLiveReviewShowsAssistantAndCollapsedFullContext() throws {
        launch([], fixture: "review")
        XCTAssertTrue(tab("Review").waitForExistence(timeout: 10))
        tab("Review").tap()
        let answer = app.staticTexts["Choose Forgot password. The link expires after 30 minutes."]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Earlier question in transcript"].exists)
        let sources = app.buttons["reviewSources"]
        XCTAssertEqual(sources.value as? String, "Collapsed")
        XCTAssertLessThanOrEqual(app.buttons["Good"].frame.maxY, sources.frame.minY)
        try captureReviewDesign("review-a-live")
        sources.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reset links are valid for 30 minutes.")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "We never ask for your password by email.")).firstMatch.exists)
        sources.tap()
        app.buttons["Needs work"].tap()
        scrollTo(app.buttons["reason-Incomplete"])
        app.buttons["reason-Incomplete"].tap()
        XCTAssertEqual(app.buttons["reason-Incomplete"].value as? String, "Selected")
        scrollTo(app.buttons["Save rating"])
        app.buttons["Save rating"].tap()
        XCTAssertTrue(app.buttons["Undo saved review"].waitForExistence(timeout: 10))
        scrollTo(app.buttons["Undo saved review"])
        app.buttons["Undo saved review"].tap()
        XCTAssertTrue(app.buttons["Good"].waitForExistence(timeout: 10))
    }

    private func captureReviewDesign(_ name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["REVIEW_DESIGN_OUTPUT"] else { return }
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
    }

    func testReviewSkipCollapsesSourcesAndUndoRestoresAnswer() throws {
        launch()
        selectTab("Review")
        let sources = app.buttons["reviewSources"]
        sources.tap()
        XCTAssertEqual(sources.value as? String, "Expanded")
        app.buttons["skipReview"].tap()
        XCTAssertEqual(app.buttons["reviewTrace"].value as? String, "9C2B")
        XCTAssertEqual(sources.value as? String, "Collapsed")
        app.buttons["undoReview"].tap()
        XCTAssertEqual(app.buttons["reviewTrace"].value as? String, "7C1D")
        XCTAssertEqual(sources.value as? String, "Collapsed")
        XCTAssertTrue(app.staticTexts["How do I reset my password?"].isHittable)
        XCTAssertTrue(app.buttons["undoReview"].waitForNonExistence(timeout: 8))
        try captureReviewDesign("review-a-implemented")
    }

    func testSearchBySessionAndNoResults() {
        launch()
        selectTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a8f2")
        XCTAssertTrue(app.buttons["trace-7F3A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trace-9C2B"].exists)
        app.buttons["trace-9C2B"].tap()
        XCTAssertTrue(app.navigationBars["Trace"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "no-such-trace")
        XCTAssertTrue(app.staticTexts["No matching traces"].waitForExistence(timeout: 5))
    }

    private func selectTab(_ name: String) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing \(name) tab")
        tab.tap()
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

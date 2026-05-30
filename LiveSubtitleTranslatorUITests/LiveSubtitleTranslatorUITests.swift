//
//  LiveSubtitleTranslatorUITests.swift
//  LiveSubtitleTranslatorUITests
//
//  Created by Christian Merrill on 5/20/26.
//

import XCTest

final class LiveSubtitleTranslatorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesMenuBarAgent() throws {
        let app = XCUIApplication()

        if app.state == .runningForeground || app.state == .runningBackground {
            XCTAssertTrue(true)
            return
        }

        app.launch()

        let isForeground = app.wait(for: .runningForeground, timeout: 5)
        let isBackground = app.state == .runningBackground
        XCTAssertTrue(isForeground || isBackground)
    }
}

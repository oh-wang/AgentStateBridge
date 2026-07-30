import AgentStateCore
import XCTest

final class PrivacyRedactorTests: XCTestCase {
    func testSummaryDoesNotContainOriginalText() {
        let privateText = "这是一段不应出现的聊天内容"
        let summary = PrivacyRedactor.summarize(privateText)

        XCTAssertFalse(summary.contains(privateText))
        XCTAssertTrue(summary.contains("\(privateText.count) 字"))
        XCTAssertTrue(summary.contains("指纹"))
    }

    func testSameTextHasStableFingerprint() {
        XCTAssertEqual(
            PrivacyRedactor.summarize("same text"),
            PrivacyRedactor.summarize("same text")
        )
    }

    func testDifferentTextHasDifferentFingerprint() {
        XCTAssertNotEqual(
            PrivacyRedactor.summarize("first"),
            PrivacyRedactor.summarize("second")
        )
    }

    func testArrayOnlyReportsCount() {
        let summary = PrivacyRedactor.summarizeValue(["private", "content"])

        XCTAssertEqual(summary, "列表（2 项）")
        XCTAssertFalse(summary.contains("private"))
    }
}

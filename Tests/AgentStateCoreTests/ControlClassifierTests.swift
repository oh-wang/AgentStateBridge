import AgentStateCore
import XCTest

final class ControlClassifierTests: XCTestCase {
    func testConfirmedChinesePromptName() {
        XCTAssertEqual(
            ControlClassifier.semantic(
                role: "AXTextArea",
                title: "随心输入",
                description: nil,
                help: nil
            ),
            .promptInput
        )
    }

    func testConfirmedChineseStopButton() {
        XCTAssertEqual(
            ControlClassifier.semantic(
                role: "AXButton",
                title: "停止",
                description: nil,
                help: nil
            ),
            .stopButton
        )
    }

    func testChineseReasoningLabelAllowsEllipsisVariants() {
        for value in [
            "正在思考",
            "正在思考...",
            "正在思考……",
            "正在思考中",
            "思考中",
            "思考中...",
            "思考中……",
        ] {
            XCTAssertEqual(
                ControlClassifier.semantic(
                    role: "AXStaticText",
                    title: nil,
                    description: nil,
                    help: nil,
                    value: value
                ),
                .reasoningLabel
            )
        }
    }

    func testLongConversationTextIsNotAReasoningLabel() {
        for value in [
            "请解释思考中……这个状态",
            "界面显示正在思考四个字",
        ] {
            XCTAssertNil(
                ControlClassifier.semantic(
                    role: "AXStaticText",
                    title: nil,
                    description: nil,
                    help: nil,
                    value: value
                )
            )
        }
    }

    func testPlaceholderIsNotUserText() {
        XCTAssertEqual(
            ControlClassifier.hasUserText(
                role: "AXTextArea",
                value: "随心输入",
                title: "随心输入",
                description: nil,
                placeholder: nil
            ),
            false
        )
    }

    func testDifferentValueIsUserText() {
        XCTAssertEqual(
            ControlClassifier.hasUserText(
                role: "AXTextArea",
                value: "hello",
                title: "随心输入",
                description: nil,
                placeholder: nil
            ),
            true
        )
    }
}

import Foundation

public enum ControlClassifier {
    private static let promptNames: Set<String> = [
        "随心输入",
        "ask anything",
        "message chatgpt",
        "message codex"
    ]

    private static let stopNames: Set<String> = [
        "停止",
        "stop",
        "stop generating"
    ]

    private static let sendNames: Set<String> = [
        "发送",
        "send",
        "send message",
        "提交",
        "submit"
    ]

    public static func semantic(
        role: String,
        title: String?,
        description: String?,
        help: String?,
        value: String? = nil
    ) -> ControlSemantic? {
        let names = [title, description, help, value]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if names.contains(where: isReasoningLabel) {
            return .reasoningLabel
        }
        if role == "AXTextArea", names.contains(where: promptNames.contains) {
            return .promptInput
        }
        if role == "AXButton", names.contains(where: stopNames.contains) {
            return .stopButton
        }
        if role == "AXButton", names.contains(where: sendNames.contains) {
            return .sendButton
        }
        return nil
    }

    private static func isReasoningLabel(_ value: String) -> Bool {
        let withoutEllipsis = value
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutEllipsis == "正在思考"
            || withoutEllipsis == "正在思考中"
            || withoutEllipsis == "思考中"
            || withoutEllipsis == "thinking"
    }

    public static func hasUserText(
        role: String,
        value: String?,
        title: String?,
        description: String?,
        placeholder: String?
    ) -> Bool? {
        guard role == "AXTextArea" || role == "AXTextField" else {
            return nil
        }
        guard let value else {
            return false
        }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            return false
        }

        let emptyValues = [title, description, placeholder]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !emptyValues.contains(normalizedValue)
    }
}

import Foundation

public enum ControlSemantic: String, Codable, Equatable, Sendable {
    case promptInput = "prompt_input"
    case reasoningLabel = "reasoning_label"
    case stopButton = "stop_button"
    case sendButton = "send_button"
}

public struct InspectedNode: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let depth: Int
    public let role: String
    public let subrole: String?
    public let identifier: String?
    public let title: String?
    public let description: String?
    public let help: String?
    public let valueSummary: String?
    public let isEnabled: Bool?
    public let isFocused: Bool?
    public let childCount: Int
    public let semantic: ControlSemantic?
    public let hasUserText: Bool?
    public let ariaLive: String?

    public init(
        id: String,
        depth: Int,
        role: String,
        subrole: String?,
        identifier: String?,
        title: String?,
        description: String?,
        help: String?,
        valueSummary: String?,
        isEnabled: Bool?,
        isFocused: Bool?,
        childCount: Int,
        semantic: ControlSemantic? = nil,
        hasUserText: Bool? = nil,
        ariaLive: String? = nil
    ) {
        self.id = id
        self.depth = depth
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.description = description
        self.help = help
        self.valueSummary = valueSummary
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.childCount = childCount
        self.semantic = semantic
        self.hasUserText = hasUserText
        self.ariaLive = ariaLive
    }
}

public enum AgentActivityState: String, Codable, Equatable, Sendable {
    case inactive
    case idle
    case composing
    case reasoning
    case working
    case completed
    case unknown

    public var displayName: String {
        switch self {
        case .inactive: "未运行"
        case .idle: "空闲"
        case .composing: "正在输入"
        case .reasoning: "思考中"
        case .working: "输出中"
        case .completed: "刚刚完成"
        case .unknown: "暂时无法判断"
        }
    }
}

public enum ActivityEvidence: String, Codable, Equatable, Sendable {
    case applicationNotRunning = "application-not-running"
    case accessibilityUnavailable = "accessibility-unavailable"
    case promptInputPresent = "prompt-input-present"
    case promptInputContainsText = "prompt-input-contains-text"
    case reasoningLabelPresent = "reasoning-label-present"
    case stopButtonPresent = "stop-button-present"
    case stopButtonDisappeared = "stop-button-disappeared"
}

public struct ActivityAssessment: Codable, Equatable, Sendable {
    public let state: AgentActivityState
    public let confidence: Double
    public let evidence: [ActivityEvidence]

    public init(
        state: AgentActivityState,
        confidence: Double,
        evidence: [ActivityEvidence]
    ) {
        self.state = state
        self.confidence = confidence
        self.evidence = evidence
    }

    public static let unknown = ActivityAssessment(
        state: .unknown,
        confidence: 0,
        evidence: [.accessibilityUnavailable]
    )
}

public struct ActivityTransition: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let assessment: ActivityAssessment

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        assessment: ActivityAssessment
    ) {
        self.id = id
        self.timestamp = timestamp
        self.assessment = assessment
    }
}

public struct InspectionSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let applicationVersion: String?
    public let processIdentifier: Int32
    public let nodes: [InspectedNode]
    public let wasTruncated: Bool

    public init(
        capturedAt: Date,
        applicationVersion: String?,
        processIdentifier: Int32,
        nodes: [InspectedNode],
        wasTruncated: Bool
    ) {
        self.capturedAt = capturedAt
        self.applicationVersion = applicationVersion
        self.processIdentifier = processIdentifier
        self.nodes = nodes
        self.wasTruncated = wasTruncated
    }
}

public struct ObservedChange: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let notification: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), notification: String) {
        self.id = id
        self.timestamp = timestamp
        self.notification = notification
    }
}

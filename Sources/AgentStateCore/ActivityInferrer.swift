import Foundation

public enum ActivityInferrer {
    public static func assess(
        snapshot: InspectionSnapshot,
        previous: ActivityAssessment?
    ) -> ActivityAssessment {
        let stopButtonPresent = snapshot.nodes.contains { $0.semantic == .stopButton }
        let reasoningLabelPresent = snapshot.nodes.contains {
            $0.semantic == .reasoningLabel
        }

        // ChatGPT currently exposes “正在思考” as ordinary accessibility
        // text rather than an ARIA live region. Requiring both the exact label
        // and the stop button keeps the signal useful without depending on
        // that missing attribute.
        if stopButtonPresent, reasoningLabelPresent {
            return ActivityAssessment(
                state: .reasoning,
                confidence: 0.94,
                evidence: [.reasoningLabelPresent, .stopButtonPresent]
            )
        }

        if stopButtonPresent {
            return ActivityAssessment(
                state: .working,
                confidence: 0.96,
                evidence: [.stopButtonPresent]
            )
        }

        let promptInput = snapshot.nodes.first(where: { $0.semantic == .promptInput })
        if promptInput?.hasUserText == true {
            return ActivityAssessment(
                state: .composing,
                confidence: 0.88,
                evidence: [.promptInputPresent, .promptInputContainsText]
            )
        }

        // A completion is intentionally held until the caller's TTL expires.
        // Extra AX notifications often cause several snapshots right after the
        // stop button disappears and must not shorten the visible completion.
        // Real new activity above always takes priority over this hold.
        if previous?.state == .completed {
            return previous ?? .unknown
        }

        if previous?.state == .working || previous?.state == .reasoning {
            return ActivityAssessment(
                state: .completed,
                confidence: 0.90,
                evidence: [.stopButtonDisappeared]
            )
        }

        if promptInput != nil {
            return ActivityAssessment(
                state: .idle,
                confidence: 0.82,
                evidence: [.promptInputPresent]
            )
        }

        return ActivityAssessment(
            state: .unknown,
            confidence: 0.20,
            evidence: []
        )
    }

    public static let inactive = ActivityAssessment(
        state: .inactive,
        confidence: 1,
        evidence: [.applicationNotRunning]
    )
}

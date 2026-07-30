import AgentStateBridgeService
import AgentStateCore
import AppKit
import MacSignalSources
import OSLog

public struct AgentStateRuntimeConfiguration: Sendable, Equatable {
    public let enablesExternalSocket: Bool

    public init(enablesExternalSocket: Bool = true) {
        self.enablesExternalSocket = enablesExternalSocket
    }
}

public struct AgentStateRuntimeSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sequence: Int64
    public let state: String
    public let previousState: String

    public init(
        schemaVersion: Int,
        sequence: Int64,
        state: String,
        previousState: String
    ) {
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.state = state
        self.previousState = previousState
    }

    public init(envelope: AgentStateEnvelope) {
        schemaVersion = envelope.schemaVersion
        sequence = Int64(clamping: envelope.sequence)
        state = envelope.state.rawValue
        previousState = envelope.previousState?.rawValue ?? "unknown"
    }
}

struct InspectionRefreshGate: Sendable {
    private(set) var isRunning = false
    private var hasPendingRequest = false

    mutating func request() -> Bool {
        guard !isRunning else {
            hasPendingRequest = true
            return false
        }
        isRunning = true
        return true
    }

    mutating func finish() -> Bool {
        isRunning = false
        defer { hasPendingRequest = false }
        return hasPendingRequest
    }

    mutating func cancel() {
        isRunning = false
        hasPendingRequest = false
    }
}

private enum InspectionReadOutcome: Sendable {
    case success(InspectionSnapshot, elapsedMilliseconds: Double)
    case failure(String, elapsedMilliseconds: Double)
}

/// Headless lifecycle for ChatGPT observation.
///
/// Both the diagnostic Inspector and an embedding macOS app can own this type.
/// It deliberately has no SwiftUI dependency.
@MainActor
public final class AgentStateRuntime {
    public private(set) var permissionGranted = AccessibilityPermission.isGranted
    public private(set) var chatGPT: ChatGPTRunningApplication?
    public private(set) var latestInspectionSnapshot: InspectionSnapshot?
    public private(set) var activity = ActivityAssessment.unknown
    public private(set) var currentEnvelope: AgentStateEnvelope?
    public private(set) var isRunning = false
    public private(set) var isObserving = false
    public private(set) var runtimeErrorMessage: String?
    public private(set) var bridgeErrorMessage: String?

    public var onSnapshot: ((AgentStateRuntimeSnapshot) -> Void)?
    public var onUnavailable: (() -> Void)?
    public var onStatusChange: (() -> Void)?
    public var onActivityChange: ((ActivityAssessment) -> Void)?
    public var onNotification: ((String) -> Void)?

    public var currentSnapshot: AgentStateRuntimeSnapshot? {
        currentEnvelope.map(AgentStateRuntimeSnapshot.init)
    }

    public var stateFileURL: URL {
        statePublisher.writer.fileURL
    }

    public var socketFileURL: URL {
        socketServer.socketURL
    }

    public var revealControlNames = false

    private let configuration: AgentStateRuntimeConfiguration
    private let reader: any InspectionSnapshotReading
    private let statePublisher: StateSnapshotPublisher
    private let socketServer: UnixSocketStateServer
    private var socketIsAvailable = false
    private var socketStartupErrorMessage: String?
    private var monitor: AXChangeMonitor?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pendingRefresh: Task<Void, Never>?
    private var pendingCompletionReset: Task<Void, Never>?
    private var observationRefreshLoop: Task<Void, Never>?
    private var inspectionTask: Task<Void, Never>?
    private var inspectionGate = InspectionRefreshGate()
    private var inspectionGeneration: UInt64 = 0
    private var hasReportedUnavailable = false
    private let inspectionLogger = Logger(
        subsystem: "local.agentstatebridge.runtime",
        category: "AXInspection"
    )

    public init(
        configuration: AgentStateRuntimeConfiguration = .init(),
        reader: any InspectionSnapshotReading = AXTreeReader(),
        statePublisher: StateSnapshotPublisher = StateSnapshotPublisher(),
        socketServer: UnixSocketStateServer = UnixSocketStateServer()
    ) {
        self.configuration = configuration
        self.reader = reader
        self.statePublisher = statePublisher
        self.socketServer = socketServer
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        runtimeErrorMessage = nil
        startExternalSocketIfNeeded()
        observeWorkspace()
        refreshApplicationStatus()
        startObservingIfPossible()

        if currentEnvelope == nil {
            publishAssessment(activity, previousState: nil)
        }
        if !permissionGranted {
            reportUnavailableOnce()
        }
        notifyStatusChanged()
    }

    public func stop() {
        guard isRunning else { return }

        tearDownObservation()
        removeWorkspaceObservers()
        publishAssessment(
            .unknown,
            previousState: activity.state
        )
        activity = .unknown
        onActivityChange?(.unknown)
        onUnavailable?()
        isRunning = false
        socketServer.stop()
        socketIsAvailable = false
        notifyStatusChanged()
    }

    public func refreshPermission() {
        permissionGranted = AccessibilityPermission.isGranted
        notifyStatusChanged()
    }

    public func requestPermission() {
        AccessibilityPermission.requestFromUser()
        refreshPermissionAndStart()
    }

    public func refreshPermissionAndStart() {
        refreshApplicationStatus()
        startObservingIfPossible()
    }

    public func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func refreshApplicationStatus() {
        permissionGranted = AccessibilityPermission.isGranted
        chatGPT = ChatGPTApplicationLocator.runningApplication()

        if !permissionGranted, isObserving {
            tearDownObservation()
            setActivity(.unknown)
            reportUnavailableOnce()
        } else if chatGPT == nil, isObserving {
            tearDownObservation()
        }

        if chatGPT == nil {
            setActivity(ActivityInferrer.inactive)
        }
        notifyStatusChanged()
    }

    public func refreshInspection() {
        guard isRunning else { return }
        refreshApplicationStatus()
        runtimeErrorMessage = nil

        guard permissionGranted else {
            runtimeErrorMessage = "请先允许辅助功能权限。"
            setActivity(.unknown)
            reportUnavailableOnce()
            notifyStatusChanged()
            return
        }
        guard let chatGPT else {
            runtimeErrorMessage = "没有找到正在运行的 ChatGPT。"
            setActivity(ActivityInferrer.inactive)
            notifyStatusChanged()
            return
        }

        guard inspectionGate.request() else { return }

        let reader = self.reader
        let processIdentifier = chatGPT.processIdentifier
        let applicationVersion = chatGPT.version
        let revealControlNames = self.revealControlNames
        let generation = inspectionGeneration

        inspectionTask = Task.detached(priority: .utility) { [weak self] in
            let startedAt = ProcessInfo.processInfo.systemUptime
            let outcome: InspectionReadOutcome
            do {
                let snapshot = try reader.read(
                    processIdentifier: processIdentifier,
                    applicationVersion: applicationVersion,
                    revealControlNames: revealControlNames
                )
                outcome = .success(
                    snapshot,
                    elapsedMilliseconds:
                        (ProcessInfo.processInfo.systemUptime - startedAt)
                        * 1_000
                )
            } catch {
                outcome = .failure(
                    error.localizedDescription,
                    elapsedMilliseconds:
                        (ProcessInfo.processInfo.systemUptime - startedAt)
                        * 1_000
                )
            }

            guard !Task.isCancelled else { return }
            await self?.finishInspection(outcome, generation: generation)
        }
    }

    private func finishInspection(
        _ outcome: InspectionReadOutcome,
        generation: UInt64
    ) {
        guard generation == inspectionGeneration else { return }
        inspectionTask = nil
        let shouldRefreshAgain = inspectionGate.finish()
        guard isRunning else { return }

        switch outcome {
        case let .success(newSnapshot, elapsedMilliseconds):
            if elapsedMilliseconds >= 50 {
                inspectionLogger.notice(
                    """
                    AX scan took \
                    \(elapsedMilliseconds, format: .fixed(precision: 1)) ms \
                    for \(newSnapshot.nodes.count) nodes
                    """
                )
            }
            latestInspectionSnapshot = newSnapshot
            hasReportedUnavailable = false
            setActivity(
                ActivityInferrer.assess(
                    snapshot: newSnapshot,
                    previous: activity
                )
            )
            scheduleCompletionResetIfNeeded()
        case let .failure(message, elapsedMilliseconds):
            inspectionLogger.error(
                """
                AX scan failed after \
                \(elapsedMilliseconds, format: .fixed(precision: 1)) ms: \
                \(message, privacy: .public)
                """
            )
            runtimeErrorMessage = message
            setActivity(.unknown)
            reportUnavailableOnce()
        }
        notifyStatusChanged()

        if shouldRefreshAgain {
            refreshInspection()
        }
    }

    private func startExternalSocketIfNeeded() {
        guard configuration.enablesExternalSocket else {
            socketIsAvailable = false
            return
        }
        do {
            try socketServer.start()
            socketIsAvailable = true
            socketStartupErrorMessage = nil
            bridgeErrorMessage = nil
        } catch {
            socketIsAvailable = false
            let message = "无法启动 bridge.sock：\(error.localizedDescription)"
            socketStartupErrorMessage = message
            bridgeErrorMessage = message
        }
    }

    private func startObservingIfPossible() {
        guard isRunning,
              !isObserving,
              permissionGranted,
              let chatGPT
        else {
            return
        }

        guard let newMonitor = AXChangeMonitor(
            processIdentifier: chatGPT.processIdentifier,
            handler: { [weak self] name in
                DispatchQueue.main.async {
                    self?.received(notification: name)
                }
            }
        ) else {
            runtimeErrorMessage = "无法开始观察 ChatGPT 的界面变化。"
            setActivity(.unknown)
            reportUnavailableOnce()
            notifyStatusChanged()
            return
        }

        monitor = newMonitor
        isObserving = true
        onNotification?("开始观察")
        refreshInspection()
        startObservationRefreshLoop()
        notifyStatusChanged()
    }

    private func tearDownObservation() {
        observationRefreshLoop?.cancel()
        observationRefreshLoop = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pendingCompletionReset?.cancel()
        pendingCompletionReset = nil
        cancelInspection()
        monitor?.stop()
        monitor = nil
        isObserving = false
    }

    private func cancelInspection() {
        inspectionGeneration &+= 1
        inspectionTask?.cancel()
        inspectionTask = nil
        inspectionGate.cancel()
    }

    private func received(notification: String) {
        onNotification?(notification)
        let refreshNotifications: Set<String> = [
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
            "AXCreated",
            "AXLiveRegionCreated",
            "AXLiveRegionChanged",
            kAXUIElementDestroyedNotification,
            kAXWindowCreatedNotification,
            kAXTitleChangedNotification,
            kAXLayoutChangedNotification
        ]
        if refreshNotifications.contains(notification) {
            scheduleRefresh(delay: .milliseconds(75))
        }
    }

    private func scheduleRefresh(delay: Duration) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.refreshInspection()
        }
    }

    private func scheduleCompletionResetIfNeeded() {
        pendingCompletionReset?.cancel()
        guard activity.state == .completed,
              let latestInspectionSnapshot
        else {
            return
        }

        pendingCompletionReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled,
                  let self,
                  self.activity.state == .completed
            else {
                return
            }
            self.setActivity(
                ActivityInferrer.assess(
                    snapshot: latestInspectionSnapshot,
                    previous: nil
                )
            )
            self.notifyStatusChanged()
        }
    }

    private func startObservationRefreshLoop() {
        observationRefreshLoop?.cancel()
        observationRefreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = Duration.milliseconds(
                    Self.inspectionIntervalMilliseconds(
                        for: self.activity.state
                    )
                )

                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self.refreshInspection()
            }
        }
    }

    static func inspectionIntervalMilliseconds(
        for state: AgentActivityState
    ) -> Int {
        switch state {
        case .reasoning, .working:
            150
        default:
            500
        }
    }

    private func setActivity(_ newActivity: ActivityAssessment) {
        let previousState = activity.state
        activity = newActivity
        guard newActivity.state != previousState else { return }

        onActivityChange?(newActivity)
        publishAssessment(newActivity, previousState: previousState)
    }

    private func publishAssessment(
        _ assessment: ActivityAssessment,
        previousState: AgentActivityState?
    ) {
        let envelope = statePublisher.makeEnvelope(
            assessment: assessment,
            previousState: previousState,
            applicationVersion: chatGPT?.version
        )

        var errors: [String] = socketStartupErrorMessage.map { [$0] } ?? []
        do {
            try statePublisher.writer.write(envelope)
        } catch {
            errors.append("无法写入 state.json：\(error.localizedDescription)")
        }

        if configuration.enablesExternalSocket, socketIsAvailable {
            do {
                try socketServer.broadcast(envelope)
            } catch {
                errors.append("无法发送 socket 事件：\(error.localizedDescription)")
            }
        }

        bridgeErrorMessage = errors.first
        currentEnvelope = envelope
        onSnapshot?(AgentStateRuntimeSnapshot(envelope: envelope))
        notifyStatusChanged()
    }

    private func reportUnavailableOnce() {
        guard !hasReportedUnavailable else { return }
        hasReportedUnavailable = true
        onUnavailable?()
    }

    private func notifyStatusChanged() {
        onStatusChange?()
    }

    private func observeWorkspace() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification
        ]

        workspaceObservers = notifications.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.refreshApplicationStatus()
                    self.startObservingIfPossible()
                }
            }
        }
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }
}

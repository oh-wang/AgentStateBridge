import AgentStateCore
import AgentStateRuntime
import ApplicationServices
import Combine
import MacSignalSources
import SwiftUI

@MainActor
final class InspectorViewModel: ObservableObject {
    @Published private(set) var permissionGranted = false
    @Published private(set) var chatGPT: ChatGPTRunningApplication?
    @Published private(set) var snapshot: InspectionSnapshot?
    @Published private(set) var changes: [ObservedChange] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isObserving = false
    @Published private(set) var activity = ActivityAssessment.unknown
    @Published private(set) var activityTransitions: [ActivityTransition] = []
    @Published private(set) var bridgeSequence: UInt64?
    @Published private(set) var bridgeErrorMessage: String?
    @Published var revealControlNames = false
    @Published var searchText = ""

    private let runtime: AgentStateRuntime

    var stateFilePath: String {
        runtime.stateFileURL.path
    }

    var socketFilePath: String {
        runtime.socketFileURL.path
    }

    init(runtime: AgentStateRuntime = AgentStateRuntime()) {
        self.runtime = runtime
        bindRuntime()
        runtime.start()
        syncFromRuntime()
    }

    func refreshPermission() {
        runtime.refreshPermission()
        syncFromRuntime()
    }

    func requestPermission() {
        runtime.requestPermission()
        syncFromRuntime()
    }

    func refreshPermissionAndStart() {
        runtime.refreshPermissionAndStart()
        syncFromRuntime()
    }

    func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
    }

    func refreshApplicationStatus() {
        runtime.refreshApplicationStatus()
        syncFromRuntime()
    }

    func startObserving() {
        changes.removeAll(keepingCapacity: true)
        activityTransitions.removeAll(keepingCapacity: true)
        runtime.start()
        syncFromRuntime()
    }

    func stopObserving() {
        runtime.stop()
        syncFromRuntime()
    }

    func refreshTree() {
        runtime.refreshInspection()
        syncFromRuntime()
    }

    func revealSettingChanged() {
        runtime.revealControlNames = revealControlNames
        if runtime.isObserving || runtime.latestInspectionSnapshot != nil {
            runtime.refreshInspection()
        }
        syncFromRuntime()
    }

    private func bindRuntime() {
        runtime.onStatusChange = { [weak self] in
            self?.syncFromRuntime()
        }
        runtime.onSnapshot = { [weak self] _ in
            self?.syncFromRuntime()
        }
        runtime.onUnavailable = { [weak self] in
            self?.syncFromRuntime()
        }
        runtime.onActivityChange = { [weak self] assessment in
            self?.recordActivityTransition(assessment)
        }
        runtime.onNotification = { [weak self] notification in
            self?.recordNotification(notification)
        }
    }

    private func syncFromRuntime() {
        permissionGranted = runtime.permissionGranted
        chatGPT = runtime.chatGPT
        snapshot = runtime.latestInspectionSnapshot
        errorMessage = runtime.runtimeErrorMessage
        isObserving = runtime.isObserving
        activity = runtime.activity
        bridgeSequence = runtime.currentEnvelope?.sequence
        bridgeErrorMessage = runtime.bridgeErrorMessage
    }

    private func recordActivityTransition(_ assessment: ActivityAssessment) {
        activityTransitions.insert(
            ActivityTransition(assessment: assessment),
            at: 0
        )
        if activityTransitions.count > 50 {
            activityTransitions.removeLast(activityTransitions.count - 50)
        }
        syncFromRuntime()
    }

    private func recordNotification(_ notification: String) {
        changes.insert(
            ObservedChange(notification: friendlyName(notification)),
            at: 0
        )
        if changes.count > 200 {
            changes.removeLast(changes.count - 200)
        }
    }

    private func friendlyName(_ notification: String) -> String {
        let names: [String: String] = [
            kAXFocusedUIElementChangedNotification: "焦点移到了另一个控件",
            kAXValueChangedNotification: "某个控件的值发生变化",
            "AXCreated": "出现了新控件",
            "AXLiveRegionCreated": "出现了实时状态提示",
            "AXLiveRegionChanged": "实时状态提示发生变化",
            kAXUIElementDestroyedNotification: "某个控件消失了",
            kAXWindowCreatedNotification: "出现了新窗口",
            kAXTitleChangedNotification: "某个控件的标题发生变化",
            kAXLayoutChangedNotification: "界面布局发生变化"
        ]
        return names[notification] ?? notification
    }
}

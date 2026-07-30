import AgentStateCore
import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: InspectorViewModel
    @State private var selectedNodeID: String?

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()

            if !model.permissionGranted {
                permissionView
            } else if model.chatGPT == nil {
                chatGPTNotRunningView
            } else {
                content
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .onChange(of: model.revealControlNames) {
            model.revealSettingChanged()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(
                model.permissionGranted ? "辅助功能权限已允许" : "需要辅助功能权限",
                systemImage: model.permissionGranted ? "checkmark.shield.fill" : "exclamationmark.shield"
            )
            .foregroundStyle(model.permissionGranted ? .green : .orange)

            Divider().frame(height: 20)

            Label(
                model.chatGPT == nil ? "ChatGPT 未运行" : "ChatGPT 正在运行",
                systemImage: model.chatGPT == nil ? "xmark.circle" : "checkmark.circle.fill"
            )

            if let chatGPT = model.chatGPT {
                Text("版本 \(chatGPT.version ?? "未知")")
                    .foregroundStyle(.secondary)
                Text(chatGPT.isFrontmost ? "当前在前台" : "当前在后台")
                    .foregroundStyle(.secondary)
            }

            if let sequence = model.bridgeSequence {
                Text("Bridge #\(sequence)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(
                        "快照：\(model.stateFilePath)\n"
                            + "实时事件：\(model.socketFilePath)"
                    )
            }

            Spacer()

            if model.isObserving {
                Button("停止观察", role: .destructive) {
                    model.stopObserving()
                }
            } else {
                Button("开始观察") {
                    model.startObserving()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("重新读取") {
                model.refreshTree()
            }
            .disabled(!model.permissionGranted || model.chatGPT == nil)
        }
        .padding(12)
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("需要辅助功能权限", systemImage: "hand.raised.fill")
        } description: {
            Text("这个权限让检查器看到 ChatGPT 窗口里的控件。它不会监听键盘，也不会录制屏幕。")
        } actions: {
            HStack {
                Button("请求权限") {
                    model.requestPermission()
                }
                .buttonStyle(.borderedProminent)

                Button("打开系统设置") {
                    model.openAccessibilitySettings()
                }

                Button("我已允许，重新检查") {
                    model.refreshPermissionAndStart()
                }
            }
        }
    }

    private var chatGPTNotRunningView: some View {
        ContentUnavailableView {
            Label("没有找到 ChatGPT", systemImage: "bubble.left.and.exclamationmark.bubble.right")
        } description: {
            Text("请先打开 ChatGPT，然后点下面的按钮。")
        } actions: {
            Button("重新查找") {
                model.refreshApplicationStatus()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()

            HSplitView {
                nodeList
                    .frame(minWidth: 580)
                changeList
                    .frame(minWidth: 300)
            }

            if let message = model.errorMessage {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = model.bridgeErrorMessage {
                Divider()
                Label(message, systemImage: "doc.badge.exclamationmark")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var optionsBar: some View {
        HStack {
            Toggle("临时显示控件名称", isOn: $model.revealControlNames)
                .toggleStyle(.switch)
                .help("可能会显示聊天中的少量文字。控件的正文值仍然始终隐藏。")

            Text("正文内容始终只显示长度和指纹")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("搜索控件类型、identifier 或名称", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            Spacer()

            if let snapshot = model.snapshot {
                Text("读到 \(snapshot.nodes.count) 个控件")
                if snapshot.wasTruncated {
                    Text("有一部分过深的内容被省略")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("还没有读取")
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 20)

            HStack(spacing: 5) {
                Circle()
                    .fill(activityColor)
                    .frame(width: 9, height: 9)
                Text("状态：\(model.activity.state.displayName)")
                    .fontWeight(.semibold)
                Text("\(Int(model.activity.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var nodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ChatGPT 界面里的控件")
                .font(.headline)
                .padding(12)

            Divider()

            if !filteredNodes.isEmpty {
                List(filteredNodes, selection: $selectedNodeID) { node in
                    NodeRow(node: node)
                        .tag(node.id)
                }
                .listStyle(.inset)
            } else {
                ContentUnavailableView(
                    "还没有控件信息",
                    systemImage: "list.bullet.rectangle",
                    description: Text("获得权限后会自动开始；也可以点“开始观察”或“重新读取”。")
                )
            }
        }
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("界面变化")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(model.isObserving ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(model.isObserving ? "正在观察" : "已停止")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if model.changes.isEmpty && model.activityTransitions.isEmpty {
                ContentUnavailableView(
                    "还没有变化",
                    systemImage: "waveform.path",
                    description: Text("观察会自动开始；请在 ChatGPT 中点击或输入。")
                )
            } else {
                List {
                    if !model.activityTransitions.isEmpty {
                        Section("状态变化") {
                            ForEach(model.activityTransitions) { transition in
                                HStack {
                                    Circle()
                                        .fill(color(for: transition.assessment.state))
                                        .frame(width: 8, height: 8)
                                    Text(transition.assessment.state.displayName)
                                    Spacer()
                                    Text("\(Int(transition.assessment.confidence * 100))%")
                                        .foregroundStyle(.secondary)
                                    Text(
                                        transition.timestamp.formatted(
                                            date: .omitted,
                                            time: .standard
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if !model.changes.isEmpty {
                        Section("原始通知") {
                            ForEach(model.changes) { change in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(change.notification)
                                    Text(
                                        change.timestamp.formatted(
                                            date: .omitted,
                                            time: .standard
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var filteredNodes: [InspectedNode] {
        guard let nodes = model.snapshot?.nodes else {
            return []
        }
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nodes
        }

        return nodes.filter { node in
            [
                node.role,
                node.subrole,
                node.identifier,
                node.title,
                node.description,
                node.help,
                node.valueSummary
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var activityColor: Color {
        color(for: model.activity.state)
    }

    private func color(for state: AgentActivityState) -> Color {
        switch state {
        case .inactive: .gray
        case .idle: .blue
        case .composing: .orange
        case .reasoning: .purple
        case .working: .green
        case .completed: .mint
        case .unknown: .secondary
        }
    }
}

private struct NodeRow: View {
    let node: InspectedNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(node.role)
                    .font(.system(.body, design: .monospaced))
                if let identifier = node.identifier, !identifier.isEmpty {
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if node.isFocused == true {
                    Text("已聚焦")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
                if let semantic = node.semantic {
                    Text(semanticLabel(semantic))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }
            }

            if let name = node.title ?? node.description ?? node.help {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Text("位置 \(node.id)")
                Text("\(node.childCount) 个子控件")
                if let ariaLive = node.ariaLive {
                    Text("实时区域 \(ariaLive)")
                }
                if let value = node.valueSummary {
                    Text(value)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.leading, CGFloat(min(node.depth, 12)) * 12)
    }

    private func semanticLabel(_ semantic: ControlSemantic) -> String {
        switch semantic {
        case .promptInput: "输入框"
        case .reasoningLabel: "思考提示"
        case .stopButton: "停止按钮"
        case .sendButton: "发送按钮"
        }
    }
}

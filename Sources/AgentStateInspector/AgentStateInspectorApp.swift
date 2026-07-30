import SwiftUI

@main
struct AgentStateInspectorApp: App {
    @StateObject private var model = InspectorViewModel()

    var body: some Scene {
        WindowGroup("Agent State Inspector") {
            InspectorView(model: model)
        }
        .defaultSize(width: 1_100, height: 760)

        Settings {
            VStack(alignment: .leading, spacing: 8) {
                Text("Agent State Inspector")
                    .font(.headline)
                Text("自动观察 ChatGPT 状态，并通过本地文件和 Unix socket 提供给其他程序。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}

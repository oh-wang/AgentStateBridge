# 架构说明

AgentStateBridge 被拆成几个相互独立的小模块。这样既能运行诊断应用，也能把状态能力
嵌入其他 macOS 程序。

## 数据流程

```text
ChatGPTApplicationLocator
    找到 ChatGPT 进程
            ↓
AXChangeMonitor + AXTreeReader
    接收界面通知并读取辅助功能控件
            ↓
ControlClassifier
    把控件归类为输入框、停止按钮、思考文字等
            ↓
ActivityInferrer
    根据多个信号判断状态
            ↓
AgentStateRuntime
    管理权限、刷新节奏、生命周期和状态转换
            ↓
回调 / StateSnapshotWriter / UnixSocketStateServer
```

## AgentStateCore

核心模块不依赖 AppKit 或 SwiftUI，包括：

- 状态枚举；
- 辅助功能快照模型；
- 控件分类规则；
- 状态判断规则；
- JSON 协议模型；
- 文字脱敏工具。

这部分可以只使用构造出的测试快照运行，不需要真的启动 ChatGPT。

## MacSignalSources

该模块负责与 macOS 交互：

- 检查和请求辅助功能权限；
- 根据 Bundle ID `com.openai.codex` 查找 ChatGPT；
- 使用 `AXObserver` 接收界面变化；
- 遍历辅助功能控件树。

控件树默认最多读取 5,000 个节点，最深 60 层，并记录已经访问的控件，避免循环引用。

## AgentStateRuntime

Runtime 把各模块组合起来，并负责：

- 应用启动、退出和前后台变化；
- 权限变化；
- 自动开始和停止观察；
- 通知触发的刷新；
- 定时兜底刷新；
- 后台扫描和重复请求合并；
- `completed` 的 4 秒保持；
- 状态文件、socket 和内存回调。

Runtime 标记为 `@MainActor`。耗时的辅助功能扫描通过后台任务完成，扫描结果再回到主
actor 更新状态。

Runtime 只在状态发生变化时发布新事件，不会在每次扫描后重复写相同状态。

## AgentStateBridgeService

服务模块包含两种进程间接口：

- `StateSnapshotWriter` 原子写入最新 JSON；
- `UnixSocketStateServer` 推送逐行 JSON。

两者使用相同的 `AgentStateEnvelope`，因此消费者可以使用 `sequence` 合并来源并去重。

## AgentStateInspector

Inspector 是一个 SwiftUI 诊断工具，用于：

- 引导辅助功能授权；
- 显示当前状态；
- 查看脱敏后的控件树；
- 搜索控件；
- 回看通知和状态转换。

Inspector 不包含独立的状态识别实现，它直接使用 `AgentStateRuntime`，避免诊断版本和
嵌入版本出现两套不同逻辑。

## 状态判断原则

状态规则尽量使用两个互相补充的线索。例如：

```text
准确文字“正在思考”
        +
回答期间存在“停止”按钮
        =
reasoning
```

这样可以避免聊天正文中出现同样文字造成误判。规则不依赖动画颜色、屏幕坐标或辅助功能
树中的长路径。

## 扩展方式

若要支持其他应用，应增加新的信号来源和分类规则，不要把另一个应用的特殊判断直接塞进
ChatGPT 适配器。核心协议可以继续共用。

增加新状态时需要：

1. 先确认界面上存在稳定信号；
2. 为误判场景写测试；
3. 保持旧字段含义不变；
4. 必要时增加 `schemaVersion`；
5. 更新 Swift 和 JavaScript 消费者测试。

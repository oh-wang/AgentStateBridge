# AgentStateBridge

AgentStateBridge 是一个 macOS 本地状态桥。它通过系统“辅助功能”接口观察
Codex 桌面应用，把界面变化整理成简单、稳定的状态，供桌宠、菜单栏工具、
灯效或其他本地程序使用。

当前版本实际支持 Codex macOS 客户端，可以识别：

- `inactive`：Codex 没有运行；
- `idle`：等待输入；
- `composing`：用户正在输入；
- `reasoning`：回答正文出现前，界面显示“正在思考”；
- `working`：正在输出回答；
- `completed`：刚刚完成；
- `unknown`：暂时无法判断。

这是一个非官方项目，与 OpenAI 没有从属或授权关系。Codex 是其各自权利人的商标。

## 当前兼容范围

目前只在 Codex macOS 客户端的**简体中文界面**完成了真实使用验证。

代码中预留了一些英文控件名称，并有对应的单元测试，但还没有在英文版 Codex
界面中实际验证。繁体中文和其他语言也尚未适配。因此，当前可以确认支持的是：

```text
macOS + Codex 简体中文界面
```

其他语言环境可能部分可用，但不应视为正式支持。若 Codex 更新界面结构或控件名称，
也可能需要调整识别规则。

## 工作方式

```text
Codex 窗口
    ↓
macOS Accessibility API
    ↓
识别输入框、停止按钮和“正在思考”等界面信号
    ↓
状态判断
    ↓
内存回调 / state.json / Unix socket
```

程序不会向 Codex 注入代码，不会控制鼠标键盘，也没有网络上传功能。
它会在本机内存中检查辅助功能控件属性，但默认不保存或传输聊天正文。
详细说明见[隐私说明](docs/PRIVACY.zh-CN.md)。

## 系统要求

- macOS 14 或更高版本；
- 安装完整 Xcode；
- Swift 6.2 或兼容版本；
- 为 Agent State Inspector 开启 macOS“辅助功能”权限；
- 正在运行的 Codex macOS 客户端。

## 构建和运行

```bash
git clone <仓库地址>
cd AgentStateBridge
./scripts/build-app.sh
open .build/AgentStateInspector.app
```

第一次运行时，按照应用内提示前往：

```text
系统设置 → 隐私与安全性 → 辅助功能
```

允许 Agent State Inspector 后返回应用。权限和 Codex 都准备好后，观察会自动开始。

构建脚本会生成一个本地临时签名的应用。它适合开发和自行编译，不是经过 Apple
Developer ID 签名、公证的正式安装包。

## 给其他程序使用

最新状态保存在：

```text
~/Library/Application Support/AgentStateBridge/state.json
```

实时状态变化通过以下 Unix socket 发送：

```text
~/Library/Application Support/AgentStateBridge/bridge.sock
```

`state.json` 用来回答“现在是什么状态”，socket 用来通知“刚刚发生了什么变化”。
同一个 Swift 进程也可以直接使用 `AgentStateRuntime` 的回调，不必经过文件或 socket。

协议格式、JavaScript 示例和断线恢复方式见
[本地状态接口](docs/PROTOCOL.zh-CN.md)。

## 作为 Swift Package 使用

仓库提供以下模块：

- `AgentStateCore`：状态、协议模型和判断规则；
- `MacSignalSources`：Codex 进程查找、辅助功能读取和变化通知；
- `AgentStateBridgeService`：JSON 文件与 Unix socket；
- `AgentStateRuntime`：把观察、判断和输出串起来的无界面运行模块；
- `AgentStateInspector`：用于授权、观察和诊断的 macOS 应用；
- `AgentStatePet`：根据状态播放 GIF 动画的透明桌宠应用；
- `AgentStateExampleConsumer`：读取状态文件的命令行示例。

`AgentStateRuntime` 不依赖 SwiftUI，可以嵌入其他 macOS 应用。

## 运行桌宠

仓库包含一个独立的透明桌宠应用。它复用 `AgentStateRuntime`，不会复制状态判断逻辑，
也不会上传聊天内容：

```bash
./scripts/build-pet-app.sh release
open .build/AgentStatePet.app
```

桌宠窗口首次启动时默认位于当前屏幕右下角，置顶、透明、可拖动，不占用 Dock 图标。
右键桌宠可以退出；Codex 退出时桌宠也会自动退出。动画映射如下：

| 状态 | 动画 |
|---|---|
| `idle` | `06.gif`，微笑待机 |
| `composing` | `05.gif`，集中输入 |
| `reasoning` | `04.gif`，阅读思考 |
| `working` | `01.gif`，持续输出 |
| `completed` | `03.gif`，完成后放松 |
| `inactive` | `02.gif`，未运行动作 |
| `unknown` | `06.gif`，启动过渡待机 |

第一次运行仍需在“系统设置 → 隐私与安全性 → 辅助功能”中允许 **Agent State Pet**。
允许后重新启动桌宠，它会自动观察 Codex（当前正式验证范围仍是简体中文界面）。

### 与 Codex 一键启动

桌宠提供一个只打开桌宠的脚本，适合放进 macOS“快捷指令”的 Codex 启动自动化：

```bash
./scripts/launch-pet.sh
```

配置方式：

1. 在“快捷指令”中创建个人自动化，选择 **Codex**，触发条件选“打开时”；
2. 添加“运行 Shell 脚本”操作，执行仓库中的 `scripts/launch-pet.sh`；
3. 关闭“运行前询问”，保存自动化。

桌宠启动后会先显示默认动画；Codex 打开并获得辅助功能权限后，会自动切换到对应状态动画。

## 测试

Swift 测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

JavaScript 示例测试：

```bash
node --test examples/agent-state-controller.test.mjs
```

## 当前限制

- 目前只实现了 Codex macOS 客户端适配器；
- 目前只在 Codex 简体中文界面完成真实验证；
- 状态识别依赖 Codex 暴露的辅助功能控件，客户端更新后可能需要调整规则；
- `completed` 会保留最多 4 秒，方便消费者显示完成动作；
- 程序异常退出后，`state.json` 可能暂时保留最后一次状态；
- 尚未提供生产者心跳或存活标记；
- 多窗口、网络搜索、工具调用、错误和手动停止还没有独立状态。

这些限制不会影响当前基本状态识别，但接入方应把 `unknown` 当作正常情况处理。

## 文档

- [架构说明](docs/ARCHITECTURE.zh-CN.md)
- [开发与运行](docs/DEVELOPMENT.zh-CN.md)
- [本地状态接口](docs/PROTOCOL.zh-CN.md)
- [隐私说明](docs/PRIVACY.zh-CN.md)
- [版本变化](CHANGELOG.md)

## 许可证

本项目使用 [MIT License](LICENSE)。

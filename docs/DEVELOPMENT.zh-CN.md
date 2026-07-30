# 开发与运行说明

## 开发环境

需要：

- macOS 14 或更高版本；
- 完整 Xcode；
- Swift 6.2 或兼容版本；
- ChatGPT macOS 客户端。

先进入仓库根目录：

```bash
cd AgentStateBridge
```

## 构建检查器

```bash
./scripts/build-app.sh
```

生成位置：

```text
.build/AgentStateInspector.app
```

启动：

```bash
open .build/AgentStateInspector.app
```

脚本默认使用 `/Applications/Xcode.app` 中的完整工具链。可以通过 `DEVELOPER_DIR`
改用其他 Xcode。

脚本只做本地临时签名。重新构建和签名后，macOS 可能要求再次确认辅助功能权限。

## 第一次运行

1. 点击“请求权限”；
2. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Agent State Inspector；
3. 回到检查器，重新检查权限；
4. 打开 ChatGPT；
5. 检查器会自动开始观察。

左侧显示 ChatGPT 暴露的辅助功能控件，右侧显示通知和最近的状态变化。
“重新读取”会立即启动一次新检查。

检查器默认隐藏文字。临时开启“显示控件名称”只应用于当前运行，用于研究按钮名称；
不要在包含私人对话的环境中截图或分享诊断界面。

## 运行测试

Swift：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
swift test --disable-sandbox
```

JavaScript：

```bash
node --test examples/agent-state-controller.test.mjs
```

Unix socket 测试需要系统允许测试进程创建本地 socket。在额外限制网络或进程通信的
沙箱中，这类测试可能因为 `EPERM` 失败；这不等同于状态判断代码失败。

## 运行示例消费者

读取一次当前状态：

```bash
swift run AgentStateExampleConsumer
```

持续读取：

```bash
swift run AgentStateExampleConsumer --watch
```

读取仓库中的模拟状态：

```bash
swift run AgentStateExampleConsumer --file examples/mock-state.json
```

## 调试状态识别

程序同时依靠系统通知和主动检查：

- 收到相关界面通知后，约 75 毫秒后检查；
- `reasoning` 或 `working` 时，每 150 毫秒检查；
- 其他状态下，每 500 毫秒检查。

扫描在后台执行。短时间重复发来的刷新请求会被合并，避免多个完整扫描同时运行。

需要研究新控件时：

1. 临时显示控件名称；
2. 在 ChatGPT 中触发目标功能；
3. 找出出现和消失的控件；
4. 优先使用准确文字、控件类型或 identifier；
5. 增加第二个保护条件，避免聊天正文导致误判；
6. 同时编写命中和不应命中的测试；
7. 用真实 ChatGPT 界面验证。

更详细的方法见[界面组件识别经验](COMPONENT-DETECTION.zh-CN.md)。

## 发布安装包

仓库当前适合发布源码。若要直接提供可下载的 `.app`，还需要：

- 自己控制的稳定 Bundle ID；
- Apple Developer ID 签名；
- Hardened Runtime；
- Apple 公证；
- 在干净的 macOS 用户环境中测试首次授权流程。

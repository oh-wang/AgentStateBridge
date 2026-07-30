# 本地状态接口

当前协议版本为 1。

## 状态文件

最新状态写入：

```text
~/Library/Application Support/AgentStateBridge/state.json
```

目录权限是 `0700`，文件权限是 `0600`。默认情况下只有当前 macOS 用户可以访问。

示例：

```json
{
  "schemaVersion": 1,
  "sequence": 42,
  "timestamp": "2026-07-27T12:00:00+08:00",
  "application": {
    "id": "chatgpt",
    "bundleId": "com.openai.codex",
    "version": "26.721.41059"
  },
  "state": "working",
  "previousState": "reasoning",
  "confidence": 0.96,
  "evidence": [
    "stop-button-present"
  ]
}
```

消费者至少需要处理：

- `schemaVersion`；
- `sequence`；
- `state`；
- `previousState`。

其他字段可用于调试。消费者应忽略不认识的额外字段，这样协议以后增加内容时，
旧版消费者仍能工作。

## 状态值

| 值 | 含义 |
|---|---|
| `inactive` | ChatGPT 没有运行 |
| `idle` | 等待输入 |
| `composing` | 用户正在输入 |
| `reasoning` | 回答正文出现前正在思考 |
| `working` | 正在生成回答 |
| `completed` | 刚刚完成 |
| `unknown` | 当前无法可靠判断 |

`completed` 最多保留 4 秒。新输入或新回答可以立即打断它。

## 为什么不会读到半个 JSON

程序先写好临时文件，再让系统用新文件整体替换旧文件。消费者只会读到完整的旧状态
或完整的新状态，不会读到写了一半的 JSON。这个过程叫作“原子替换”。

监听文件变化时应监听父目录，因为原子替换会创建新的文件节点，不要一直持有旧文件句柄。

## 实时 Unix socket

socket 位置：

```text
~/Library/Application Support/AgentStateBridge/bridge.sock
```

socket 权限为 `0600`，只供本机当前用户使用。

每个状态是一行完整 JSON，行尾为换行符：

```text
{"schemaVersion":1,"sequence":42,"state":"reasoning",...}\n
{"schemaVersion":1,"sequence":43,"state":"working",...}\n
```

系统可能把一行拆成多次读取，也可能把多行合并到一次读取中。因此客户端必须先把数据
放进缓冲区，再按换行符切分。

新客户端连接后，服务会先发送最近一次状态，随后发送每次变化。断线后应自动重连，
同时继续用 `state.json` 恢复当前状态。

## `sequence` 的作用

每次发布新状态，`sequence` 都会增加。程序重启时会读取旧状态文件，并从上次序号之后
继续计数。

同时使用文件和 socket 时，消费者可能从两个来源收到同一状态。只处理比当前
`sequence` 更大的状态即可去重。

## JavaScript 控制器

仓库中的：

```text
examples/agent-state-controller.mjs
```

已经处理：

- 启动时读取状态文件；
- socket 按行拆分；
- socket 自动重连；
- 监听目录变化；
- 每 250 毫秒检查文件作为兜底；
- 使用 `sequence` 去重；
- 检查协议版本和状态值；
- `start()` 与 `stop()` 生命周期。

使用示例：

```js
import { AgentStateController } from "./agent-state-controller.mjs";

const controller = new AgentStateController();

controller.on("state", (snapshot) => {
  console.log(snapshot.state);
});

controller.on("error", (error) => {
  console.error(error);
});

await controller.start();
```

这段代码需要 Node.js 环境，例如 Electron 主进程、Tauri sidecar 或本地服务。
普通网页不能直接访问本机文件和 Unix socket。

## Swift 同进程接口

嵌入 macOS 应用时，可以创建 `AgentStateRuntime`，通过 `onSnapshot` 直接接收：

```swift
let runtime = AgentStateRuntime(
    configuration: .init(enablesExternalSocket: false)
)

runtime.onSnapshot = { snapshot in
    print(snapshot.sequence, snapshot.state)
}

runtime.start()
```

该回调运行在主 actor。调用方应在应用退出或不再需要状态时调用 `stop()`。

## 接口选择

```text
同一个进程：优先使用 AgentStateRuntime 回调
不同的本地进程：Unix socket + state.json
只需要偶尔查看：只读取 state.json
```

`state.json` 是最新状态快照，不是完整历史记录。Unix socket 也不保证消费者离线时保留
所有事件；重新连接后应以服务器发送的最新状态为准。

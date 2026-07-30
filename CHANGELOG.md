# Changelog

本项目的主要变化会记录在这里。

## 0.1.0

首次公开版本：

- 通过 macOS Accessibility API 观察 ChatGPT；
- 在 ChatGPT 简体中文界面完成真实状态验证；
- 支持 `inactive`、`idle`、`composing`、`reasoning`、`working`、
  `completed` 和 `unknown`；
- 提供可嵌入的 `AgentStateRuntime`；
- 原子写入 `state.json`；
- 通过本地 Unix socket 实时发送状态；
- 提供 Swift 和 JavaScript 示例消费者；
- 默认对诊断文字进行脱敏；
- 提供 Agent State Inspector 诊断应用。

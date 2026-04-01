## Why

当前流程允许开发者在 Lookin 中检查 iOS UI，但 LLM agent 仍然无法获得足够完整的实时 UI 现场，因此没法可靠判断布局质量。我们需要一个范围克制的 MVP，通过 MCP 暴露截图和布局证据，让 Codex CLI 能像开发者一样分析当前界面。

## What Changes

- 增加一个面向 MCP 的 app session 流程，用于发现可检查的 iOS app，并在 bridge 中维护一个当前激活的目标 app。
- 增加一个 UI snapshot 流程，返回当前选中 app 的截图、可见 view controller、命中的 view，以及从 Lookin 模型提炼出的布局证据。
- 引入一套面向 LLM 的 JSON 返回格式，对 hierarchy 做裁剪并对 constraints 做摘要，而不是直接暴露 Lookin GUI 内部状态。
- 将 MVP 限定为只读检查能力，不包含属性修改、方法调用或 3D 预览控制。

## Capabilities

### New Capabilities
- `lookin-app-session`：发现可检查的 app，并维护后续 MCP 请求所依赖的激活 app 选择。
- `ui-snapshot-capture`：抓取带截图的 UI 快照，并提供 view 匹配、层级摘录和布局摘要，供 LLM 分析使用。

### Modified Capabilities

## Impact

- 需要新增一个 macOS bridge 层，在不依赖桌面 GUI 的前提下复用 Lookin 的连接与 session 逻辑。
- 需要基于 Lookin 的共享模型增加 MCP tool 定义与 JSON 适配层，包括 app info、hierarchy、display item、detail 和 auto-layout 元数据。
- 需要实现针对 `vc_name`、`ivar_name`、`class_name` 与 `text` 的匹配与摘要逻辑。

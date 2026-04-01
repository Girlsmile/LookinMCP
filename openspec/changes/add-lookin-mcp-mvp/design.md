## Context

Lookin 已经解决了最困难的运行时问题：从 macOS 连接 debug iOS app、拉取 hierarchy、拉取 detail payload，并通过共享模型序列化截图和布局元数据。当前缺的不是“检查能力”本身，而是一层面向机器的 bridge，让 MCP 客户端不需要驱动 Lookin GUI 也能请求一个聚焦过的 UI snapshot。

MVP 的目标刻意保持收敛。它必须让 Codex CLI 能够：

- 发现当前可检查的 app
- 选中一个激活 app
- 请求带截图的 UI snapshot
- 用确定性的过滤条件匹配 view
- 收到包含布局证据的裁剪后 JSON 结果

MVP 不应修改目标 app，也不应复刻完整的 Lookin 桌面行为。

## Goals / Non-Goals

**Goals:**
- 从 macOS 侧复用现有 Lookin 的连接与共享模型逻辑。
- 为 app 发现、app 选择和 UI snapshot 抓取提供稳定的只读 MCP 接口。
- 返回面向 LLM 推理优化的 JSON schema，而不是桌面渲染专用结构。
- 让第一版实现足够小，能在扩大协议或 GUI 改造前验证价值。

**Non-Goals:**
- 不追求与 Lookin 桌面版完全一致。
- 不包含属性编辑、方法调用、手势开关等修改型操作。
- 不包含 3D 预览、导出流程或仅桌面 GUI 需要的 AppKit 交互。
- 不做超出确定性过滤条件的自然语言模糊检索。
- MVP 阶段不重做 iOS 侧协议。

## Decisions

### 1. Build the MVP as a macOS-native bridge, not a JavaScript protocol reimplementation

现有协议基于 `Lookin_PTChannel` 和 `NSSecureCoding` 对象图。直接在 Node 里重写这一套会额外引入 secure decoding、版本兼容和二进制 payload 处理风险。bridge 应保留在 macOS 原生代码中消费 Lookin 模型，只向 MCP 暴露干净的 JSON。

Alternative considered:
- 在 JavaScript 中重写协议。MVP 阶段拒绝此方案，因为在产品形态尚未验证前，它会重复实现脆弱的底层逻辑。

### 2. Split the MVP into two capabilities: app session and UI snapshot capture

App discovery/selection and snapshot capture are related but distinct concerns. Separating them keeps specs clear:
app 发现/选择与 snapshot 抓取相关，但职责不同。拆开后 spec 边界更清晰：

- `lookin-app-session` 负责发现与激活目标 app 的选择。
- `ui-snapshot-capture` 负责 snapshot 返回结构与匹配行为。

Alternative considered:
- 使用一个大而全的 `lookin-mcp` capability。拒绝原因是这会模糊需求边界，并让后续演进更困难。

### 3. Keep the MVP read-only and single-session

bridge 一次只维护一个选中的 app，只暴露检查型流程。这样能让失败模式更可预测，也避免过早引入并发选择、修改回滚和 agent 安全边界的问题。

Alternative considered:
- 支持多 app 或多 session 控制。MVP 阶段拒绝，因为核心故事是“检查我当前正在调试的 app”。

### 4. Use a target-aware snapshot payload instead of returning the full hierarchy

原始 Lookin hierarchy 体积大且噪音多。bridge 应该：

- 按 `vc_name`、`ivar_name`、`class_name` 和 `text` 做可选过滤
- 以确定性规则计算命中的 view
- 返回命中节点、祖先链、附近兄弟节点和直接子节点
- 返回一个有边界的 tree excerpt，而不是完整 hierarchy

这样既能让返回结果对 LLM 有用，也能控制体积。

Alternative considered:
- 每次都返回完整 hierarchy。拒绝原因是 token 成本更高，模型推理质量反而更差。

### 5. Derive a stable JSON view model from Lookin models

MCP contract 不应直接镜像 Objective-C 原始模型。bridge 应把 Lookin 对象映射为下列 JSON 字段：

- app 元数据
- 可见 view controller
- screenshot
- 命中 view 的摘要
- frame / bounds / visibility
- intrinsic size、hugging、compression resistance
- constraint 摘要
- diagnostic notes

Alternative considered:
- 直接暴露 Lookin 原始对象或桌面导向结构。拒绝原因是它们包含过多额外状态，并把 MCP contract 绑死在 GUI 内部实现上。

### 6. Constraint summaries should be bridge-derived, but retain raw metadata fields needed for reasoning

Lookin 已经暴露了约束结构。bridge 应保留 `effective`、`active`、`priority`、`identifier` 等元数据，同时补充可读的 `summary` 字符串供 LLM 使用。这样既保留稳定的机器字段，也有紧凑的人类可读输出。

Alternative considered:
- 只返回可读字符串。拒绝原因是会丢失有价值的结构化数据。

## Risks / Trade-offs

- [协议耦合] -> bridge 依赖 Lookin 内部协议和模型兼容性。缓解方式：将 bridge 保持在同一套原生代码边界内，并随仓库一起版本化。
- [缺少稳定目标标识] -> `accessibilityIdentifier` 看起来不在当前数据通路中。缓解方式：MVP 先支持 `vc_name`、`ivar_name`、`class_name` 和 `text`，标识符支持后补。
- [payload 过大] -> 截图和 hierarchy 数据可能很重。缓解方式：裁剪 hierarchy、限制 match 数量，并让 screenshot 可配置。
- [连接不稳定] -> 选中的 app 可能断开或进入后台。缓解方式：显式定义无选择、断开连接和后台不可用等 MCP 错误。
- [桌面耦合] -> 某些 Lookin 代码路径默认依赖 GUI 时代假设。缓解方式：围绕 connection/session/shared-model 层隔离 bridge 代码，避免依赖 AppKit controller。

## Migration Plan

1. 引入一个原生 bridge target 或 module，在不启动桌面 GUI 的前提下复用 Lookin 的 connection 与 shared-model 代码。
2. 先实现 app session 流程，让 MCP 能稳定发现并选择目标 app。
3. 在选中的 app session 之上实现 snapshot 抓取与 JSON 转换。
4. 增加 `list_apps`、`select_app` 和 `capture_ui_snapshot` 的 MCP stdio transport 与 tool handler。
5. 至少在一个 simulator app 和一个真机连接 app 上完成验证，再扩大范围。

回滚相对直接，因为 MVP 是新增 bridge 能力，而不是修改 iOS app 内现有的检查行为。必要时可以移除 bridge target，而不影响现有 Lookin 桌面用法。

## Open Questions

- 原生 bridge target 应使用 Objective-C、Swift，还是采用包裹现有 Objective-C 连接层的混合 target？
- screenshot 在第一版中应以内联 base64 形式返回，还是在首个可用版本后改成 MCP resource 语义？
- 如果 bridge 实现中发现低风险采集路径，是否要把 `accessibilityIdentifier` 一并纳入 MVP？

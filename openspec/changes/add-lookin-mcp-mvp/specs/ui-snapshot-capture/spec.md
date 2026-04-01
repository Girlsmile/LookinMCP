## ADDED Requirements

### Requirement: MCP can capture a screenshot-backed UI snapshot
系统 SHALL 提供一个 MCP 能力，为当前选中的 app 返回一个适合 LLM 消费的、带截图的 UI snapshot。

#### Scenario: Capture current UI snapshot
- **WHEN** MCP 客户端为一个有效激活 app 请求 snapshot
- **THEN** 系统返回 app 元数据以及在可获取时的可见 view controller 名称
- **AND** 当启用截图返回时，系统返回 screenshot
- **AND** 系统返回一个适合 LLM 分析的 hierarchy excerpt

### Requirement: Snapshot capture supports deterministic view matching filters
系统 SHALL 支持针对 `vc_name`、`ivar_name`、`class_name` 和 `text` 的确定性 view 匹配过滤条件。

#### Scenario: Match by view controller and ivar
- **WHEN** MCP 客户端提供 `vc_name` 和 `ivar_name` 过滤条件
- **THEN** 系统将匹配范围限制在与该 view controller 关联的 views 上
- **AND** 系统只返回 ivar trace 可用且与请求 ivar 名匹配的 views

#### Scenario: Match by class or text
- **WHEN** MCP 客户端提供 `class_name` 或 `text` 过滤条件
- **THEN** 系统返回元数据符合这些条件的 views
- **AND** 返回的命中数量不超过请求值或默认上限

### Requirement: Snapshot responses include layout evidence for matched views
系统 SHALL 为每个命中的 view 返回进行 UI 分析所需的布局证据。

#### Scenario: Return view layout fields
- **WHEN** 有一个或多个 view 命中 snapshot 过滤条件
- **THEN** 每个命中的 view 都包含 frame 与 bounds 信息
- **AND** 每个命中的 view 都包含 hidden 与 alpha 状态
- **AND** 在可获取时，每个命中的 view 都包含 intrinsic content size
- **AND** 在可获取时，每个命中的 view 都包含 hugging 和 compression resistance priority
- **AND** 在可获取时，每个命中的 view 都包含结构化的 auto-layout constraint 元数据以及可读的约束摘要

### Requirement: Snapshot responses are pruned for LLM consumption
系统 SHALL 返回一个有边界的 hierarchy excerpt，而不是完整的原始 hierarchy。

#### Scenario: Return excerpt around matched views
- **WHEN** 一个 snapshot 请求命中了若干 views
- **THEN** hierarchy excerpt 包含这些命中的 views
- **AND** excerpt 包含将这些命中项放回上下文所需的祖先链
- **AND** excerpt 包含布局推理所需的附近兄弟节点或直接子节点

#### Scenario: No views match filters
- **WHEN** 一个 snapshot 请求没有命中任何 views
- **THEN** 系统返回空的 `matches` 列表
- **AND** 在可获取时，系统仍返回可见 view controller 名称
- **AND** 系统返回一个有边界的当前页面 hierarchy excerpt，而不是直接让请求失败

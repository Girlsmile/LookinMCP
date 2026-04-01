## ADDED Requirements

### Requirement: MCP 可以读取最新的本地 snapshot
系统 SHALL 提供一个 MCP 能力，用于读取本地 snapshot 目录中的最新 UI 现场。

#### Scenario: 读取 current snapshot
- **WHEN** MCP 客户端请求最新 snapshot
- **THEN** 系统读取约定 `current` 目录中的 `snapshot.json`
- **AND** 系统返回适合 LLM 消费的结构化结果

#### Scenario: 当前没有 snapshot
- **WHEN** `current` 目录不存在或其中没有可读取的 `snapshot.json`
- **THEN** 系统返回明确的 `NO_SNAPSHOT_AVAILABLE` 风格错误

### Requirement: MCP 可以列出本地可用 snapshot
系统 SHALL 提供一个 MCP 能力，用于列出当前可用的 snapshot，至少包含当前快照和可选历史快照。

#### Scenario: 列出 snapshot 清单
- **WHEN** MCP 客户端请求 snapshot 列表
- **THEN** 系统返回 0 个或多个 snapshot 条目
- **AND** 每个条目都包含可唯一标识该 snapshot 的 `snapshot_id`
- **AND** 每个条目都包含 `captured_at` 及基本 app 元数据

### Requirement: MCP 可以对 snapshot 执行确定性查询
系统 SHALL 支持对已读取的 snapshot 使用 `vc_name`、`ivar_name`、`class_name` 和 `text` 进行确定性查询。

#### Scenario: 按 view controller 与 ivar 查询
- **WHEN** MCP 客户端对某个 snapshot 提供 `vc_name` 与 `ivar_name`
- **THEN** 系统只返回同时满足这两个条件的命中 view

#### Scenario: 按 class 或 text 查询
- **WHEN** MCP 客户端对某个 snapshot 提供 `class_name` 或 `text`
- **THEN** 系统从 snapshot 中筛选符合条件的 view
- **AND** 返回的命中数不超过请求值或默认上限

### Requirement: 查询结果必须包含层级摘录与布局证据
系统 SHALL 在 snapshot 查询结果中返回足以支撑 UI 分析的 hierarchy excerpt 与 layout evidence。

#### Scenario: 查询命中 view
- **WHEN** 查询命中了一个或多个 view
- **THEN** 系统为每个命中项返回 frame、bounds、hidden、alpha 等基础布局字段
- **AND** 在可获取时返回 intrinsic size、hugging、compression resistance 和 constraint summary
- **AND** 系统返回围绕命中节点裁剪后的 hierarchy excerpt

#### Scenario: 查询未命中 view
- **WHEN** 查询没有命中任何 view
- **THEN** 系统返回空的 `matches`
- **AND** 系统仍返回当前页面的有边界 hierarchy excerpt
- **AND** 系统不因“未命中”而把请求视为失败

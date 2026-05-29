## ADDED Requirements

### Requirement: MCP 可以触发当前页面刷新

系统 SHALL 提供 `lookin.refresh` MCP tool，让 agent 能请求 Lookin Desktop 刷新当前 inspecting app 的 UI snapshot。

#### Scenario: 刷新当前 inspecting app

- **WHEN** MCP 客户端调用 `lookin.refresh`
- **AND** Lookin Desktop 当前存在有效 inspecting app
- **THEN** 系统触发当前 app 的 hierarchy reload
- **AND** 系统在刷新完成后导出新的 current snapshot
- **AND** tool 返回可用于后续查询的 snapshot id

#### Scenario: 当前没有可刷新 app

- **WHEN** MCP 客户端调用 `lookin.refresh`
- **AND** Lookin Desktop 当前没有有效 inspecting app
- **THEN** 系统返回明确错误
- **AND** 系统不要求 agent 打开 Lookin GUI 菜单选择 app

### Requirement: Refresh tool 必须返回明确完成阶段

系统 SHALL 支持等待 `hierarchy` 和 `details` 两类完成阶段，并在响应中返回实际完成阶段。

#### Scenario: 等待 hierarchy 阶段

- **WHEN** MCP 客户端调用 `lookin.refresh` 且 `wait_until` 为 `hierarchy`
- **THEN** 系统在 hierarchy reload 完成并导出 snapshot 后返回
- **AND** 响应中的 `phase` 为 `hierarchy` 或更完整阶段

#### Scenario: 等待 details 阶段

- **WHEN** MCP 客户端调用 `lookin.refresh` 且未显式指定 `wait_until`
- **THEN** 系统默认等待 detail/screenshot 补全稳定或确认没有待补全任务
- **AND** 系统在最终 snapshot 导出后返回
- **AND** 响应中的 `phase` 为 `details`

#### Scenario: 刷新超时

- **WHEN** MCP 客户端调用 `lookin.refresh` 且刷新未在 `timeout_ms` 内达到目标阶段
- **THEN** 系统返回超时结果或错误
- **AND** 响应包含已知的最新 `sid`、`prev_sid`、`phase`、`changed` 和 `ms`

### Requirement: Refresh tool 默认必须低 token

`lookin.refresh` SHALL 默认返回 ids-only 响应，只包含刷新完成与后续查询所需的最小字段。

#### Scenario: 默认低 token 响应

- **WHEN** MCP 客户端调用 `lookin.refresh` 且未指定 `mode`
- **THEN** 响应只包含 `ok`、`sid`、`prev_sid`、`phase`、`changed` 和 `ms` 等最小状态字段
- **AND** 响应不得内联 screen 摘要、节点摘要、截图元数据或重复 resource URI 模板

#### Scenario: brief 响应

- **WHEN** MCP 客户端调用 `lookin.refresh` 且 `mode` 为 `brief`
- **THEN** 系统 MAY 额外返回 `captured_at` 和 app 名称等短字段
- **AND** 系统仍不得返回 hierarchy、节点列表或截图正文

### Requirement: Refresh 后查询必须继续复用现有 snapshot tools

系统 SHALL 保持刷新动作和 snapshot 查询分离。

#### Scenario: 使用新 snapshot 查询

- **WHEN** `lookin.refresh` 返回新的 `sid`
- **THEN** MCP 客户端可以把该 `sid` 传给 `lookin.screen`、`lookin.find`、`lookin.inspect`、`lookin.capture` 或 resources/read
- **AND** 这些查询工具的既有低 token 行为保持不变

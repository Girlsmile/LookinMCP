## ADDED Requirements

### Requirement: MCP can discover inspectable apps
系统 SHALL 提供一个 MCP 能力，用于列出 macOS bridge 当前可发现的、可被检查的 iOS app。

#### Scenario: Discover connected apps
- **WHEN** MCP 客户端请求可用 app 列表
- **THEN** 系统返回 0 个或多个可检查的 app
- **AND** 每个返回的 app 都包含由 bridge 生成的 `app_id`
- **AND** 在可获取时，每个 app 都包含 app 名称、bundle identifier、设备描述和屏幕元数据

### Requirement: MCP can select an active app
系统 SHALL 允许 MCP 客户端选择一个可检查 app 作为后续 snapshot 请求的激活目标。

#### Scenario: Select a listed app
- **WHEN** MCP 客户端提交一个存在于最近发现结果中的 `app_id`
- **THEN** 系统将该 app 保存为当前激活选择
- **AND** 系统返回被选中 app 的元数据

#### Scenario: Reject an unknown app selection
- **WHEN** MCP 客户端提交一个 bridge 不认识的 `app_id`
- **THEN** 系统返回选择错误
- **AND** 当前激活 app 选择保持不变

### Requirement: Snapshot requests require a valid active app
系统 SHALL 在处理 snapshot 请求前，要求存在一个有效的激活 app 选择或显式提供一个有效的 `app_id`。

#### Scenario: No app selected
- **WHEN** MCP 客户端在没有激活 app 且没有显式有效 `app_id` 的情况下请求 snapshot
- **THEN** 系统返回一个 `NO_APP_SELECTED` 风格的错误

#### Scenario: Active app disconnects
- **WHEN** 发起 snapshot 请求时，当前激活 app 已无法连接
- **THEN** 系统返回一个 `APP_DISCONNECTED` 风格的错误
- **AND** bridge 清除或失效化这个过期的激活选择

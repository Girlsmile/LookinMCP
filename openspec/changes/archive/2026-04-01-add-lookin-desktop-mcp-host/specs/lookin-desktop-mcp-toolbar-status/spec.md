## ADDED Requirements

### Requirement: Lookin 顶部 toolbar 必须提供 MCP 状态入口
系统 SHALL 在 Lookin Desktop 顶部 toolbar 中提供一个 MCP 状态入口，供用户查看和操作桌面端 MCP 功能。

#### Scenario: 打开 Lookin 主窗口
- **WHEN** 用户进入 Lookin 的静态查看主窗口
- **THEN** 系统在顶部 toolbar 中显示 MCP 按钮
- **AND** 该按钮可反映当前 MCP 状态

#### Scenario: MCP 功能不可用
- **WHEN** 当前未启用 MCP host 或服务启动失败
- **THEN** MCP 按钮仍然可见
- **AND** 按钮状态与视觉反馈可以区分“未启用”和“错误”

### Requirement: MCP 状态必须同时体现服务健康度和 snapshot 新鲜度
系统 SHALL 使用统一状态模型表达 MCP 功能是否可用，而不是只展示“进程是否在运行”。

#### Scenario: 服务在线且 snapshot 新鲜
- **WHEN** 本地 MCP host 已启动，且当前 snapshot 在新鲜度阈值内
- **THEN** 系统展示 `ready` 或等价可用状态

#### Scenario: 服务在线但 snapshot 过期
- **WHEN** 本地 MCP host 已启动，但当前 snapshot 超过新鲜度阈值
- **THEN** 系统展示 `stale` 或等价状态
- **AND** 系统不把该状态误显示为完全正常

#### Scenario: 最近存在客户端请求
- **WHEN** 本地 MCP host 在最近一段时间内收到并成功处理请求
- **THEN** 系统展示 `connected` 或等价活跃状态

### Requirement: 点击 MCP 按钮必须展示可操作的详情面板
系统 SHALL 在用户点击 MCP 按钮后展示一个详情面板，而不是仅依赖图标颜色。

#### Scenario: 打开 MCP popover
- **WHEN** 用户点击 toolbar 中的 MCP 按钮
- **THEN** 系统展示一个 popover 或等价详情面板
- **AND** 面板中包含当前状态、服务地址、最近 snapshot 时间、最近请求时间和最近错误

#### Scenario: 用户需要复制连接信息
- **WHEN** 用户在 MCP 详情面板中选择复制连接地址
- **THEN** 系统将当前 localhost MCP 地址复制到剪贴板

### Requirement: MCP 状态入口必须支持显式启停
系统 SHALL 允许用户从桌面状态入口显式启动或停止本地 MCP host。

#### Scenario: 用户启动 MCP host
- **WHEN** 用户在 MCP 详情面板中执行启动操作
- **THEN** 系统进入启动流程
- **AND** 状态从 `off` 进入 `starting` 直至成功或失败

#### Scenario: 用户停止 MCP host
- **WHEN** 用户在 MCP 详情面板中执行停止操作
- **THEN** 系统停止本地 MCP host
- **AND** 状态进入 `off`

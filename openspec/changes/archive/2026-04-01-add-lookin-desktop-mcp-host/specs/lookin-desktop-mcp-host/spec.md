## ADDED Requirements

### Requirement: Lookin Desktop 必须托管本地 MCP host
系统 SHALL 允许 Lookin Desktop 在本机启动一个本地 MCP host，并通过固定 localhost 地址对外提供 MCP 服务。

#### Scenario: 启动本地 MCP host
- **WHEN** 用户启用 Lookin 的 MCP 功能
- **THEN** 系统启动一个由 Lookin Desktop 托管的本地 MCP host
- **AND** 系统对外暴露固定 localhost MCP 地址

#### Scenario: 停止本地 MCP host
- **WHEN** 用户关闭 Lookin 的 MCP 功能或 Lookin 即将退出
- **THEN** 系统停止本地 MCP host
- **AND** 系统释放对应的本地监听资源

### Requirement: 本地 MCP host 必须复用现有 snapshot reader 工具能力
系统 SHALL 通过本地 MCP host 暴露与现有 snapshot reader 一致的工具能力，而不是重新引入直连 iOS 端逻辑。

#### Scenario: 客户端通过本地 host 调用节点查询工具
- **WHEN** MCP 客户端连接本地 host 并调用节点定位、详情、关系或子树工具
- **THEN** 系统基于本地 snapshot 返回结构化结果
- **AND** 系统不要求客户端重新连接 iOS 设备或重新发现 app

#### Scenario: 当前没有可用 snapshot
- **WHEN** MCP 客户端调用本地 host，但当前没有可读取的 snapshot
- **THEN** 系统返回明确错误
- **AND** 错误语义与现有 snapshot reader 的错误风格保持一致

### Requirement: 本地 MCP host 必须使用稳定地址和可诊断错误
系统 SHALL 使用稳定的本地服务地址，并在服务无法启动时提供可诊断错误。

#### Scenario: 端口被占用
- **WHEN** Lookin 尝试启动本地 MCP host，但目标端口已被其他进程占用
- **THEN** 系统不静默切换到随机端口
- **AND** 系统记录并暴露明确的端口占用错误

#### Scenario: 客户端在 Lookin 重启后重连
- **WHEN** Lookin 完成一次重启并重新启动 MCP host
- **THEN** 系统继续使用同一个 localhost 地址
- **AND** 客户端可以基于该地址重新建立连接

### Requirement: 本地 MCP host 必须记录运行态元数据
系统 SHALL 记录足以支撑状态展示和诊断的运行态信息。

#### Scenario: 服务已收到请求
- **WHEN** 任意 MCP 客户端通过本地 host 成功发起一次请求
- **THEN** 系统记录最近一次成功请求时间
- **AND** 系统可将该信息提供给桌面状态展示层

#### Scenario: 服务请求失败
- **WHEN** 本地 host 处理请求或启动服务时发生错误
- **THEN** 系统记录最近错误摘要
- **AND** 系统可将该错误提供给桌面状态展示层

## MODIFIED Requirements

### Requirement: Lookin Desktop 必须托管本地 MCP host
系统 SHALL 允许 Lookin Desktop 在本机启动一个本地 MCP host，并通过固定 localhost 地址对外提供 MCP 服务。发布态必须优先使用 app bundle 内嵌的 `lookin-mcp` helper；开发态仍可使用环境变量或仓库内构建产物作为显式覆盖。

#### Scenario: 启动本地 MCP host
- **WHEN** 用户启用 Lookin 的 MCP 功能
- **THEN** 系统启动一个由 Lookin Desktop 托管的本地 MCP host
- **AND** 系统对外暴露固定 localhost MCP 地址

#### Scenario: 发布态使用内嵌 helper
- **WHEN** 用户运行安装后的发布态 Lookin.app 且 app bundle 中存在可执行的 `lookin-mcp` helper
- **THEN** 系统使用该内嵌 helper 启动本地 MCP host
- **AND** 系统不要求用户提供源码目录或手工构建产物路径

#### Scenario: 开发者显式覆盖 helper
- **WHEN** 开发者通过 `LOOKIN_MCP_EXECUTABLE` 提供一个有效 helper 路径
- **THEN** 系统使用该显式路径启动本地 MCP host
- **AND** 该覆盖行为优先于发布态默认内嵌路径

#### Scenario: 停止本地 MCP host
- **WHEN** 用户关闭 Lookin 的 MCP 功能或 Lookin 即将退出
- **THEN** 系统停止本地 MCP host
- **AND** 系统释放对应的本地监听资源

### Requirement: 本地 MCP host 必须使用稳定地址和可诊断错误
系统 SHALL 使用稳定的本地服务地址，并在服务无法启动时提供可诊断错误。除端口冲突外，系统还必须能区分 helper 缺失、helper 不可执行和 helper 启动失败等安装型错误。

#### Scenario: 端口被占用
- **WHEN** Lookin 尝试启动本地 MCP host，但目标端口已被其他进程占用
- **THEN** 系统不静默切换到随机端口
- **AND** 系统记录并暴露明确的端口占用错误

#### Scenario: 内嵌 helper 缺失或不可执行
- **WHEN** 发布态 Lookin 尝试启动本地 MCP host，但 app bundle 中的 `lookin-mcp` helper 缺失或不可执行
- **THEN** 系统启动失败
- **AND** 系统暴露明确的 helper 解析错误
- **AND** 错误可被桌面状态层或日志读取

#### Scenario: 客户端在 Lookin 重启后重连
- **WHEN** Lookin 完成一次重启并重新启动 MCP host
- **THEN** 系统继续使用同一个 localhost 地址
- **AND** 客户端可以基于该地址重新建立连接

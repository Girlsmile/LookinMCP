## MODIFIED Requirements

### Requirement: 本地 MCP host 必须复用现有 snapshot reader 工具能力
系统 SHALL 继续基于本地 snapshot 数据提供 Lookin 分析能力，但对外暴露方式必须符合 MCP 官方 primitives 分层，而不是只暴露工具列表。

#### Scenario: 客户端初始化本地 host
- **WHEN** MCP 客户端连接 Lookin Desktop 托管的本地 host 并完成 `initialize`
- **THEN** 系统在 capability 中同时声明 `tools`、`resources` 与 `prompts`
- **AND** 系统不要求客户端把所有分析数据都通过 `tools/call` 获取

#### Scenario: 客户端通过本地 host 读取分析上下文
- **WHEN** MCP 客户端需要读取 snapshot 原文、局部 subtree、截图或其他重数据
- **THEN** 系统允许客户端通过 `resources/list` 与 `resources/read` 获取这些内容
- **AND** 这些内容继续来源于本地 snapshot 数据，而不是重新建立 iOS 端直连流程

#### Scenario: 客户端通过本地 host 获取工作流模板
- **WHEN** MCP 客户端请求 Lookin 提供的 prompt 定义
- **THEN** 系统通过 `prompts/list` 与 `prompts/get` 返回可复用的 UI 分析模板
- **AND** prompt 中引用的分析入口与当前 tools/resources surface 保持一致

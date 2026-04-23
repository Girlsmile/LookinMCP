## MODIFIED Requirements

### Requirement: 工具返回必须默认采用 compact-first 协议
系统 SHALL 让分析工具默认返回紧凑摘要、关键证据与按需展开入口，而不是默认返回完整 snapshot 或整棵 subtree。

#### Scenario: 客户端使用默认参数检查节点
- **WHEN** MCP 客户端调用 `lookin.screen`、`lookin.find` 或 `lookin.inspect` 且未显式提升 detail 等级
- **THEN** 系统返回 compact 级别的结构化结果
- **AND** 返回中包含节点定位所需的最小标识、关键布局或样式证据，以及可进一步读取的 resource 引用
- **AND** 系统 SHOULD 在面向 LLM 的推荐路径中优先使用低 token mode，避免默认重复返回 resource 描述和未请求的证据字段

#### Scenario: 客户端显式请求更高细节等级
- **WHEN** MCP 客户端在工具调用中传入 `detail=standard` 或 `detail=full`
- **THEN** 系统在该工具定义允许的范围内增加返回字段
- **AND** 系统仍保持字段边界可预测，而不是退化为无上限原始转储

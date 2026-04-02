## ADDED Requirements

### Requirement: Lookin MCP 必须提供收敛后的分析工具面
系统 SHALL 以不超过 5 个高价值 tools 对外暴露 Lookin 分析能力，而不是继续暴露一组细粒度 snapshot reader tools。

#### Scenario: 客户端获取工具列表
- **WHEN** MCP 客户端请求 Lookin 的工具列表
- **THEN** 系统只暴露 `lookin.screen`、`lookin.find`、`lookin.inspect`、`lookin.capture` 与 `lookin.raw` 或等价数量不超过 5 的稳定工具集合
- **AND** 每个工具的职责边界清晰，不要求客户端串联多个细粒度旧工具才能完成一次基本分析

### Requirement: 工具返回必须默认采用 compact-first 协议
系统 SHALL 让分析工具默认返回紧凑摘要、关键证据与按需展开入口，而不是默认返回完整 snapshot 或整棵 subtree。

#### Scenario: 客户端使用默认参数检查节点
- **WHEN** MCP 客户端调用 `lookin.screen`、`lookin.find` 或 `lookin.inspect` 且未显式提升 detail 等级
- **THEN** 系统返回 compact 级别的结构化结果
- **AND** 返回中包含节点定位所需的最小标识、关键布局或样式证据，以及可进一步读取的 resource 引用

#### Scenario: 客户端显式请求更高细节等级
- **WHEN** MCP 客户端在工具调用中传入 `detail=standard` 或 `detail=full`
- **THEN** 系统在该工具定义允许的范围内增加返回字段
- **AND** 系统仍保持字段边界可预测，而不是退化为无上限原始转储

### Requirement: 重数据必须通过 resources 按需读取
系统 SHALL 将 snapshot 原文、局部 subtree、全屏截图与节点裁剪图等重数据通过 MCP resources 暴露。

#### Scenario: 客户端读取当前 snapshot 原文
- **WHEN** MCP 客户端浏览或读取当前 snapshot 的 raw resource
- **THEN** 系统返回当前 snapshot 的完整结构化内容
- **AND** 该内容可以在不调用额外分析工具的前提下被客户端按需消费

#### Scenario: 客户端读取节点局部子树或裁剪图
- **WHEN** MCP 客户端针对某个 `snapshot_id` 与 `node_id` 读取 subtree 或 capture resource
- **THEN** 系统返回与该节点绑定的局部树或局部截图内容
- **AND** 系统不要求工具默认内联同等体量的数据

### Requirement: 系统必须提供面向 UI 诊断的 prompts
系统 SHALL 提供可复用的 MCP prompts，用于引导客户端执行常见的 UI 布局和视觉分析工作流。

#### Scenario: 客户端获取 UI 诊断 prompts
- **WHEN** MCP 客户端请求 Lookin 的 prompt 列表
- **THEN** 系统返回至少覆盖布局分析、视觉样式分析或间距对齐分析的 prompt 模板
- **AND** 每个 prompt 明确说明所需参数以及推荐调用的 tool/resource 组合

#### Scenario: 客户端请求某个 prompt 的具体内容
- **WHEN** MCP 客户端请求某个已声明 prompt 的详细定义
- **THEN** 系统返回适合直接交给 LLM 的结构化说明
- **AND** 返回中不重复内联完整 snapshot 数据，而是引用相应工具与 resources

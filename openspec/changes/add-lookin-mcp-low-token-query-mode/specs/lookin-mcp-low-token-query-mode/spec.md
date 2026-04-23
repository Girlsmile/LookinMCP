## ADDED Requirements

### Requirement: Lookin MCP 必须支持低 token 查询模式
系统 SHALL 提供面向 LLM 的低 token 查询模式，使客户端可以用多次小查询替代一次大返回。

#### Scenario: 客户端以 ID 模式查找节点
- **WHEN** MCP 客户端调用 `lookin.find` 并传入 `mode=ids`
- **THEN** 系统返回 snapshot 标识、匹配总数和节点 ID 列表
- **AND** 返回中不默认内联 layout、style、relations、children 或 resource description

#### Scenario: 客户端以 brief 模式查看节点
- **WHEN** MCP 客户端调用 `lookin.inspect` 并传入 `mode=brief`
- **THEN** 系统返回节点 ID、class、raw class、host view controller 与 frame 摘要
- **AND** frame SHALL 使用数组形态 `[x, y, width, height]`
- **AND** 坐标值 SHOULD 限制到足够 UI 分析使用的精度

#### Scenario: 客户端显式请求证据模式
- **WHEN** MCP 客户端调用 `lookin.inspect` 并传入 `mode=evidence` 与 `include`
- **THEN** 系统只返回 include 指定的 evidence section
- **AND** 未指定的 section 不应出现在响应中

### Requirement: 低 token 响应必须使用稳定短字段
系统 SHALL 为低 token 模式提供稳定短字段 contract，避免每次响应重复长字段名。

#### Scenario: 客户端接收短字段节点摘要
- **WHEN** 系统返回低 token 节点摘要
- **THEN** 响应可以使用 `sid`、`id`、`cls`、`raw`、`vc`、`f`、`ch`、`p`、`n` 等短字段
- **AND** 字段含义必须在文档和 tool 描述中保持稳定

#### Scenario: 客户端需要可读响应
- **WHEN** 客户端未启用低 token mode 或显式请求现有 detail 模式
- **THEN** 系统继续支持现有可读字段名响应
- **AND** 不要求旧客户端理解短字段

### Requirement: 重复展开入口不得默认内联
系统 SHALL 在低 token 模式中避免默认返回重复的 resource link 描述。

#### Scenario: 客户端查看节点 brief
- **WHEN** 系统返回 `mode=brief` 的节点结果
- **THEN** 响应不应默认包含完整 `resource_links` 数组
- **AND** 客户端可以通过固定 URI 模板读取 layout、style、relations、children、siblings、subtree 或 capture

#### Scenario: 客户端读取 section resource
- **WHEN** 客户端读取 `lookin://snapshots/{sid}/nodes/{id}/{section}` 形式的 resource
- **THEN** 系统返回对应 section 的结构化内容
- **AND** 不混入未请求的其他 section 证据

### Requirement: 列表型 section 必须支持分页
系统 SHALL 为 children、siblings 和 subtree 等列表型 section 提供分页或游标能力。

#### Scenario: 客户端读取 children section
- **WHEN** 客户端读取 children resource 并传入 `limit`
- **THEN** 系统最多返回 `limit` 个子节点摘要
- **AND** 如果存在更多结果，系统返回可继续读取的 `next` cursor

#### Scenario: 客户端继续读取列表 section
- **WHEN** 客户端使用上一页返回的 cursor 再次读取同一 section
- **THEN** 系统返回下一批稳定排序的结果
- **AND** cursor 不暴露本地文件路径或不稳定内存地址

### Requirement: 低 token 模式必须有可验证的预算收益
系统 SHALL 通过自动化测试验证低 token 查询模式相对当前 compact 响应具有明确收益。

#### Scenario: 典型节点查询 token 预算测试
- **WHEN** 测试使用固定 snapshot 调用 `lookin.find mode=ids` 与 `lookin.inspect mode=brief`
- **THEN** 响应 token 或字节数 SHALL 显著低于当前 compact 查询路径
- **AND** 目标节约比例 SHOULD 不低于 50%

## Why

当前 Lookin MCP 已经能返回本地 snapshot 数据，但能力面主要堆在细粒度 tools 上，默认返回内容也偏重，导致 LLM 在一次任务里很容易拿到过多上下文。MCP 官方更鼓励将“动作”放到 tools，把大块上下文放到 resources，把可复用工作流放到 prompts，因此需要对现有 surface 做一次正式收敛。

```mermaid
flowchart LR
    A[现状: 多个细粒度 tools] --> B[默认返回大量 JSON]
    B --> C[LLM 上下文成本偏高]
    C --> D[需要按官方 primitives 重构]
```

## What Changes

- 将现有 Lookin MCP 对外 surface 收敛为 5 个以内的高价值 tools，并统一采用 compact-first 返回策略。
- 新增面向 snapshot、subtree、screenshot 与 raw export 的 MCP resources，让大对象通过按需读取暴露。
- 新增面向 UI 排查的 prompts，把“分析间距/颜色/层级”等工作流做成模板。
- 调整 tool 返回协议，优先返回摘要、证据字段和 resource 引用，而不是默认返回整棵树。
- **BREAKING** 移除或替换现有细粒度 snapshot reader tools，客户端需要迁移到新的 tool/resource/prompt surface。

## Capabilities

### New Capabilities
- `lookin-mcp-analysis-surface`: 定义 Lookin 面向 LLM 的官方 MCP surface，包括收敛后的 tools、按需读取的 resources 与工作流 prompts。

### Modified Capabilities
- `lookin-desktop-mcp-host`: 调整桌面端 host 的能力声明与请求处理逻辑，使其不再只暴露工具列表，而是同时声明 tools、resources 和 prompts。

## Impact

- 影响 `Sources/LookinMCPServer` 中的 MCP 协议处理、tool 注册和返回 schema。
- 影响 snapshot 适配层，需要新增 compact 摘要、resource URI 与 prompt 参数组装逻辑。
- 影响桌面端 host 的 capability 宣告、README、安装接入文档以及面向客户端的调用示例。

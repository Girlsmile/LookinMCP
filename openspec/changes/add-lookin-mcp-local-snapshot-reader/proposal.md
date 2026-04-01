## Why

当前 Lookin 桌面版已经能稳定连接 iOS App 并展示完整 UI 信息，但我们之前尝试让 MCP 直接连接 iOS 端时，会和 Lookin 桌面版争抢唯一连接，导致桌面版与 MCP 不能同时工作。更稳妥的方向是让 mac 端先把当前界面的截图、层级和布局证据整理为本地 snapshot，再由 MCP 只读这些本地产物。

```mermaid
flowchart LR
    A[Lookin mac 端已连接 App] --> B[导出本地 snapshot]
    B --> C[MCP 读取 snapshot 文件]
    C --> D[LLM 分析 UI]
```

## What Changes

- 增加一个 mac 端本地 snapshot 产物格式，统一保存当前 app 元数据、可见页面信息、层级摘录、布局证据和截图路径。
- 增加一个面向本地 snapshot 的 MCP reader，只从固定目录读取最新 snapshot 或按条件查询 snapshot。
- 将当前 MVP 的数据来源从“直连 iOS App”切换为“读取 Lookin mac 端已导出的 snapshot 文件”。
- 移除 MCP 对 iOS 端 app discovery、USB 连接和激活 app session 的依赖。
- 保持能力为只读，不包含修改 UI、调用方法或控制 Lookin GUI。

## Capabilities

### New Capabilities
- `lookin-local-snapshot-store`：定义 mac 端导出的 snapshot 文件结构、存放位置和刷新规则。
- `lookin-local-snapshot-reader`：定义 MCP 如何读取、列出和查询本地 snapshot，并返回适合 LLM 消费的结果。

### Modified Capabilities

## Impact

- 影响 [Package.swift](/Users/guzhipeng/Desktop/LookinMCP/LookinMCP/Package.swift)、[Sources/LookinMCPServer/main.swift](/Users/guzhipeng/Desktop/LookinMCP/LookinMCP/Sources/LookinMCPServer/main.swift) 和 [Sources/LookinBridgeCore/LKMBridge.m](/Users/guzhipeng/Desktop/LookinMCP/LookinMCP/Sources/LookinBridgeCore/LKMBridge.m) 的能力边界。
- 需要新增一个本地 snapshot schema 与对应读写代码，推荐固定目录，例如 `~/Library/Application Support/LookinMCP/`。
- 需要在 Lookin mac 端增加 snapshot 导出入口，或新增一个可复用的导出模块，直接读取当前内存中的 `inspectingApp`、`rawHierarchyInfo` 和 detail 数据。
- 需要把 MCP tool contract 收敛为本地文件读取与查询，而不是连接管理。

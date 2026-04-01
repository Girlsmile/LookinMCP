## Context

当前 Lookin mac 桌面版已经掌握完整的运行时上下文，包括：

- 当前选中的 inspecting app
- 已拉取的 `LookinHierarchyInfo`
- 已更新的 `LookinDisplayItemDetail`
- 已在桌面内完成的截图、层级和属性渲染

问题不在“能不能拿到数据”，而在“谁拥有唯一连接”。iOS 侧 `LookinServer` 只维护一个活跃 `peerChannel`，当桌面版已连接后，第二个 client 会被拒绝。因此 MCP 不应再直接连接 iOS 端，而应复用 Lookin mac 端当前已持有的数据，先导出为本地 snapshot，再由 MCP 进程只读这些产物。

```mermaid
flowchart LR
    A[Lookin mac 内存数据] --> B[Snapshot 导出器]
    B --> C[本地 snapshot 目录]
    C --> D[MCP Reader]
    D --> E[Codex CLI / LLM]
```

## Goals / Non-Goals

**Goals:**
- 定义一个稳定的本地 snapshot 文件模型，供 Lookin mac 端导出当前 UI 现场。
- 让 `lookin-mcp` 只读取本地 snapshot，不再承担 USB、端口扫描或 app session 管理。
- 保留对 LLM 有价值的核心字段：app 元数据、可见 VC、hierarchy excerpt、layout evidence、截图引用。
- 支持“读取最新 snapshot”和“按条件查询 snapshot”两类最小 MCP 场景。

**Non-Goals:**
- 不支持多个 MCP 进程同时写 snapshot。
- 不要求第一版实现复杂的跨进程 RPC 或内存共享。
- 不在本 change 中支持 UI 修改、方法调用或 3D 预览控制。
- 不在第一版中引入数据库或索引服务。

## Decisions

### 1. 用文件目录做 Lookin 与 MCP 的边界，而不是进程内嵌或直接读取运行时内存

采用固定目录下的 snapshot 文件作为边界，例如 `~/Library/Application Support/LookinMCP/current/`。

原因：
- 文件边界最容易调试和回放。
- 可以避免给现有 Lookin 桌面进程引入额外常驻 IPC server。
- MCP 进程崩溃不会影响 Lookin 桌面主流程。

备选方案：
- 直接把 MCP server 嵌进 Lookin.app。拒绝原因是耦合太重，发布、调试和权限边界都更复杂。
- 直接跨进程读取 Lookin 内存对象。拒绝原因是不可维护且不稳定。

### 2. Snapshot 导出格式采用“一个主 JSON + 零个或一个图片文件”

主 JSON 保存结构化信息，截图单独落地为 PNG 文件并在 JSON 中记录相对路径。

原因：
- 文本与二进制分离，便于 MCP 返回时按需决定是否内联截图。
- 同一份 JSON 可被工具、脚本和测试直接读取。

备选方案：
- 截图直接 base64 内联到 JSON。拒绝原因是文件体积膨胀，更新和比较都不友好。

### 3. Snapshot 目录同时维护 `current` 指针和历史快照

建议目录结构：

```text
LookinMCP/
  current/
    snapshot.json
    screenshot.png
  history/
    20260401T110530Z/
      snapshot.json
      screenshot.png
```

原因：
- `current` 便于 MCP 读取最新现场。
- `history` 便于后续做回溯、对比和调试。

### 4. MCP 工具从“连接型工具”切换为“本地读取型工具”

第一版工具建议收敛为：

- `lookin.get_latest_snapshot`
- `lookin.query_snapshot`
- `lookin.list_snapshots`

原因：
- 这组工具与实际能力一致，不再伪装 app discovery 或 select session。
- 查询行为只面向 snapshot 数据，不受 iOS 端连接状态影响。

### 5. 查询逻辑沿用现有 MVP 的过滤语义，但作用于 snapshot 文件

保留 `vc_name`、`ivar_name`、`class_name`、`text`、`max_matches`、`include_tree` 等参数，但它们都作用在本地 JSON 上。

原因：
- 能复用已经整理好的 LLM 消费 schema。
- 用户侧调用体验不用因为数据来源改变而重学一套接口。

## Risks / Trade-offs

- [Lookin 桌面未导出 snapshot] -> MCP 无法工作  
  缓解：对“没有 current snapshot”提供显式错误，并在文档中说明导出前置条件。

- [导出 JSON 与桌面内存状态不同步] -> LLM 看到旧数据  
  缓解：在 snapshot 中写入 `captured_at`、`app_identifier` 和导出版本，并让导出动作由用户显式触发或由 Lookin 明确刷新后触发。

- [截图路径失效] -> MCP 返回不完整  
  缓解：将截图文件放在 snapshot 同目录，路径使用相对路径。

- [历史目录无限增长] -> 本地磁盘堆积  
  缓解：增加保留条数或按时间淘汰，第一版先设定简单上限。

- [Lookin 代码侵入过大] -> 上游升级成本升高  
  缓解：把导出逻辑集中在独立模块，尽量只读 `LKAppsManager` 与 `LKStaticHierarchyDataSource` 暴露的现有状态。

## Migration Plan

1. 在 Lookin mac 端新增一个本地 snapshot 导出模块，能从当前 inspecting app 和 hierarchy data source 生成标准 JSON。
2. 将现有 `lookin-mcp` 的 bridge 边界改为“读取 snapshot 目录”，移除对直连 iOS 发现流程的依赖。
3. 保留现有 LLM 友好 schema 的大部分字段，避免调用层重写。
4. 完成“无 snapshot”“有 current snapshot”“按条件查询命中/未命中”的验证。
5. 后续如需更低延迟，再考虑把文件边界升级为本地 IPC，但不影响当前 contract。

## Open Questions

- Lookin mac 端的导出入口应该是显式菜单动作、调试按钮，还是在每次 reload 后自动刷新？
- `current` 是否只保留最新一份，还是允许按 app 维度拆分多个 current 子目录？
- 第一版 screenshot 在 MCP 返回中应默认内联，还是只返回路径并由调用方决定是否读取？

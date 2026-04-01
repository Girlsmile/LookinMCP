## 1. MCP Core 与 Host 架构整理

- [x] 1.1 将现有 `Sources/LookinMCPServer/` 中的工具分发与 snapshot 查询逻辑下沉为可复用 core，避免仅依赖 `stdio` 入口。
- [x] 1.2 设计并实现 Lookin Desktop 可调用的本地 MCP host 管理器，支持启动、停止、健康检查和最近请求/错误记录。
- [x] 1.3 定义固定 localhost 地址、端口占用失败和 Lookin 退出时的释放行为，并补充对应注释。

## 2. Lookin Desktop Toolbar 状态入口

- [x] 2.1 在 Lookin toolbar 中新增 MCP 按钮和对应 identifier，接入静态主窗口。
- [x] 2.2 实现 MCP 状态模型（`off`、`starting`、`ready`、`connected`、`stale`、`error`）以及与 snapshot freshness 的联动。
- [x] 2.3 实现 MCP popover，展示状态、服务地址、最近 snapshot 时间、最近请求、最近错误，并提供启动/停止/复制地址操作。

## 3. Transport 与行为验证

- [x] 3.1 为本地 MCP host 增加协议级测试，覆盖服务启动、工具调用、无 snapshot、端口冲突和停止后的行为。
- [x] 3.2 为 toolbar 状态与 popover 行为补充单元测试或可自动化验证的状态测试，保证非人工测试部分覆盖率超过 80%。
- [x] 3.3 验证 `swift build`、`swift test` 与 Lookin mac 工程编译通过，确认桌面 host 与现有 `stdio` 调试入口都可用。

## 4. 文档与接入说明

- [x] 4.1 更新 README 与相关说明文档，写清楚 Lookin Desktop 内置 MCP host 的地址、启停方式和当前限制。
- [x] 4.2 补充 CodexCLI / 其他 MCP 客户端的连接示例，明确 Lookin 重启后应按固定 localhost 地址重连。

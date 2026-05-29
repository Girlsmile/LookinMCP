## 1. OpenSpec 与契约

- [x] 1.1 定义 `lookin.refresh` 的 tool schema：`wait_until`、`timeout_ms`、`mode`。
- [x] 1.2 定义 ids-only 与 brief 响应字段，明确不内联 screen/tree/screenshot/resource 模板。

## 2. Desktop 刷新控制入口

- [x] 2.1 在 Lookin Desktop 主进程新增 localhost-only 刷新控制入口。
- [x] 2.2 将控制入口接入现有 static window reload 流程。
- [x] 2.3 在 hierarchy 完成和 detail 完成时返回或记录刷新完成阶段。
- [x] 2.4 处理无 app、正在刷新、刷新失败和超时等错误语义。

## 3. MCP helper tool

- [x] 3.1 在 MCP tool list 中注册 `lookin.refresh`。
- [x] 3.2 实现 helper 到 Desktop 控制入口的 refresh client。
- [x] 3.3 返回低 token payload，并在超时/失败时带上已知阶段和 snapshot id。

## 4. 验证与文档

- [x] 4.1 增加 MCP handler/tool schema 与 refresh payload 单元测试。
- [x] 4.2 执行 `openspec status --change "add-lookin-mcp-refresh-tool" --json`。
- [x] 4.3 执行 `swift build --package-path LookinServer` 或受影响 SwiftPM 构建。
- [x] 4.4 更新 README / MCP 接入文档中的推荐调用顺序。

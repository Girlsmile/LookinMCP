## 1. Snapshot 导出模型

- [x] 1.1 定义本地 snapshot 的目录结构、JSON schema 版本和历史保留规则
- [x] 1.2 实现 snapshot 写入器，支持原子写入 `current/snapshot.json` 与可选截图文件
- [x] 1.3 实现从 Lookin 当前内存状态提取 app 元数据、页面信息、层级摘录和布局证据的序列化逻辑

## 2. Lookin mac 导出能力

- [x] 2.1 在 Lookin mac 端增加“导出当前 snapshot”的触发入口
- [x] 2.2 基于 `LKAppsManager` 与 `LKStaticHierarchyDataSource` 生成最新 snapshot 并写入固定目录
- [x] 2.3 处理未连接 app、缺少 hierarchy、截图缺失等异常场景，并给出明确错误

## 3. MCP 本地读取能力

- [x] 3.1 移除直连 iOS 的 MCP 工具，改为读取本地 snapshot 目录
- [x] 3.2 实现 `lookin.list_snapshots`、`lookin.get_latest_snapshot`、`lookin.query_snapshot`
- [x] 3.3 让查询支持 `vc_name`、`ivar_name`、`class_name`、`text`、`max_matches`、`include_tree`

## 4. 测试与文档

- [x] 4.1 为 snapshot 读取与查询逻辑补充单元测试，覆盖命中、未命中、无快照等场景
- [x] 4.2 验证 Swift Package 与 Lookin mac 工程均可编译通过
- [x] 4.3 更新仓库文档，说明 snapshot 目录、导出方式、MCP 调用方式与当前限制

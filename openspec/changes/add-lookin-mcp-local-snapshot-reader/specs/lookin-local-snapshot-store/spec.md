## ADDED Requirements

### Requirement: Lookin mac 端可以导出当前 UI 现场为本地 snapshot
系统 SHALL 允许 Lookin mac 端把当前 inspecting app 的 UI 现场导出为本地 snapshot，而不是要求 MCP 重新连接 iOS 端。

#### Scenario: 导出当前界面快照
- **WHEN** 用户在 Lookin mac 端触发一次 snapshot 导出
- **THEN** 系统生成一份包含 app 元数据、可见 view controller、hierarchy excerpt 和 layout evidence 的本地 snapshot
- **AND** 当截图可用时，系统同时生成 screenshot 文件并在 snapshot 中记录其相对路径

### Requirement: Snapshot 使用稳定的目录与文件结构
系统 SHALL 使用固定目录和稳定文件名保存最新 snapshot，并允许保留历史快照。

#### Scenario: 写入 current snapshot
- **WHEN** 系统完成一次新的 snapshot 导出
- **THEN** 系统将最新 snapshot 写入约定的 `current` 目录
- **AND** `current` 目录中至少包含 `snapshot.json`

#### Scenario: 保留历史 snapshot
- **WHEN** 系统启用了历史保留
- **THEN** 每次导出后的 snapshot 都会写入一个独立的历史目录
- **AND** 历史目录名可以唯一标识该次导出

### Requirement: Snapshot JSON 必须携带时效与来源信息
系统 SHALL 在 snapshot JSON 中提供足以判断数据新鲜度与来源的字段。

#### Scenario: 记录导出元信息
- **WHEN** 系统写入 `snapshot.json`
- **THEN** JSON 中包含 `captured_at`
- **AND** JSON 中包含 app 标识信息，例如 app 名称、bundle identifier 或等价字段
- **AND** JSON 中包含导出 schema 版本

### Requirement: Snapshot 文件必须可脱离 Lookin 进程被独立读取
系统 SHALL 使 snapshot 成为完整的、磁盘上的静态产物，以便 MCP 或测试脚本独立读取。

#### Scenario: Lookin 关闭后读取 snapshot
- **WHEN** Lookin 已经完成导出且随后被关闭
- **THEN** MCP 仍然可以读取最后一次成功写入的 `snapshot.json`
- **AND** 读取行为不依赖 Lookin 进程仍然存活

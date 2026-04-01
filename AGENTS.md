# Repository Guidelines

## 项目结构与模块划分

这个仓库是围绕上游 Lookin 项目构建 MCP bridge 的工作区。

- `Lookin/`：macOS 客户端源码、Xcode 工程、AppKit 界面和连接层。
- `LookinServer/`：iOS 侧运行时库、共享模型、示例工程、Swift Package 与 podspec。
- `openspec/`：本仓库变更的 proposal、design、spec 和 tasks。
- `.codex/`：本地 Codex skill 与工作流配置，不属于产品代码。

新增 bridge 代码和仓库自有文档应放在根工作区或单独的顶层模块中。除非变更明确针对上游项目，否则不要随意改动 vendored 的 Lookin 源码。

## 构建、测试与开发命令

- `openspec list --json`：查看当前变更列表。
- `openspec status --change "<name>" --json`：检查某个 change 是否已满足 apply 前置条件。
- `swift build --package-path LookinServer`：构建 `LookinServer` 的 Swift Package 入口。
- `xcodebuild -project Lookin/Lookin.xcodeproj -list`：查看 `Lookin` 的可用 scheme。
- `xcodebuild -project Lookin/Lookin.xcodeproj -scheme Lookin -configuration Debug build`：构建 macOS 客户端。

除非命令显式指定子路径，否则默认在仓库根目录执行。

## 编码风格与命名约定

遵循被修改模块的现有风格。

- Objective-C：4 空格缩进，文件名使用 `ClassName.m/.h`，常见前缀有 `LK`、`LKS`。
- Swift：遵循标准 Swift API 命名，类型名使用 PascalCase。
- OpenSpec capability 名称使用 kebab-case，例如 `ui-snapshot-capture`。
- 新接口优先输出轻量 JSON 视图模型，不要把 Lookin 的 GUI 内部对象直接暴露出去。

## 测试规范

当前仓库根目录还没有统一自动化测试套件。每次改动至少要做：

- 用 `openspec status --change "<name>" --json` 校验工件状态。
- 对受影响模块执行定向构建。
- 如果改动连接或 snapshot 流程，要连接一个真实运行中的 debug app 做验证。

新增测试名称应直接描述行为，例如 `UISnapshotCaptureTests`。

## 提交与合并请求规范

当前 Git 历史很少，使用简短的祈使句提交信息即可，例如 `Add MCP snapshot adapter`。

Pull Request 至少应包含：

- 问题背景与目标
- 对应的 OpenSpec change 名称
- 影响模块（`Lookin`、`LookinServer`、bridge、文档）
- UI/snapshot 相关截图或示例 MCP payload
- 你实际执行过的验证步骤

## Agent 说明

搜索优先用 `rg`，修改保持聚焦，不要回滚无关上游变更。若任务仍处于探索阶段，先更新 `openspec/changes/...`，只有在 change 达到 apply-ready 后再进入实现。

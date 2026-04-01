## Why

当前 Lookin Desktop 已经可以托管本地 MCP host，但分发形态仍然偏开发态：用户需要先拉源码、执行 `swift build`，再通过环境变量或仓库路径让 Lookin 找到 `lookin-mcp` 可执行文件。这意味着当前方案更像“本地调试能力”，还不是“别人下载后即可直接使用的产品能力”。

```mermaid
flowchart LR
    A[用户拉源码] --> B[swift build]
    B --> C[配置 LOOKIN_MCP_EXECUTABLE]
    C --> D[Lookin Desktop 启动 MCP]
```

如果目标是让外部开发者直接接入 MCP，就必须把 `lookin-mcp` 作为 Lookin.app 的一部分发布，并提供清晰的 release / dmg 分发流程。用户应当可以只安装 Lookin.app，再在自己的 MCP client 中填写固定 localhost 地址，而不再依赖源码目录和构建命令。

```mermaid
flowchart LR
    A[下载 LookinMCP.dmg] --> B[安装 Lookin.app]
    B --> C[Lookin 内嵌 MCP helper]
    C --> D[本地启动 MCP Host]
    D --> E[CodexCLI / Cursor 连接 localhost]
```

## What Changes

- 将 `lookin-mcp` 作为发布态 helper 内嵌进 Lookin.app，而不是要求用户从源码目录解析可执行文件。
- 调整 Lookin Desktop 的 MCP host 启动逻辑，优先从 app bundle 内查找 helper；开发态仍保留环境变量和仓库路径 fallback。
- 增加 release 打包流程，用于构建自包含的 Lookin.app，并进一步产出可分发的 dmg。
- 明确 helper 与主 app 的签名、发布目录结构以及启动失败时的可诊断错误。
- 补充面向外部用户的安装与接入文档，使“下载 app -> 打开 Lookin -> 配置 MCP client”成为主路径。

## Capabilities

### New Capabilities
- `lookin-desktop-release-distribution`：定义 Lookin.app 如何内嵌 `lookin-mcp` helper、如何产出可安装的 app / dmg，以及用户安装后的接入预期。

### Modified Capabilities
- `lookin-desktop-mcp-host`：调整桌面 MCP host 的可执行文件解析规则，使其优先使用 app bundle 内置 helper，并在缺失或签名异常时返回明确错误。

## Impact

- 影响 Lookin Desktop 的构建与发布链路，包括 Xcode target、build phase、helper 拷贝位置和打包脚本。
- 影响 `LKMCPHostManager` 的启动与可执行文件解析逻辑，需要明确发布态与开发态的优先级。
- 影响 release 交付标准，需要定义签名、notarize、dmg 结构和安装后的运行前提。
- 影响 README 与安装文档，需要将“源码构建”降级为开发者路径，把“直接安装 app / dmg”提升为默认接入路径。

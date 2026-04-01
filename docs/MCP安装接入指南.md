# LookinMCP 安装接入指南

本文档面向第一次接入 LookinMCP 的开发者。默认推荐方式是：安装已经打包好的 Lookin.app 或 dmg，由 Lookin Desktop 在本机托管 MCP HTTP 服务，客户端再连接固定地址。

## 前置条件

- macOS 13 或更高版本
- 一个已发布的 Lookin.app 或 dmg

如果你是仓库贡献者或需要自己构建发布包，再额外准备：

- Xcode 15+
- Swift 6 toolchain

## 1. 安装 Lookin

推荐路径：

1. 下载 `Lookin.app` 或 `LookinMCP.dmg`
2. 如果拿到的是 dmg，双击打开后将 `Lookin.app` 拖入 `Applications`
3. 启动 Lookin

如果你拿到的是源码仓库，而不是发布包，请改走“开发者构建路径”。

## 2. 运行 Lookin

启动后，Lookin 顶部工具栏会出现 `MCP` 按钮。正常情况下，Lookin 会自动拉起本地 MCP Host。

如果你运行的是发布版 app，这一步不需要再设置 `LOOKIN_MCP_EXECUTABLE`。

## 3. 确认 MCP Host 已启动

固定地址：

- MCP: `http://127.0.0.1:3846/mcp`
- 状态页: `http://127.0.0.1:3846/status`

可以直接检查状态：

```bash
curl http://127.0.0.1:3846/status
```

如果返回 `ready`、`connected`、`stale` 等状态字段，说明 Host 已经在线。

## 4. 在客户端中接入

### CodexCLI

在项目级 `.codex/config.toml` 或全局配置中加入：

```toml
[mcp_servers.lookin-desktop]
url = "http://127.0.0.1:3846/mcp"
enabled = true
tool_timeout_sec = 10000
```

重启客户端后，应能看到 `lookin.find_nodes`、`lookin.get_node_details`、`lookin.get_node_relations` 等工具。

## 5. 首次验证

建议按这个顺序验证：

1. 在 Lookin 中连接到目标 iOS App，并确认已经抓到 hierarchy。
2. 访问 `/status`，确认服务在线。
3. 在 MCP 客户端里调用 `lookin.list_snapshots`。
4. 再调用 `lookin.find_nodes`，确认能定位到界面节点。

## 开发者构建路径

如果你还没有发布版 app，而是直接从源码仓库接入，请先构建：

```bash
git clone git@github.com:Girlsmile/LookinMCP.git
cd LookinMCP
swift build
```

构建完成后，可执行文件位于：

```text
.build/debug/lookin-mcp
```

然后用 Xcode 打开并运行修改后的 Lookin 工程：

```bash
open Lookin/Lookin.xcodeproj
```

如果 Lookin 找不到可执行文件，先设置：

```bash
export LOOKIN_MCP_EXECUTABLE="$(pwd)/.build/debug/lookin-mcp"
```

然后再从同一个终端启动 Lookin，或让 Xcode Scheme 继承这个环境变量。

## 常见问题

- `未找到 lookin-mcp 可执行文件`
  如果你运行的是源码版，先执行 `swift build`，再检查 `LOOKIN_MCP_EXECUTABLE`。如果你运行的是发布版，优先检查 `Lookin.app/Contents/PlugIns/lookin-mcp` 是否存在且可执行。
- `127.0.0.1:3846` 连接失败
  先确认 Lookin 顶部 `MCP` 状态不是红色，再看端口是否被占用。
- 能连上 MCP，但没有节点数据
  说明 Lookin 还没有成功抓到当前 App 的 snapshot，需要先在 Lookin 里完成连接和刷新。
- 发布包能打开，但 MCP 启动失败
  优先检查 app bundle 是否完整、helper 是否被误删，以及签名是否在分发过程中被破坏。

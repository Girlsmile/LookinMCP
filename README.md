# LookinMCP MVP

[中文](README.md) | [English](README.en.md)

> **项目来源说明**
>
> 本项目基于上游开源项目 [hughkli/Lookin](https://github.com/hughkli/Lookin) 进行研究、适配与扩展，当前仓库主要聚焦于 Lookin Desktop 与 MCP 能力的集成、打包和接入流程。
>
> **免责声明**
>
> 本仓库仅用于技术研究、学习交流与兼容性验证，相关代码、商标、界面设计及其知识产权归原项目作者及其权利人所有。如本仓库中的任何内容涉及侵权、授权范围不清或其他权利问题，请权利人通过 GitHub Issue 或仓库维护者联系渠道告知，我们将在核实后及时处理、修改或移除相关内容。

这是一个基于 Lookin mac 端本地 snapshot 的 MCP 实现。当前主路径不再让外部客户端自己拉起一次性的 `stdio` 进程，而是由 Lookin Desktop 托管本地 MCP host，对外暴露固定地址，客户端只需要重连同一个 localhost URL。

## 当前结构

- `Lookin/`：macOS Lookin 客户端源码，负责连接 iOS App 并导出 snapshot。
- `Sources/LookinMCPServer/`：Swift MCP core、`stdio` 调试入口和本地 HTTP host。
- `LookinServer/`：上游 iOS runtime 与共享模型，当前不再由 MCP 直接连接。
- `openspec/changes/add-lookin-desktop-mcp-host/`：桌面托管 host、toolbar 状态入口与测试的设计、规格和任务。

## 本地目录

默认目录：

```text
~/Library/Application Support/LookinMCP/
  current/
    snapshot.json
    screenshot.png
  history/
    <timestamp>/
      snapshot.json
      screenshot.png
```

Lookin mac 端在切换 app、reload hierarchy、detail 同步完成后，会自动刷新 `current`，并保留最近的历史快照。

## 安装与接入

普通用户优先走安装路径，不需要先执行 `swift build`：

- [Release 页面（DMG 下载入口）](https://github.com/Girlsmile/LookinMCP/releases)
- [仓库地址](https://github.com/Girlsmile/LookinMCP)

1. 获取发布好的 `Lookin.app` 或 `LookinMCP.dmg`
2. 安装并启动 Lookin
3. 确认顶部 `MCP` 状态为可用
4. 在 MCP client 中连接 `http://127.0.0.1:3846/mcp`

详细步骤见 `docs/MCP安装接入指南.md`。

## 开发者构建

如果你是仓库开发者，只需要两类命令：

```bash
swift build
swift test
```

如需手动调试 MCP：

```bash
.build/debug/lookin-mcp --transport http --port 3846
```

## Lookin Desktop 内置 Host

- Lookin 静态主窗口的 toolbar 已增加 `MCP` 按钮。
- 打开主窗口后会自动尝试启动本地 host；也可以在 popover 中显式启动或停止。
- 固定地址为 `http://127.0.0.1:3846/mcp`。
- 状态接口为 `http://127.0.0.1:3846/status`。
- Lookin 退出时会停止子进程并释放端口；Lookin 重启后仍然使用同一地址，客户端应按该地址重连。

### Toolbar 状态说明

- `未启动`：Lookin 当前未托管 host。
- `启动中`：Lookin 已拉起子进程，正在等待 `/status` 就绪。
- `就绪`：服务在线，且 snapshot 新鲜。
- `活跃`：最近 30 秒内有成功的 MCP 请求。
- `过期`：服务在线，但 snapshot 缺失或已超过新鲜度阈值。
- `错误`：进程退出、端口占用或状态检查失败。

## 已支持的 Tools

- `lookin.list_snapshots`：列出 current 与 history 中可读取的快照。
- `lookin.get_latest_snapshot`：返回最新 snapshot 的完整结构化内容。
- `lookin.find_nodes`：按 `vc_name`、`ivar_name`、`class_name`、`text` 查找候选节点。
- `lookin.get_node_details`：返回节点本体、父节点和直接子节点。
- `lookin.get_node_relations`：返回父子兄弟关系、间距和对齐信息。
- `lookin.get_subtree`：展开局部子树。
- `lookin.crop_screenshot`：按节点裁剪局部截图。
- `lookin.query_snapshot`：按 `vc_name`、`ivar_name`、`class_name`、`text` 对 snapshot 做确定性查询，并返回布局证据与层级摘录。

## 查询返回的关键证据

- `frame` / `bounds` / `frame_to_root`：节点自身尺寸、局部坐标和相对根视图坐标。
- `layout_evidence`：包含 `intrinsic_size`、hugging / compression resistance，以及可直接读给 LLM 的约束摘要。
- `visual_evidence`：包含 `hidden`、`opacity`、`user_interaction_enabled`、`masks_to_bounds`、`background_color`、`border_color`、`border_width`、`corner_radius`、`shadow`、`tint_color`、`tint_adjustment_mode`、`tag`。
- `tree_excerpt`：命中节点周围的祖先和子树摘录，便于判断层级关系、包裹关系和间距来源。

颜色会按结构化对象返回，例如：

```json
{
  "hex_string": "#ff0000",
  "rgba_string": "(255, 0, 0, 1.00)",
  "components": [1, 0, 0, 1]
}
```

## 当前限制

- 只读，不支持改属性、调方法或控制 Lookin GUI。
- 当前仓库已经提供 app bundle 内嵌 helper 的发布脚本，但正式公开分发仍取决于签名、notarize 和发布产物管理。
- `get_latest_snapshot` 直接返回完整 JSON，大页面下响应体会较大。
- 真实链路依赖你运行的是这份修改后的 Lookin.app，而不是旧版本二进制。

## 客户端连接示例

CodexCLI 可直接配置固定 URL：

```toml
[mcp_servers.lookin-desktop]
url = "http://127.0.0.1:3846/mcp"
```

其他支持 HTTP MCP 的客户端也应连接同一个地址。不要依赖随机端口；Lookin 重启后应继续按 `http://127.0.0.1:3846/mcp` 重连。

## LLM Prompt 文档

- 面向 CodexCLI / 其他 Agent 的直接使用说明见 `docs/LLM使用Prompt.md`
- 该文档给出了推荐 tool 调用顺序、判断准则和可直接复制的 Prompt 模板

## 发布脚本

- `scripts/release/build-lookin-mcp-release.sh`：构建 release 版 `lookin-mcp`
- `scripts/release/assemble-lookin-app.sh`：将 helper 注入 `Lookin.app/Contents/PlugIns/`
- `scripts/release/verify-lookin-release.sh`：校验 app 内嵌 helper 和签名状态
- `scripts/release/package-lookin-release.sh`：串联 app 构建、helper 注入、签名校验和 dmg 生成

面向发布者的说明见 `docs/发布打包指南.md`。

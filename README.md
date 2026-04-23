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

- 本地 DMG 产物路径：`build/release/output/LookinMCP.dmg`
- [Release 页面（如已上传，可在此下载 DMG）](https://github.com/Girlsmile/LookinMCP/releases)
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

## 当前 MCP Surface

### Tools

- `lookin.screen`：返回当前或指定 snapshot 的紧凑页面摘要。
- `lookin.find`：按 `vc_name`、`ivar_name`、`class_name`、`text` 定位候选节点；传 `mode=ids` 时只返回 `sid/total/ids`。
- `lookin.inspect`：读取单个节点的布局、样式和关系证据；传 `mode=brief` 时只返回短字段节点摘要，传 `mode=evidence` 时只返回显式请求的证据 section。
- `lookin.capture`：按节点裁剪局部截图。
- `lookin.raw`：返回原始快照导出的兜底入口，默认只给摘要和 raw resource 链接。

### Resources

- `lookin://snapshots/current/summary`
- `lookin://snapshots/current/raw`
- `lookin://snapshots/current/screenshot`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/layout`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/style`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/relations`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/children?limit=...&cursor=...`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/siblings?limit=...&cursor=...`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/subtree?...`
- `lookin://snapshots/<snapshot_id>/nodes/<node_id>/capture?...`

大对象默认不再通过 tools 直接内联，而是让 LLM 按需读取 resources。

## 推荐的低 Token 查询路径

如果你的目标是让 LLM 少吃上下文，推荐这样调用：

1. `lookin.find` + `mode=ids`
2. `lookin.inspect` + `mode=brief`
3. 按需读取 `layout`、`style`、`relations`、`children`、`siblings`、`subtree` 或 `capture`

例如：

```json
{
  "name": "lookin.find",
  "arguments": {
    "class_name": "Collage_dev.ERCanvasImageView",
    "mode": "ids"
  }
}
```

然后：

```json
{
  "name": "lookin.inspect",
  "arguments": {
    "node_id": "oid:47",
    "mode": "brief"
  }
}
```

### 低 token 短字段

- `sid`：snapshot id
- `id`：node id
- `cls`：class name
- `raw`：raw class name
- `vc`：host view controller
- `f`：`[x, y, width, height]`
- `ch`：child count
- `p`：parent id
- `n`：nodes
- `next`：下一页 cursor

### Prompts

- `analyze-node-layout`
- `analyze-node-visual-style`
- `diagnose-spacing-and-alignment`

这些 prompts 用来约束 LLM 的取证顺序，不承载底层大数据。

## 旧接口迁移

- `lookin.list_snapshots` -> `lookin.screen` 或 `resources/list`
- `lookin.get_latest_snapshot` -> `lookin.raw`
- `lookin.find_nodes` / `lookin.query_snapshot` -> `lookin.find`
- `lookin.get_node_details` / `lookin.get_node_relations` -> `lookin.inspect`
- `lookin.get_subtree` -> `resources/read` 读取 subtree URI
- `lookin.crop_screenshot` -> `lookin.capture`

## 查询返回的关键证据

- `frame` / `bounds` / `frame_to_root`：节点自身尺寸、局部坐标和相对根视图坐标。
- `layout_evidence`：包含 `intrinsic_size`、hugging / compression resistance，以及可直接读给 LLM 的约束摘要。
- `visual_evidence`：包含 `hidden`、`opacity`、`user_interaction_enabled`、`masks_to_bounds`、`background_color`、`border_color`、`border_width`、`corner_radius`、`shadow`、`tint_color`、`tint_adjustment_mode`、`tag`。
- `relations`：父子兄弟关系、parent inset、相对间距和对齐偏移。
- `resource_links`：现有可读模式下用于进一步读取 raw snapshot、subtree 或裁图的资源入口。低 token mode 默认不重复返回它。

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
- tools 默认仍支持 `compact` 返回；如果想节约 token，优先使用 `mode=ids` / `mode=brief`，再按需读取 section resources。
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
- 该文档给出了推荐的 tool/resource/prompt 使用顺序、判断准则和可直接复制的 Prompt 模板

## 发布脚本

- `scripts/release/build-lookin-mcp-release.sh`：构建 release 版 `lookin-mcp`
- `scripts/release/assemble-lookin-app.sh`：将 helper 注入 `Lookin.app/Contents/PlugIns/`
- `scripts/release/verify-lookin-release.sh`：校验 app 内嵌 helper 和签名状态
- `scripts/release/package-lookin-release.sh`：串联 app 构建、helper 注入、签名校验和 dmg 生成

面向发布者的说明见 `docs/发布打包指南.md`。

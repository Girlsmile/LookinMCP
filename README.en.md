# LookinMCP MVP

[中文](README.md) | [English](README.en.md)

> **Project Origin**
>
> This repository is based on the upstream open-source project [hughkli/Lookin](https://github.com/hughkli/Lookin). It focuses on research, adaptation, and extension work around integrating Lookin Desktop with MCP, along with packaging and onboarding workflows.
>
> **Disclaimer**
>
> This repository is provided for technical research, learning, and compatibility evaluation only. All related code, trademarks, UI designs, and intellectual property remain the property of the original project author and respective rights holders. If any content in this repository is considered infringing, unauthorized, or otherwise problematic, rights holders may contact the maintainers through GitHub Issues or other repository contact channels, and the relevant content will be reviewed and handled promptly.

This is an MCP implementation built on top of local Lookin Desktop snapshots. The main path no longer relies on an external client spawning a one-off `stdio` process. Instead, Lookin Desktop hosts a local MCP server and exposes a stable localhost endpoint that clients can reconnect to.

## Structure

- `Lookin/`: macOS Lookin client source, responsible for connecting to the iOS app and exporting snapshots.
- `Sources/LookinMCPServer/`: Swift MCP core, `stdio` debug entry, and local HTTP host.
- `LookinServer/`: upstream iOS runtime and shared models; MCP no longer connects to it directly.
- `openspec/changes/add-lookin-desktop-mcp-host/`: design, spec, and task artifacts for the desktop-hosted MCP server and toolbar status UI.

## Local Snapshot Directory

Default location:

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

Lookin Desktop refreshes `current` after app switching, hierarchy reload, and detail sync, while keeping recent snapshot history.

## Install and Connect

Regular users should use the packaged app path instead of running `swift build` first:

- [Releases page (DMG download entry)](https://github.com/Girlsmile/LookinMCP/releases)
- [Repository](https://github.com/Girlsmile/LookinMCP)

1. Download the packaged `Lookin.app` or `LookinMCP.dmg`
2. Install and launch Lookin
3. Confirm the top `MCP` status is available
4. Connect your MCP client to `http://127.0.0.1:3846/mcp`

For detailed onboarding, see `docs/MCP安装接入指南.md`.

## Developer Build

If you are working on the repository itself, the main commands are:

```bash
swift build
swift test
```

To debug MCP manually:

```bash
.build/debug/lookin-mcp --transport http --port 3846
```

## Lookin Desktop Hosted MCP

- The static main window now includes an `MCP` button in the toolbar.
- Opening the main window attempts to start the local host automatically; it can also be started or stopped explicitly from the popover.
- Fixed endpoint: `http://127.0.0.1:3846/mcp`
- Status endpoint: `http://127.0.0.1:3846/status`
- When Lookin exits, it stops the child process and frees the port. After restart, clients should reconnect to the same address.

### Toolbar States

- `Off`: MCP host is not running
- `Starting`: Lookin started the helper and is waiting for `/status`
- `Ready`: service is online and the snapshot is fresh
- `Connected`: there has been a successful MCP request in the recent window
- `Stale`: service is online but the snapshot is missing or outdated
- `Error`: process exit, port conflict, or status check failure

## Current MCP Surface

### Tools

- `lookin.screen`: return a compact page-level snapshot summary
- `lookin.find`: find candidate nodes by `vc_name`, `ivar_name`, `class_name`, or `text`; with `mode=ids`, it returns only `sid/total/ids`
- `lookin.inspect`: inspect one node with layout, style, and relation evidence; with `mode=brief`, it returns only a short node summary, and with `mode=evidence`, it returns only explicitly requested evidence sections
- `lookin.capture`: crop a local screenshot around a node
- `lookin.raw`: fallback raw snapshot export, compact by default with a resource link

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

Heavy objects are no longer inlined by default through tools. The model should read resources on demand.

## Recommended Low-Token Query Path

If the goal is to minimize LLM context cost, use this flow:

1. `lookin.find` + `mode=ids`
2. `lookin.inspect` + `mode=brief`
3. Read `layout`, `style`, `relations`, `children`, `siblings`, `subtree`, or `capture` only when needed

Example:

```json
{
  "name": "lookin.find",
  "arguments": {
    "class_name": "Collage_dev.ERCanvasImageView",
    "mode": "ids"
  }
}
```

Then:

```json
{
  "name": "lookin.inspect",
  "arguments": {
    "node_id": "oid:47",
    "mode": "brief"
  }
}
```

### Short Fields

- `sid`: snapshot id
- `id`: node id
- `cls`: class name
- `raw`: raw class name
- `vc`: host view controller
- `f`: `[x, y, width, height]`
- `ch`: child count
- `p`: parent id
- `n`: nodes
- `next`: pagination cursor

### Prompts

- `analyze-node-layout`
- `analyze-node-visual-style`
- `diagnose-spacing-and-alignment`

Prompts describe the workflow. They do not inline the heavy snapshot payloads.

## Migration from Legacy Tools

- `lookin.list_snapshots` -> `lookin.screen` or `resources/list`
- `lookin.get_latest_snapshot` -> `lookin.raw`
- `lookin.find_nodes` / `lookin.query_snapshot` -> `lookin.find`
- `lookin.get_node_details` / `lookin.get_node_relations` -> `lookin.inspect`
- `lookin.get_subtree` -> `resources/read` with a subtree URI
- `lookin.crop_screenshot` -> `lookin.capture`

## Key Evidence in Responses

- `frame` / `bounds` / `frame_to_root`: size, local coordinates, and root-relative coordinates
- `layout_evidence`: intrinsic size, hugging/compression priorities, and readable constraint summaries
- `visual_evidence`: hidden state, opacity, interaction, masks, colors, borders, corner radius, shadow, tint, and tags
- `relations`: parent/child/sibling metrics, insets, and alignment deltas
- `resource_links`: follow-up entry points for readable/debug responses. Low-token modes do not repeat them by default.

Color values are returned in structured form, for example:

```json
{
  "hex_string": "#ff0000",
  "rgba_string": "(255, 0, 0, 1.00)",
  "components": [1, 0, 0, 1]
}
```

## Current Limitations

- Read-only only; no attribute mutation, method invocation, or Lookin GUI control
- The repository now includes app-bundled helper packaging scripts, but public distribution still depends on signing, notarization, and release management
- tools still support readable `compact` output; if you want lower token cost, prefer `mode=ids` / `mode=brief`, then read section resources explicitly
- The real workflow depends on running this modified Lookin build, not the original upstream binary

## Client Example

CodexCLI can connect with:

```toml
[mcp_servers.lookin-desktop]
url = "http://127.0.0.1:3846/mcp"
```

Any MCP client with HTTP support should use the same endpoint. Do not depend on random ports. After Lookin restarts, reconnect to `http://127.0.0.1:3846/mcp`.

## LLM Prompt Guide

- See `docs/LLM使用Prompt.md` for direct LLM usage guidance
- It includes the recommended tool/resource/prompt flow, reasoning constraints, and a copyable prompt template

## Release Scripts

- `scripts/release/build-lookin-mcp-release.sh`: build the release `lookin-mcp` helper
- `scripts/release/assemble-lookin-app.sh`: inject the helper into `Lookin.app/Contents/PlugIns/`
- `scripts/release/verify-lookin-release.sh`: verify the embedded helper and signing state
- `scripts/release/package-lookin-release.sh`: run app build, helper injection, signing verification, and DMG generation

For maintainer-facing packaging notes, see `docs/发布打包指南.md`.

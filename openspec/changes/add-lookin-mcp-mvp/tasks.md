## 1. Bridge 基础设施

- [x] 1.1 审计并隔离非 GUI 原生 bridge target 所需的最小 Lookin connection/session/shared-model 代码。
- [x] 1.2 定义 bridge 自己维护的 app session 状态，包括 `app_id` 映射、激活选择和断线失效规则。
- [x] 1.3 定义 `lookin.list_apps`、`lookin.select_app` 和 `lookin.capture_ui_snapshot` 的 MCP tool contract。

## 2. App Session 能力

- [x] 2.1 通过原生 bridge 复用现有 Lookin connection 流程实现 app discovery。
- [x] 2.2 实现激活 app 选择，以及对 unknown、missing 和 disconnected app 的显式错误处理。
- [ ] 2.3 为 discovery 与 selection 流程补充空列表与非空列表场景的验证。

## 3. UI Snapshot 能力

- [x] 3.1 实现 snapshot 抓取，从选中的 app 收集 app metadata、visible view controller 上下文、screenshot、hierarchy 和 detail payload。
- [x] 3.2 实现针对 `vc_name`、`ivar_name`、`class_name` 和 `text` 的确定性过滤。
- [x] 3.3 实现适合 LLM 消费的 hierarchy 裁剪与命中 view 提取。
- [x] 3.4 实现布局证据的 JSON 转换，包括 frame、bounds、visibility、intrinsic size、hugging、compression resistance 和 constraint summary。
- [ ] 3.5 为命中与未命中两类 snapshot 请求补充验证，并覆盖 payload 大小边界。

## 4. MCP 交付

- [x] 4.1 实现基于 stdio 的 MCP handler，通过原生 bridge 暴露这三个 MVP tools。
- [ ] 4.2 至少针对一个正在运行的 debug app，从 Codex CLI 端到端验证 MVP。
- [x] 4.3 记录 MVP 的使用方式、限制项以及后续延迟项，例如 mutation 支持和 `accessibilityIdentifier` 匹配。

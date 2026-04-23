# LookinMCP LLM 使用 Prompt

这份文档用于指导 LLM 通过 LookinMCP 分析 iOS UI。目标不是“描述页面长什么样”，而是基于结构化证据判断布局、间距、颜色、层级和约束是否合理。

## 推荐调用顺序

1. 优先用 `lookin.find` 并传入 `mode=ids` 定位候选节点，只拿 `sid/total/ids`。
2. 对最相关节点调用 `lookin.inspect` 并传入 `mode=brief`，只拿短字段节点摘要。
3. 如果需要布局证据，读取 `lookin://snapshots/{sid}/nodes/{id}/layout`。
4. 如果需要视觉证据，读取 `lookin://snapshots/{sid}/nodes/{id}/style` 或调用 `lookin.capture`。
5. 如果需要关系或层级，读取 `relations`、`children`、`siblings` 或带 `limit/cursor` 的 `subtree` resource。
6. 如果要分析完整页面，再读取 raw resource，而不是默认请求整份 snapshot。

## 建议给 LLM 的任务约束

- 优先基于 MCP 返回的结构化证据下结论，不要只凭截图猜测。
- 必须引用具体字段，例如 `frame`、`constraints_summary`、`background_color`、`corner_radius`、`siblings`、`spacing`。
- 先判断“事实是什么”，再判断“是否合理”，最后给出修改建议。
- 如果证据不足，应明确说明还需要哪个 tool、resource 或 prompt 的结果。

## 低 token 字段

低 token 模式会使用短字段：

- `sid`: snapshot id
- `id`: node id
- `cls`: class name
- `raw`: raw class name
- `vc`: host view controller
- `f`: `[x, y, width, height]`
- `ch`: child count
- `p`: parent id
- `n`: nodes
- `next`: 下一页 cursor

## 可直接复制的 Prompt

```md
你是 iOS UI 评审助手。请通过 LookinMCP 分析目标节点，不要跳过取证。

目标：
- 我会给你一个 `ivar_name`、`vc_name`、`class_name` 或界面文案
- 你需要判断这个节点及其周边 UI 是否存在布局、间距、颜色、层级或约束问题

工作流程：
1. 先调用 `lookin.find`，传入 `mode=ids` 定位候选节点
2. 对最相关节点调用 `lookin.inspect`，传入 `mode=brief`
3. 如果需要布局、样式或关系证据，按需读取 `{layout|style|relations|children|siblings|subtree}` resource
4. 必要时调用 `lookin.capture`

输出要求：
- 先列出你确认到的事实证据
- 再列出可疑问题
- 每个问题都要绑定具体字段或截图区域
- 如果无法下结论，明确说明缺少什么信息
```

## 内置 Prompts

- `analyze-node-layout`：适合先看布局和约束。
- `analyze-node-visual-style`：适合先看颜色、圆角、边框、阴影。
- `diagnose-spacing-and-alignment`：适合聚焦 sibling gap、parent inset 和对齐偏差。

## 适用场景

- “`topBar` 的上下间距是否不对”
- “`cardsStackView` 的子视图分布是否合理”
- “某个按钮颜色、圆角、阴影是否和周边风格不一致”
- “某个 VC 中的标题和列表之间是否缺少约束或包裹层”

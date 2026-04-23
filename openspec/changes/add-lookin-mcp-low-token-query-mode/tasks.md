## 1. 协议与响应模型

- [x] 1.1 在 tool schema 中为 `lookin.find` 和 `lookin.inspect` 增加 `mode=ids|brief|evidence` 参数，并为参数添加注释说明。
- [x] 1.2 新增低 token 短字段响应模型，覆盖 `sid/id/cls/raw/vc/f/ch/p/n/next` 等字段，并保留现有可读响应模型。
- [x] 1.3 新增 frame 数组化 helper，统一保留适合 UI 分析的坐标精度，并为 helper 添加方法注释。
- [x] 1.4 调整 `mode=ids` 的 `find` 返回，仅包含 snapshot、match count、节点 ID 或最小候选摘要。
- [x] 1.5 调整 `mode=brief` 的 `inspect` 返回，仅包含节点身份、VC、class、raw class、frame 和可选 child count。

## 2. Section 级按需读取

- [x] 2.1 扩展 resource URI parser，支持 `layout`、`style`、`relations`、`children`、`siblings`、`subtree` 与 `capture` section。
- [x] 2.2 实现 layout section，只返回 layout evidence。
- [x] 2.3 实现 style section，只返回 visual evidence。
- [x] 2.4 实现 relations section，只返回 parent、ancestor、sibling 与 parent inset 证据。
- [x] 2.5 实现 children、siblings 和 subtree 的 `limit/cursor` 分页读取，并为 cursor 解析方法添加注释。

## 3. 文档与推荐工作流

- [x] 3.1 更新 `docs/LLM使用Prompt.md`，推荐 `find mode=ids -> inspect mode=brief -> read section` 工作流。
- [x] 3.2 更新 MCP 接入文档，说明短字段含义和 section URI 模板。
- [x] 3.3 在 tool 描述中说明低 token mode 与现有 detail 模式的取舍。

## 4. 测试与验证

- [x] 4.1 新增 `lookin.find mode=ids` 单元测试，验证不会返回 layout/style/resource_links。
- [x] 4.2 新增 `lookin.inspect mode=brief` 单元测试，验证 frame 数组化和短字段稳定。
- [x] 4.3 新增 section resource 单元测试，覆盖 layout、style、relations 和 children 分页。
- [x] 4.4 新增 token 或字节预算测试，验证典型 `find + inspect` 查询相对当前 compact 路径节约不低于 50%。
- [x] 4.5 执行 `swift test` 或等价定向测试，确保相关测试通过。
- [x] 4.6 执行 `swift build`，验证编译通过。

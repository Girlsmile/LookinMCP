## 1. 协议收敛

- [x] 1.1 定义新的 5 个以内 tool contract，以及旧 tool 到新 surface 的迁移映射
- [x] 1.2 扩展 MCP 协议处理，补齐 `initialize` capability、`resources/list`、`resources/read`、`prompts/list` 与 `prompts/get`
- [x] 1.3 为 compact、standard、full 三档返回和 `include` 参数补充协议级单元测试

## 2. 数据与工作流适配

- [x] 2.1 将现有 snapshot reader 逻辑下沉为 `lookin.screen`、`lookin.find`、`lookin.inspect`、`lookin.capture`、`lookin.raw` 五个工具的内部适配层
- [x] 2.2 实现 snapshot、subtree、screenshot、capture 等 resources 的 URI 设计与读取逻辑
- [x] 2.3 实现布局分析、视觉样式分析、间距对齐分析三个 prompts，并补充必要注释

## 3. 兼容性与验证

- [x] 3.1 更新 README、安装接入文档与 LLM Prompt 文档，默认推荐新的 tool/resource/prompt 使用方式
- [x] 3.2 清理旧 tool 名称在错误消息、示例与帮助文本中的暴露，并提供迁移说明
- [x] 3.3 完成编译与测试验证，确保非人工测试覆盖核心协议路径且项目可正常通过构建

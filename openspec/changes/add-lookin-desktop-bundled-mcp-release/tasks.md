## 1. 内嵌 helper 与启动路径整理

- [ ] 1.1 调整 `LKMCPHostManager` 的 helper 解析顺序，确保发布态优先使用 app bundle 内嵌 `lookin-mcp`，开发态仍支持 `LOOKIN_MCP_EXECUTABLE` 和仓库路径 fallback。
- [ ] 1.2 为 helper 解析、启动和错误分支补充注释与日志，至少区分 helper 缺失、不可执行、端口占用和子进程启动失败。
- [ ] 1.3 为解析顺序和关键错误路径补充可自动化验证的测试，保证非人工测试部分覆盖率超过 80%。

## 2. Release 构建与 app 产物组装

- [ ] 2.1 增加 release helper 构建流程，生成可嵌入发布包的 `lookin-mcp` 二进制。
- [ ] 2.2 增加 app 组装步骤，将 `lookin-mcp` 拷贝到约定的 bundle 路径，并修正确保可执行的文件权限。
- [ ] 2.3 增加统一的发布脚本，串联 Lookin.app 导出、helper 注入、签名校验和 dmg 生成。

## 3. 发布校验与安装验证

- [ ] 3.1 为发布脚本增加产物校验，确认最终 Lookin.app 中存在内嵌 helper，且路径与签名状态符合预期。
- [ ] 3.2 在本机完成一次端到端验证：仅使用打包后的 Lookin.app 启动 MCP host，并成功响应 `lookin.find_nodes` 等工具调用。
- [ ] 3.3 在一台不依赖源码目录或 `swift build` 的环境中验证安装路径，确认“安装 app / dmg 后即可使用”成立。
- [ ] 3.4 验证 `swift build`、`swift test` 与 Lookin mac 工程编译通过，确保开发态与发布态链路都未被破坏。

## 4. 文档与发布说明

- [ ] 4.1 更新 README，将“直接安装 app / dmg”改为默认接入路径，把源码构建降级为开发者说明。
- [ ] 4.2 更新安装接入文档，补充发布版安装步骤、客户端配置示例和常见失败排查。
- [ ] 4.3 补充面向发布者的说明，写清楚签名、notarize 钩子和产物目录结构。

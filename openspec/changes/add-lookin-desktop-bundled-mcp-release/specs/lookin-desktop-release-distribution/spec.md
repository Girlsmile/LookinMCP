## ADDED Requirements

### Requirement: Lookin 发布产物必须内嵌 MCP helper
系统 SHALL 在发布态 Lookin.app 中内嵌 `lookin-mcp` helper，使 MCP 功能不依赖源码目录或本地手工构建。

#### Scenario: 生成发布态 Lookin.app
- **WHEN** 系统完成一次 release 构建
- **THEN** 产出的 Lookin.app 中包含 `lookin-mcp` helper
- **AND** 该 helper 位于约定的 app bundle 内部路径
- **AND** 该 helper 在安装后的机器上可直接执行

#### Scenario: 用户仅安装 Lookin.app
- **WHEN** 用户只安装发布态 Lookin.app，而没有拉取仓库源码或执行 `swift build`
- **THEN** Lookin 仍可启动本地 MCP host
- **AND** 用户不需要额外配置 helper 的本地路径

### Requirement: Release 流程必须产出可安装的 app 与 dmg
系统 SHALL 提供一条可复现的 release 打包流程，产出自包含的 Lookin.app，并可进一步生成对外分发用的 dmg。

#### Scenario: 执行 release 打包流程
- **WHEN** 发布者运行约定的 release 打包脚本或等价流程
- **THEN** 系统产出一个包含内嵌 helper 的 Lookin.app
- **AND** 系统可进一步产出与该 app 对应的 dmg 文件

#### Scenario: 分发文档引用默认安装路径
- **WHEN** 外部用户阅读安装文档
- **THEN** 文档将 “下载 app 或 dmg 并安装” 作为默认路径
- **AND** 文档不会把 `swift build` 描述为普通用户的前置步骤

### Requirement: 发布产物必须具备可验证的签名链路
系统 SHALL 为主 app 与内嵌 helper 定义统一的签名与发布校验要求，避免安装后出现 helper 无法执行的隐性错误。

#### Scenario: helper 被注入 app bundle 后签名
- **WHEN** `lookin-mcp` helper 被拷贝进 Lookin.app
- **THEN** 系统对最终 app bundle 执行统一签名或等价校验流程
- **AND** 主 app 与 helper 的签名状态保持一致

#### Scenario: 发布校验失败
- **WHEN** helper 缺失、不可执行或签名校验失败
- **THEN** 发布流程明确失败
- **AND** 失败原因可被发布者定位，而不是留到用户安装后才暴露

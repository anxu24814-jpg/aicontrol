# AI 控制台（aicontrol）

自备密钥的多模型 AI 对话客户端，面向 HarmonyOS。

应用本身不提供模型服务、密钥与额度，需要你自行接入服务商并自备 API 密钥。

> A bring-your-own-key multi-model AI chat client for HarmonyOS. The app ships with no model service, no API keys and no credits.

## 功能概览

- **多协议多服务商**：支持 OpenAI 兼容、Anthropic、Gemini 三类接入协议，内置十余个常见服务商模板，也可手动添加任意兼容服务。一个服务商可保存多支密钥并自动轮换，某支失效即切换。
- **模型与参数可配置**：模型自由添加，思考强度、温度、输出长度等参数可调，并可为模型标注工具调用、推理、视觉理解、内置联网等能力。
- **助手与提示词体系**：可创建多个助手，各自绑定模型、提示词与工具调用能力；系统提示词、会话提示词、助手提示词三层来源依次生效，支持变量占位。
- **联网搜索与工具调用**：内置免配置的联网搜索与网页抓取，模型可多轮调用工具完成任务。控制台助手能检索帮助中心回答用法问题，也能在你明确要求时代为调整设置、管理提示词、查询用量。
- **附件与文档识别**：拍照、照片与文件最多同时附加 5 个；pdf、docx、xlsx、ofd 发送前自动解析全文，图片类附件在支持视觉理解的模型上可直接识别，另内置端侧 OCR 识别引擎。
- **本地优先**：会话、助手、提示词与偏好默认只保存在设备本地，支持全量备份恢复与同步到自己的 WebDAV 网盘。记忆、用量统计、加密会话（需生物识别验证）与隐私会话（仅留内存）一并提供。

## 构建

**环境要求**

- DevEco Studio：需支持 API 26（HarmonyOS 6.0），SDK 26.0.0
- 工程基线：`modelVersion` / `targetSdkVersion` / `compatibleSdkVersion` 均为 `26.0.0`

**步骤**

1. 用 DevEco Studio 打开工程，等待同步完成（依赖经 ohpm 拉取，含 `@cangjie-tpc/markdown_hybrid` 与 `@lidary/markdown`）。
2. 配置签名：`File` → `Project Structure` → `Signing Configs`，勾选 `Automatically generate signature`（需登录华为开发者账号）。
3. 构建并运行。

**说明**

- 本仓库不包含任何签名材料。`build-profile.json5` 的 `signingConfigs` 为空数组，需按上一步自行生成。
- 工程未随附 hvigor 命令行 wrapper（`hvigorw`），构建请在 DevEco Studio 内进行。

## 自检

`tools/verify/` 下是一组零第三方依赖的纯 node 检查件，不需要安装 DevEco Studio 与 HarmonyOS SDK，克隆下来即可运行，覆盖与平台无关的纯逻辑：协议解析与请求体组装、用量统计、价格折算、跨会话检索、Markdown 复制文本、网络与文档解析、凭据存储不变量。

需要 Node.js **22.18 或更高**——其中数件把 ArkTS 源码复制为 `.ts` 后靠 Node 的类型剥离直接执行，断言的就是应用里跑的同一份实现。

```bash
for f in sse-assert usage-stats-calc-check assert-price-template assert-chat-search-domain assert-msg-copy assert-net-parse assert-security-store; do node tools/verify/$f.mjs || exit 1; done
```

| 检查件 | 覆盖 | 期望输出末行 |
| --- | --- | --- |
| `sse-assert.mjs` | SSE 帧解析，OpenAI 兼容 / Anthropic / Gemini / Responses 四协议请求体组装，提示词注入与变量替换，附件多模态，思考透传，采样参数与缓存控制，工具调用底层，模型匹配，联网搜索解析 | `结果：496 过 / 0 败（契约 0 / 形态 496）` |
| `usage-stats-calc-check.mjs` | 用量统计纯函数：热力图周列与日历网格、连续活跃、月度聚合、数值格式化 | `用量统计纯函数断言 结果：64 过 / 0 败` |
| `assert-price-template.mjs` | 价格配置解析与序列化、费用折算与聚合、价格模板数据层不变量 | `结果：29 过 / 0 败（契约 0 / 形态 29）` |
| `assert-chat-search-domain.mjs` | 跨会话检索与清单纯函数：查询切分、敏感内容闸、片段开窗、分页窗口 | `结果：67 过 / 0 败（契约 0 / 形态 67）` |
| `assert-msg-copy.mjs` | Markdown 复制文本：剥标记、去表格块、复制面板文本拼装 | `结果：31 过 / 0 败（契约 0 / 形态 31）` |
| `assert-net-parse.mjs` | HTTP 请求缓存与建销成对、WebDAV 备份恢复链、文档解析器就绪时序 | `结果：35 过 / 0 败（契约 0 / 形态 35）` |
| `assert-security-store.mjs` | 凭据与安全域不变量：密钥只入系统安全存储、跨卸载持久标记、安全存储与数据库行写序成对、生物识别门禁契约 | `结果：48 过 / 0 败（契约 0 / 形态 48）` |

同一组检查在 CI 上逐件运行，见 `.github/workflows/verify.yml`。这些检查件是作者开发仓中断言的公开副本，只覆盖纯逻辑面；依赖 SDK 的编译、UI 形态与真机行为不在本仓库内验证。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `entry/` | 应用主模块，ArkTS 源码、资源与随包第三方资产 |
| `AppScope/` | 应用级配置与图标 |
| `tools/verify/` | 免 SDK 的纯逻辑检查件（见上节「自检」） |
| `docs/` | 部分设计规范文档 |

## 第三方组件与许可

本项目使用了多个开源组件与随包资产，完整许可证文本见 [`LICENSE-THIRD-PARTY.md`](LICENSE-THIRD-PARTY.md)。随包资源的许可文本随包分发在 `entry/src/main/resources/rawfile/` 各子目录的 `NOTICE.md`。

## 商标声明

本应用是第三方客户端，与 DeepSeek、月之暗面、智谱等模型服务商不存在关联，也未获得其赞助或认可。应用内展示的服务商标识仅用于识别对应的服务，相关商标归各自权利人所有。

本项目的开源许可证不授予任何商标使用权，包括本项目的名称与图标。

## 隐私

应用无账号体系。开发者不收集、不存储你的聊天内容与访问密钥，数据默认仅保存在设备本地；仅在两种情况下发生对外传输，一是你发起对话时会话内容与附件发送至你自行配置的模型服务，二是在你主动提交反馈时反馈内容与环境信息经第三方推送服务转达开发者。应用不含统计埋点与广告组件，密钥使用系统安全存储保管，界面只显示掩码。

## 补充说明

- 源码注释中出现的 `dshinhm` 指作者自有的同系列工程，非第三方组件，无许可义务。
- 源码注释中出现的 `cubeagent-stream-test` 指上游 Cube Chat（chatcube）的本地快照工程，也就是鸣谢名单里的 Cube Chat，非本项目自身模块。
- 源码注释引用了开发期的决策记录（如「八百三十八节」），对应账目不在本仓库内。
- 本项目由作者主导，并以 AI 编程助手协作完成编码。应用内「AI 辅助开发声明」页亦有披露。

## 反馈

欢迎通过 GitHub Issues 反馈问题。应用内也提供「反馈与建议」入口。

## 许可证

[Apache License 2.0](LICENSE)。

## 二次开发提示

Fork 后若要发布自己的版本，请务必修改 `AppScope/app.json5` 的 `bundleName`。华为应用市场以包名作为应用的唯一标识，不改包名将无法上架，也无法与原版共存于同一台设备。同时请替换应用名称与图标。

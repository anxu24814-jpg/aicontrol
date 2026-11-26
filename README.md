# AI 控制台（aicontrol）

自备密钥的多模型 AI 对话客户端，面向 HarmonyOS。

应用本身不提供模型服务、密钥与额度，需要你自行接入服务商并自备 API 密钥。

> A bring-your-own-key multi-model AI chat client for HarmonyOS. The app ships with no model service, no API keys and no credits.

## 功能概览

- **多协议多服务商**：支持 OpenAI 兼容、Anthropic、Gemini 三类接入协议，内置七家境内常见服务商模板，也可手动添加任意兼容服务。一个服务商可保存多支密钥并自动轮换，某支失效即切换。
- **模型与参数可配置**：模型自由添加，思考强度、温度、输出长度等参数可调，并可为模型标注工具调用、推理、视觉理解、内置联网等能力。
- **助手与提示词体系**：可创建多个助手，各自绑定模型、提示词与工具调用能力；系统提示词、会话提示词、助手提示词三层来源依次生效，支持变量占位。
- **联网搜索与工具调用**：内置免配置的联网搜索与网页抓取，模型可多轮调用工具完成任务。控制台助手能检索帮助中心回答用法问题，也能在你明确要求时代为调整设置、管理提示词、查询用量。支持接入 MCP 服务，工具按助手开关启用。
- **附件与文档识别**：拍照、照片与文件最多同时附加 5 个；pdf、docx、xlsx、ofd 发送前自动解析全文，图片类附件在支持视觉理解的模型上可直接识别，另内置端侧 OCR 识别引擎。
- **端侧运行环境**：内置 Node 24.22.3 与 CPython 3.13.18 两套运行时，可让模型在设备本地执行脚本、读写你授权的工作区目录；扩展包由你主动从 npm 或 PyPI 安装，下载请求不携带账号信息。
- **文件夹挂载与脚本工作台**：可授权应用读取指定文件夹供对话按需引用；脚本工作台提供 JavaScript 与模拟 Shell 两模式，执行结果可回传给模型继续处理。
- **本地优先**：会话、助手、提示词与偏好默认只保存在设备本地，支持全量备份恢复与同步到自己的 WebDAV 网盘。记忆、用量统计、加密会话（需生物识别验证）与隐私会话（仅留内存）一并提供。
- **手机 Web 端**：可在局域网内启动本地 Web 服务，用浏览器访问同一份会话（`web-ui/` 为浏览器端源码）。

## 构建

**环境要求**

- DevEco Studio：需支持 API 26（HarmonyOS 6.0），SDK 26.0.0
- 工程基线：`modelVersion` / `targetSdkVersion` / `compatibleSdkVersion` 均为 `26.0.0`

**预编译运行时不在本仓库内**

Node 与 CPython 两套运行时是交叉编译产物（`entry/libs/arm64-v8a/` 下 160 个 `.so`，含 127MB 的 `libnode.so`；以及 `entry/src/main/resources/rawfile/python/` 下三个运行时压缩包），总计约 320MB。逐字节二进制不适合放进 Git 仓库，故不随源码分发：

- 只想阅读或修改源码：直接克隆本仓库即可，无需下载。
- 想完整构建：到 [Releases](../../releases) 下载 `prebuilt-runtime-1.7.5.zip`，解压后把 `libs/` 与 `rawfile-python/` 分别放回 `entry/libs/arm64-v8a/` 与 `entry/src/main/resources/rawfile/python/`。二进制由 `scripts/node-runtime/factory/` 与 `scripts/python-runtime/factory/` 的构建脚本生成，这两个目录不在本仓库内。
- 只想安装使用：直接下载 Release 中已签名的安装包，见该版本的说明。

**步骤**

1. 用 DevEco Studio 打开工程，等待同步完成（依赖经 ohpm 拉取，含 `@cangjie-tpc/formula_hybrid`）。
2. 按上节放回预编译运行时（如需完整构建）。
3. 配置签名：`File` → `Project Structure` → `Signing Configs`，勾选 `Automatically generate signature`（需登录华为开发者账号）。
4. 构建并运行。

**说明**

- 本仓库不包含任何签名材料。`build-profile.json5` 的 `signingConfigs` 为空数组，需按上一步自行生成。
- 工程未随附 hvigor 命令行 wrapper（`hvigorw`），构建请在 DevEco Studio 内进行。
- 缺预编译运行时直接构建会在打包阶段报找不到 `libnode.so` / `libpython3.13.so`，这是预期行为，不是源码问题。

## 自检

`tools/verify/` 下是一组零第三方依赖的纯 node 检查件，不需要安装 DevEco Studio 与 HarmonyOS SDK，克隆下来即可运行，覆盖与平台无关的纯逻辑。

需要 Node.js **22.18 或更高**——检查件把 ArkTS 源码复制为 `.ts` 后靠 Node 的类型剥离直接执行，断言的就是应用里跑的同一份实现。

```bash
for f in sse-assert usage-stats-calc-check; do node tools/verify/$f.mjs || exit 1; done
```

| 检查件 | 覆盖 | 期望输出末行 |
| --- | --- | --- |
| `sse-assert.mjs` | SSE 帧解析，OpenAI 兼容 / Anthropic / Gemini / Responses 四协议请求体组装，提示词注入与变量替换，附件多模态，思考透传与回放占位，采样参数与缓存控制，工具调用底层与清洗，模型匹配，联网搜索解析，上下文用量估算与系数持久化 | `结果：491 过 / 0 败（契约 0 / 形态 491）` |
| `usage-stats-calc-check.mjs` | 用量统计纯函数：热力图周列与日历网格、连续活跃、月度聚合、数值格式化 | `用量统计纯函数断言 结果：64 过 / 0 败` |

同一组检查在 CI 上逐件运行，见 `.github/workflows/verify.yml`。这些检查件是作者开发仓中断言的公开副本，只覆盖纯逻辑面；依赖 SDK 的编译、UI 形态与真机行为不在本仓库内验证。

开发仓中另有五件同形制检查件（价格模板、跨会话检索、Markdown 复制、网络与文档解析、凭据存储），在 1.7.5 的工具域重构后断言锚点尚未对齐，暂不随本仓库发布。

## 目录结构

| 路径 | 内容 |
| --- | --- |
| `entry/` | 应用主模块，ArkTS 源码、资源与随包第三方资产（预编译运行时除外，见「构建」节） |
| `AppScope/` | 应用级配置与图标 |
| `web-ui/` | 手机 Web 端的浏览器端源码（React + Vite），构建产物随包在 `entry/src/main/resources/rawfile/webui/` |
| `tools/verify/` | 免 SDK 的纯逻辑检查件（见上节「自检」） |
| `docs/` | 部分设计规范文档 |

## 第三方组件与许可

本项目使用了多个开源组件与随包资产，完整许可证文本见 [`LICENSE-THIRD-PARTY.md`](LICENSE-THIRD-PARTY.md)。随包资源的许可文本随包分发在 `entry/src/main/resources/rawfile/` 各子目录的 `NOTICE.md`。

## 商标声明

本应用是第三方客户端，与 DeepSeek、月之暗面、智谱等模型服务商不存在关联，也未获得其赞助或认可。应用内展示的服务商标识仅用于识别对应的服务，相关商标归各自权利人所有。

本项目的开源许可证不授予任何商标使用权，包括本项目的名称与图标。

## 隐私

应用无账号体系。开发者不收集、不存储你的聊天内容与访问密钥，数据默认仅保存在设备本地；对外传输只发生在四种情况：你发起对话时会话内容与附件发送至你自行配置的模型服务；你使用联网搜索时关键词发送至搜索引擎；你主动提交反馈时反馈内容与环境信息（应用版本、系统版本、设备型号）经第三方推送服务转达开发者；你主动安装 Node 或 Python 扩展包时从 npm 或 PyPI 下载所选包，请求不携带账号信息。

应用不含统计埋点与广告组件，密钥使用系统安全存储保管，界面只显示掩码。完整政策见应用内「隐私政策」页。

## 补充说明

- 源码注释中出现的 `dshinhm` 指作者自有的同系列工程，非第三方组件，无许可义务。
- 源码注释中出现的 `cubeagent-stream-test` 指上游 Cube Chat（chatcube）的本地快照工程，也就是鸣谢名单里的 Cube Chat，非本项目自身模块。
- 源码注释引用了开发期的决策记录（如「八百三十八节」），对应账目不在本仓库内。
- 源码注释中的「决明」是作者的决策代号，指该条设计的拍板来源，不是第三方。
- `LICENSE-THIRD-PARTY.md` 中提到的 `scripts/node-runtime/`、`scripts/python-runtime/` 是运行时的交叉编译工程，与预编译二进制一并留在开发仓，不在本仓库内；此处仅作来源说明。
- 本项目由作者主导，并以 AI 编程助手协作完成编码。应用内「AI 辅助开发声明」页亦有披露。

## 反馈

欢迎通过 GitHub Issues 反馈问题。应用内也提供「反馈与建议」入口。

## 许可证

[Apache License 2.0](LICENSE)。

## 二次开发提示

Fork 后若要发布自己的版本，请务必修改 `AppScope/app.json5` 的 `bundleName`。华为应用市场以包名作为应用的唯一标识，不改包名将无法上架，也无法与原版共存于同一台设备。同时请替换应用名称与图标。

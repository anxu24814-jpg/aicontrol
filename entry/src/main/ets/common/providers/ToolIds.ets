// 工具稳定标识叶子（架构收口自 `common/providers/ToolTypes.ets` 外迁）：内置工具的 id
// 常量（件数随笔扩容，现数以 ToolTypes 注册块为准；函数名 = 请求侧 name，全工程禁裸
// 字符串）——工具域的**稳定标识**，由注册表（ToolTypes）、各域执行器、UI 页面与断言族
// 共同消费。
// · 为什么单独成文件：ToolChatSearch 需要两个 id 常量（isCrossSessionTool 判据）——它若
//   从 ToolTypes 引，就与 ToolTypes 引它的执行器构成模块环（坑50：环内模块作用域读对方
//   绑定 = 未初始化值，只读常量静默坏值、再走一步方法调用即启动 JsError）。id 常量落零
//   import 叶子后注册器**单向装配**（域件 → ToolIds、ToolTypes → 域件），环消失。
// · 禁什么：①本件**零 import**（叶子纪律——引一次就把可求值依赖带回叶子）；②工具域件
//   从本件引 id、**禁再从聚合根 ToolTypes 引 id**；③ToolTypes **不再对外转出**本件符号
//   （禁加 `export { … } from './ToolIds'`——转出会把环接回来）。
// · 常规工具默认属性（下文简称「常规默认」，不再逐件复读）：助手工具页对应卡开关
//  （assistants.tools 通道）、defaultEnabled=false 不进任何默认集合、不入 seed（非立身
//   能力，用户显式开）。

// ── 内置工具名常量 ──
export const TOOL_GET_TIME_INFO: string = 'get_time_info';
export const TOOL_ASK_USER: string = 'ask_user';
export const TOOL_SEARCH_WEB: string = 'search_web';
export const TOOL_SCRAPE_WEB: string = 'scrape_web';
// 内置浏览器三工具（读域在 ToolBrowse.ets / 动作域在 ToolBrowseAct.ets——常量在此归口）：
// browse_open 后台打开网页读渲染后正文 / browse_read 续读或取可交互元素或诊断信号 /
// browse_act 对当前页执行 scroll·click·type·select·press_key 动作；隐形宿主在
// common/BrowseWeb.ets；三件单列「浏览器控制」卡，启用面只由本卡开关决定（不随联网
// 三级闸门）
export const TOOL_BROWSE_OPEN: string = 'browse_open';
export const TOOL_BROWSE_READ: string = 'browse_read';
export const TOOL_BROWSE_ACT: string = 'browse_act';
// 浏览器截图（实现在 providers/ToolBrowseSnap.ets——常量在此归口）：browse_screenshot
// 截当前视口或整页长图，落盘工作区并附图
export const TOOL_BROWSE_SCREENSHOT: string = 'browse_screenshot';
// HTTP 请求工具（实现在 ToolHttp.ets——常量在此归口）：通用 HTTP 工具（method + URL +
// headers + body），写方法逐次确认（preflight 弹确认卡，设置页可切「自动通过」），
// GET/HEAD/OPTIONS 直通；defaultEnabled=false 不进默认集合（true = 静默向存量助手发放
// 写能力，不可接受）；单列独立卡——启用面只由助手工具页本卡开关决定，不随联网搜索
export const TOOL_HTTP_REQUEST: string = 'http_request';
// HTTP 凭据查名工具（实现在 ToolEnv.ets——常量在此归口）：模式驱动第三件——不走
// assistants.tools 启用清单、工具页不出页，助手启用清单含 http_request 时由
// ChatContextUsage.collectTools 追加声明（与 http_request 同进退）；回执只含名称清单
//（值永不出现在对话，硬边界——注入链在 HttpCredentials/ToolHttp）
export const TOOL_ENV_LIST: string = 'env_list';
export const TOOL_SEARCH_HELP: string = 'search_help';
//（set_app_preference 已随控制台合并笔退役——get_app_preference 读件保留，沿革见变更记录）
export const TOOL_GET_APP_PREFERENCE: string = 'get_app_preference';
// 提示词读写域两工具（实现在 ToolPrompts.ets——常量在此归口，注册/拦截/seed 同源引用）
export const TOOL_EDIT_SYSTEM_PROMPT: string = 'edit_system_prompt';
export const TOOL_MANAGE_PROMPTS: string = 'manage_prompts';
// 功能模型域两工具（实现在 ToolFunctional.ets——常量在此归口，注册/拦截/seed 同源引用）
export const TOOL_SET_FUNCTIONAL_MODEL: string = 'set_functional_model';
export const TOOL_EDIT_TITLE_PROMPT: string = 'edit_title_prompt';
// 用量统计查询工具（实现在 ToolUsageStats.ets——常量在此归口，注册/拦截/seed 同源引用）
export const TOOL_GET_USAGE_STATS: string = 'get_usage_stats';
// 记忆检索工具（实现在 MemoryGen.ets——常量在此归口）：模式驱动工具——声明与否由记忆页
//「读取方式」决定（ChatSendCtrl 追加），不走 assistants.tools 启用清单，也不进助手工具页
export const TOOL_SEARCH_MEMORY: string = 'search_memory';
// 跨会话检索工具（实现在 ToolChatSearch.ets——常量在此归口）：常规工具（助手工具页开关，
// 常规默认）；隐私会话不声明（ChatSendCtrl 声明层过滤，与记忆工具隐私闸同源）
export const TOOL_SEARCH_CHATS: string = 'search_chats';
// 跨会话读取工具（实现在 ToolChatSearch.ets——常量在此归口）：get_chats 两动作（list
// 最近会话清单 / read 按标题或会话编号定位通读消息原文，支持 conversationId 路）——
// 常规工具（本地检索卡开关，常规默认、不入 seed）；与 search_chats 同属跨会话读取域，
// 隐私会话经 isCrossSessionTool 双件同闸不声明
export const TOOL_GET_CHATS: string = 'get_chats';
// 知识库检索工具（实现在 ToolKnowledge.ets——常量在此归口；用户可见名「知识库」）：
// 常规工具（知识库卡开关，常规默认）；**只读**——search / list 两动作，无写动作。
//「工具操作面 ⊆ UI 操作面」仍成立（书级改名与删库只有 UI 有，工具侧没有）；隐私会话
// 照常声明（知识库非会话内容，不进 isCrossSessionTool 名单——理由见域件头注释）
export const TOOL_SEARCH_KNOWLEDGE: string = 'search_knowledge';
// 知识库管理工具（实现在 ToolKnowledge.ets 同文件——常量在此归口）：**知识库唯一写口**
//——七动作 list / get / read_file / create_book / create / update / delete（get 与
// read_file 为只读读回；条目级三写全开含 delete；**书级只开放建库**，改名与删库留给
// 设置页）。常规工具（知识库卡开关，常规默认、不入 seed）；写入恒带 source='assistant'
//（UI 编辑页恒 'user'）。定位范围 = **全部书，不取助手启用集**（与 search_knowledge
// 的启用集作用域刻意不同：新建的库默认不被任何助手启用，卡启用集会让助手刚建的库写不
// 进去——闸与建议之别见域件头注释）；隐私会话照常声明（同上）
export const TOOL_MANAGE_KNOWLEDGE: string = 'manage_knowledge';
// 记忆管理工具（实现在 ToolMemoryManage.ets——常量在此归口）：★ 非独占件（原
// console-exclusive 修改件，决明拍板乙案）——普通助手经「记忆」卡开关可开；常规默认，
// 控制台助手经 seed 默认开。
// ★ 作用域（决策 13 已知后果，勿"顺手修"）：执行器选库由执行上下文携带的记忆作用域决定
//（ToolExecutionContext.memoryScopeAssistantId）——助手「记忆作用域」= 助手记忆时锁该
// 助手自己的库，留在默认「全局记忆」时锁**全局库**（改的会影响所有用全局记忆的助手，
// 这是拍板接受的取舍；用户要隔离就去助手记忆页切作用域）。禁加确认门、禁加作用域闸、
// 禁改 memoryScope 默认值
export const TOOL_MANAGE_MEMORY: string = 'manage_memory';
// 技能加载工具（实现在 ToolSkill.ets——常量在此归口）：模式驱动工具第二件——声明与否由
//「该助手是否启用了技能」决定（ChatSendCtrl 追加），不走 assistants.tools 启用清单，
// 也不进助手工具页
export const TOOL_USE_SKILL: string = 'use_skill';
// 管理技能工具（实现在 ToolSkill.ets——常量在此归口）：技能管理卡**非独占**件——普通
// 助手工具页技能管理卡开关可开，控制台助手 seed 默认开；list/get/create/update 四 action
// 无 delete（删除不可逆且绕过 UI 确认链，desc 指引 设置 → 技能库 手动删，manage_prompts
// 先例）
export const TOOL_MANAGE_SKILLS: string = 'manage_skills';
// 服务商与模型读取（实现在 ToolProvider.ets——常量在此归口）：console-exclusive 读取件，
// 只读查询服务商清单/模型清单/当前会话生效连接；★ 不读密钥与自定义头明文（三敏感列
// 零出现，断言负向钉）
export const TOOL_GET_PROVIDER_CONFIG: string = 'get_provider_config';
// 费用估计读取（实现在 ToolCostStats.ets——常量在此归口）：console-exclusive 读取件，
// 只读查询费用估计页三档的四格/排行/用途分布；四格构造与费用页同源
//（UsageStatsCalc.buildCostCells 单源）
export const TOOL_GET_COST_STATS: string = 'get_cost_stats';
// 位置工具（实现在 ToolLocation.ets——常量在此归口，决明拍板精准定位 + 默认关）：
// get_location 单次取设备当前位置（WGS-84 + 逆地理地址尽力而为），常规卡开关——
// defaultEnabled=false 不进默认集合（位置是敏感面，用户显式开）；权限 =
// APPROXIMATELY_LOCATION + LOCATION 双声明 user_grant（本仓首批，域件头注释），执行期
// 首次调用弹窗授权
export const TOOL_GET_LOCATION: string = 'get_location';
// 日程工具域四件（实现在 ToolCalendar.ets——常量在此归口，决明拍板查/建/改/删全做）：
// get_calendar_events 查询 / create_calendar_event 创建 / update_calendar_event 修改 /
// delete_calendar_event 删除——只读写「本应用创建的日程」（自建账户 AiControl，
// READ/WRITE_CALENDAR 两枚开放权限 user_grant）。日程卡常规开关——defaultEnabled=false
// 不进默认集合（日程是敏感面，显式开），不入控制台 seed、所有助手可开；创建/修改 = 写档、
// 删除 = 不可逆档恒问人（三写件带 preflight，见域件头注释）
export const TOOL_GET_CALENDAR_EVENTS: string = 'get_calendar_events';
export const TOOL_CREATE_CALENDAR_EVENT: string = 'create_calendar_event';
export const TOOL_UPDATE_CALENDAR_EVENT: string = 'update_calendar_event';
export const TOOL_DELETE_CALENDAR_EVENT: string = 'delete_calendar_event';
// 写入剪贴板工具（实现在 ToolClipboard.ets——常量在此归口，决明拍板只做零权限写入）：
// 把文本写入系统剪贴板（零权限——官方 FAQ「复制内容是系统默认支持的能力，不需要额外
// 申请权限」；写路径经 common/Clipboard.ets 单源）。常规卡开关——defaultEnabled=false
// 不进默认集合（显式开）、不入 seed；零 preflight（描述句防线 + 默认关 + 工具卡可见
// 结果）。★ 读剪贴板未做：READ_PASTEBOARD 属受限开放权限（system_basic + user_grant，
// 须 ACL），官方白名单不含 AI 助手
export const TOOL_CLIPBOARD_WRITE: string = 'clipboard_write';
// 文件工作区三工具（实现在 ToolWorkspace.ets——常量在此归口）：workspace_list 列出工作区
// 全部文件 / workspace_read 按显示名读文本文件原文 / workspace_write 把文本保存成工作区
// 文件（同名覆盖，无模型侧删除——删除只在用户管理面）。常规工具（「文件工作区」卡开关，
// 常规默认）；声明面 = 执行面（无全局开关，无执行器开关复查——http_request 同款）；无
// 隐私特判（隐私会话功能已全链退役）；工作区文件不进备份不随删会话级联（跨会话持久资产）
export const TOOL_WORKSPACE_LIST: string = 'workspace_list';
export const TOOL_WORKSPACE_READ: string = 'workspace_read';
export const TOOL_WORKSPACE_WRITE: string = 'workspace_write';
// ★ 会话附件导入工作区
export const TOOL_WORKSPACE_IMPORT: string = 'workspace_import';
// 文件工作区目录四工具（实现在 ToolWorkspace.ets——常量在此归口）：mkdir 建文件夹 /
// rename 重命名（文件或文件夹，改名不覆盖）/ move 移动（toDir 必须已存在，文件夹环检查
// 拒）/ delete 删除（走确认链——不可逆档任何数据管理档位都恒问人；mkdir/rename/move 无
// 确认拍板——可逆、管理页可删）。常规工具（「文件工作区」卡开关，常规默认）；(dir,
// name) 定位、name 目录内唯一跨目录可同名
export const TOOL_WORKSPACE_MKDIR: string = 'workspace_mkdir';
export const TOOL_WORKSPACE_RENAME: string = 'workspace_rename';
export const TOOL_WORKSPACE_MOVE: string = 'workspace_move';
export const TOOL_WORKSPACE_DELETE: string = 'workspace_delete';
// ★ 表格数据生成 Excel（任务书-工作区文件格式支持）：rows JSON 二维数组原串 → 真 .xlsx
//（产出核 WorkspaceXlsx + 落库编排 WorkspaceDbXlsx + 桥页反读自检，坏件永不落库）。常规
// 工具（「文件工作区」卡开关，常规默认）；write 族无 preflight（可逆、管理页可删）
export const TOOL_WORKSPACE_WRITE_XLSX: string = 'workspace_write_xlsx';
// ★ 检索两工具（拍板均按推荐）：workspace_glob 按名称模式查找文件与文件夹（glob→RegExp
// 五规则 + 无 / 模式 basename 兜底，上限 500 字典序）/ workspace_grep 在文本文件内容里
// 搜索正则（只扫 text 档 + 三重闸 2MB/4MB/100，非法正则回退字面量）。常规工具
//（「文件工作区」卡开关，常规默认）；只读零 preflight、零政策字段
export const TOOL_WORKSPACE_GLOB: string = 'workspace_glob';
export const TOOL_WORKSPACE_GREP: string = 'workspace_grep';
// ★ 对既有文本文件做定点替换编辑（任务书-工作区文件编辑工具）：三级级联匹配（exact →
// line_trimmed → block_anchor，蓝本 RikkaHub TextReplacers）+ 先读后编硬门（本会话 read
// 过且行值未变才放行，链外行为门）+ 直写无备份（拍板）。常规工具（「文件工作区」卡开关，
// 常规默认）；零 preflight（编辑就地改既有行、管理页可删，可逆性成立）、零政策字段
export const TOOL_WORKSPACE_EDIT: string = 'workspace_edit';
// ★ staging 入向桥：把工作区件复制进本会话临时区（二进制进脚本的唯一通道——模型经
// token 转手中转二进制不可行）。常规工具；随域拆分迁助手工具页「脚本工作台」卡（原
// codeWorkbench 三面闸退役——唯一消费方是脚本沙箱）；零 preflight（拷贝可逆、源只读、
// 临时区可清）
export const TOOL_WORKSPACE_STAGE: string = 'workspace_stage';
// ★ 压缩包三工具（任务书-附件重发与ZIP三件Office补丁-20261031 U-B1；实现在
// providers/ToolZip.ets——常量在此归口）：zip_list 查看压缩包条目清单 / zip_extract 解压
// 吸入工作区（瞬态解压 + 实测值执法 + 目录树与扁平 UUID 物理文件落正式区）/ zip_create
// 把工作区文件夹打包成 zip。常规工具（「文件工作区」卡开关，常规默认）；零 preflight
//（产物可逆、管理页可删）；输入只收工作区相对路径（附件先 workspace_import 导入）
export const TOOL_ZIP_LIST: string = 'zip_list';
export const TOOL_ZIP_EXTRACT: string = 'zip_extract';
export const TOOL_ZIP_CREATE: string = 'zip_create';
// ★ Office 补丁工具（任务书-附件重发与ZIP三件Office补丁-20261031 U-B2；实现在
// providers/ToolOffice.ets——常量在此归口）：office_patch 编辑工作区里的 docx / xlsx / pptx
//（ops JSON 数组原串多操作、fail-fast 全或无、恒写新文件吸收入正式区——xlsx setCell 恒转
// inlineStr 禁改 sharedStrings 表）。常规工具（「文件工作区」卡开关，常规默认）；零
// preflight（产物为新文件可逆、管理页可删）；输入只收工作区相对路径（附件先 workspace_import）
export const TOOL_OFFICE_PATCH: string = 'office_patch';
// 文件夹挂载工具族（实现在 ToolMount.ets——常量在此归口）：mount_list 列出挂载目录内容
//（不传 mountId 时回挂载清单）/ mount_read 读取挂载内文本与图片（含文档解析）/
// mount_write 写入挂载内文本文件（三方式 + 确认链——新建与追加跟数据管理档、整写覆盖
// 不可逆档恒问）/ mount_copy_out 把挂载内文件复制进文件工作区（零确认）/ mount_copy_in
// 把工作区文件复制进挂载（与 copy_out 反向；写挂载侧故带模式闸与两档确认）/ mount_delete
// 把挂载内文件或文件夹删除到系统回收站（可恢复；写挂载侧故带模式闸与恒不可逆档确认）。
// 常规工具（「文件夹挂载」卡开关，常规默认）；零政策字段 ⇒ 控制台助手按封顶缺省不可见
//（开放需另拍板）。与 workspace_* 族平行独立（沙箱域 vs 授权外部域，两域根语义互斥）
export const TOOL_MOUNT_LIST: string = 'mount_list';
export const TOOL_MOUNT_READ: string = 'mount_read';
export const TOOL_MOUNT_WRITE: string = 'mount_write';
export const TOOL_MOUNT_COPY_OUT: string = 'mount_copy_out';
export const TOOL_MOUNT_COPY_IN: string = 'mount_copy_in';
export const TOOL_MOUNT_DELETE: string = 'mount_delete';
// 代码工作台两工具（实现在 ToolCodeExec.ets——常量在此归口）：exec_code 编写并运行
// JavaScript 脚本（沙箱 = 系统自带 JSVM 经 libcodeexec.so，无 JIT 零新权限）/
// exec_output_read 分页读回本会话临时区文件（exec_code 超长输出的溢出件与脚本 fs.write
// 的产物）。常规工具（「脚本工作台」独立卡开关——自「文件工作区」卡拆出，原
// codeWorkbench 政策字段与总开关三面闸退役）；常规默认；脚本只能读写本会话临时区
//（filesDir/workspace-tmp/<会话id>/），网络只能走宿主函数 httpGet，默认发 GET 且写方法
// 需全局开关开启写请求授权，限本助手与全局已授权域名的并集（预授权清单空 = 全禁）
export const TOOL_EXEC_CODE: string = 'exec_code';
export const TOOL_EXEC_OUTPUT_READ: string = 'exec_output_read';
// Python 执行工具（实现在 ToolPyExec.ets——常量在此归口，注册面自注册）：exec_python 在
// 内嵌 CPython 3.13 里运行 Python 源码（28 预置包，会话命名空间续算，cwd = 会话临时区，
// save() 登记转存文件工作区）。常规工具（「Python 运行」独立卡开关——默认关，紧邻代码
// 工作台卡，两卡互不联动）；常规默认；执行走确认卡（写档，routeConfirmPrompt 三档归一）
export const TOOL_EXEC_PYTHON: string = 'exec_python';
// Node 执行工具（实现在 ToolNodeExec.ets——常量在此归口，注册面自注册）：exec_node 在内嵌
// Node.js 24.22.3 里运行 JavaScript 源码（同会话变量与模块缓存跨轮保留，cwd = 会话临时区，
// save() 登记转存文件工作区，action 为 read_output 时只分页读临时区文件）。常规工具（「Node
// 运行」独立卡开关——默认关，紧随「Python 运行」卡，三张执行卡互不联动）；defaultEnabled=
// false 不进默认集合；执行走确认卡（写档，routeConfirmPrompt 三档归一），read_output 不弹卡
export const TOOL_EXEC_NODE: string = 'exec_node';
// AI 配置工具域四件（常量在此归口，注册在 ToolTypes、执行器分居 ToolProviderAdmin /
// ToolModelAdmin / ToolProviderProbe）：manage_providers 服务商管理十动作 / manage_models
// 模型管理六动作 / test_provider 连接测试与模型发现 / manage_balance 余额配置与查询。
// 全部 console-exclusive + defaultEnabled=false 不进任何默认集合；密钥明文硬边界——工具
// 读不到也写不了任何密钥明文，条目由工具建占位行、明文由用户在安全输入面板或设置页填写
export const TOOL_MANAGE_PROVIDERS: string = 'manage_providers';
export const TOOL_MANAGE_MODELS: string = 'manage_models';
export const TOOL_TEST_PROVIDER: string = 'test_provider';
export const TOOL_MANAGE_BALANCE: string = 'manage_balance';
// 图表工具（实现在 ToolChart.ets——常量在此归口，chart_display 形态）：把数据画成图表
// 显示在对话里（入参即数据、execute 纯校验零绘制、渲染层解析同一入参自绘）。「图表」卡
// 常规开关（常规默认）；零政策字段 ⇒ 控制台助手按封顶缺省不可见不可开不可调；零
// preflight（只读展示类——零外部副作用、零落库、零系统能力）
export const TOOL_CHART_DISPLAY: string = 'chart_display';

// ★ 随形说明：ToolTypes 侧三名单（CONSOLE_EXCLUSIVE_TOOLS / MODE_DRIVEN_TOOLS /
// WEB_DOMAIN_TOOLS）已改为**随注册项派生**退役（consoleExclusive 亦随控制台合并笔退役）
//——上文偶见的历史归类表述只记录当时动作，判别语义现走 ToolEntry 的 webDomain /
// modeDriven 字段。

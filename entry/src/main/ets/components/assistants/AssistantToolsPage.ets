// 助手工具页签三级页：编辑页「工具调用」分区卡 push，param = 助手 id。
// 页面形态（决明分组指令定稿；2026-11-01 归并笔决明「应用管理归入本机与设备、图表归入
// 文件与代码」——两张单组卡机制随归并退役，原「应用管理不与通用组混排」「图表恒末卡」
// 两句旧口径同日推翻；应用管理对全部助手可见可开的可见性口径不变）：**四张组卡**——
// 组卡内每行 = 原一张功能卡（行 = 图标 + 组名 + 副标题 + 开关，行间官方 0.5vp 分割线），
// 页序 = 组卡1（基础能力/位置/日程/剪贴板/应用管理）→ 组卡2（联网搜索/浏览器控制/
// HTTP 请求）→ 组卡3（文件工作区/文件夹挂载/脚本工作台/图表）→ 组卡4（记忆/知识库/
// 本地检索/技能管理）；四张组卡各带卡外板块标题（本机与设备/联网与请求/文件与代码/
// 记忆与检索）。
// 分组轴（分组成员 = 能力域相邻）：组卡1 本机与助手交互面 / 组卡2 网络面 / 组卡3 文件与
// 代码面 / 组卡4 记忆与检索面；组成员常量单源在 ToolTypes 注册表，本页归并表只决定「哪几组
// 排在同一张卡」——新增工具照旧只改注册项；未归组新组落「其他能力」兜底卡，不静默消失。
// 每行一枚开关 = 整组工具批量进出启用清单（成员明细行 / 组头计数 / 展开折叠机制已整体退役）。
// ★ MCP 服务器绑定卡已整体迁出（决明「mcp 移出工具调用」拍板）——现为独立三级页
// AssistantMcpPage（编辑页连接组卡「MCP」行 push，行形制与开关链原样搬迁，本页零残留）；
// 开关落库仍写 assistants.mcpServers 列（解析/序列化单源 McpText，禁复用 tools 解析）。
// ★ 卡口径统一（七百三十二节）：卡显示态判定单源 ToolTypes——visibleToolGroups（可见卡）/
// enablableToolMembers（卡内可开件分母）/ toolGroupAllOn（整卡开关）三件由本页与编辑页
//「工具调用」卡面摘要（报「已开卡数/卡总数」）共用，原页内三方法退化为薄委托，**禁两处
// 各写一套放行逻辑**。开关切换即时落库（「选择即落库不经保存键」），assistants.tools 列
// 存启用 id 清单 JSON 串（'' = 默认集合）。发送链 = ChatPromptState.load 同链解析 →
// ChatSendCtrl.defsFor 查声明（细则见 ToolTypes 头注释）——底层链路零改动：本页只管分组
// 呈现，逐件存取与逐件声明原样。
// ★ 全部工具对全部助手可开可关（原 search_help 控制台锁定 + console-exclusive 反向拦截
// 两闸已随控制台助手退役整段删除），剩余拦截因 = 联网域从属件压制单因（判定单源
// enableBlockReason / canEnable，批量路径禁另写一套放行逻辑——规范 §4.2）。
// ★ 联网域从属件单向绑定（B 案，从属 search_web 本体；从属件现 = scrape_web 一件——浏览
// 三件已随浏览器控制独立卡移出 WEB_DOMAIN_TOOLS 不受此闸）：从属件不进卡开关分母
//（groupEnablableMembers 可开件口径），批量开时两段式按批后目标集合求值防「全开误挡」；
// 显示压制不改写 enabledIds（放开闸门回到用户原态）。压制判据单维（助手清单是否含联网
// 搜索——总开关已退役）。
// ★ isModeDriven 工具（search_memory / use_skill）不进本页——声明由模式开关驱动
//（ChatSendCtrl 追加），过滤落点 = ToolTypes.visibleToolGroups（成员与卡两级同做，模式件
// 不进 enabledIds）。
// ★ 工具运行参数全局化（决明拍板「只在设置页全局控制」）：原两张滑轨卡（工具调用轮数上限/
// 搜索结果条数）已整体迁出——轮数在 设置 → 工具调用 页、条数在其下联网搜索页（全局偏好键
// prefToolStepLimit / prefSearchResultCount，全助手一份）；原助手级两列在库内退役为墓碑
//（不复用、不读取）；本页自此只承载工具启用清单。页尾「脚本联网域名」自绘授权卡同笔撤除
//——域名管理迁设置侧总览/管理两页 + 助手编辑页入口卡。
// 刷新链：无保存动作 → onBackPressed pop({saved:true})（坑17「无保存动作的完成返回」姿势）
// 刷编辑页卡面摘要；开关落库失败 toast 不静默（开关状态回滚由 onPop 重拉兜底）。
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_TOOLS_PAGE } from '../../common/RouteNames';
import { SECTION_GAP, SECTION_HEADER_GAP } from '../../common/Theme';
import { InfoCard } from '../InfoCard';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE, SETTING_ICON_GRAY, SETTING_ICON_GREEN, SETTING_ICON_ORANGE, SETTING_ICON_PURPLE } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';
import { ToolEntry, ToolGroup,
  isWebDomainTool, parseEnabledToolIds,
  serializeEnabledToolIds, TOOL_GROUP_APP, TOOL_GROUP_BASIC, TOOL_GROUP_BROWSE, TOOL_GROUP_CODE,
  TOOL_GROUP_HTTP,
  TOOL_GROUP_KNOWLEDGE, TOOL_GROUP_LOCAL, TOOL_GROUP_LOCATION, TOOL_GROUP_MEMORY,
  TOOL_GROUP_SKILL, TOOL_GROUP_WEB, TOOL_GROUP_WORKSPACE, TOOL_GROUP_CALENDAR,
  TOOL_GROUP_CLIPBOARD,
  toolTitle } from '../../common/providers/ToolTypes';
// 域件自注册组标签（ToolMount / ToolChart / ToolPyExec——ToolTypes 不再转出该常量，同款纪律）
import { TOOL_GROUP_MOUNT } from '../../common/providers/ToolMount';
import { TOOL_GROUP_CHART } from '../../common/providers/ToolChart';
import { TOOL_GROUP_PYTHON } from '../../common/providers/ToolPyExec';
import { TOOL_GROUP_NODE } from '../../common/providers/ToolNodeExec';
// 卡显示态判定单源 ToolCardView.ets（卡视图与摘要计数）
import { enablableToolMembers, isToolSuppressedInList, toolGroupAllOn,
  visibleToolGroups } from '../../common/providers/ToolCardView';
import { TOOL_SEARCH_WEB } from '../../common/providers/ToolIds';
import { queryAssistant, updateAssistantTools } from '../../common/store/AssistantDb';

// ── 组卡归并表（决明「…合为组卡N」；2026-11-01 归并笔「应用管理归入本机与设备、图表
// 归入文件与代码」，两张单组卡随归并退役）──
// 每项 = 一张组卡，卡内行序即表内组序；卡内成员经 visibleToolGroups 过滤，全空则整卡不出
//（模式驱动件被滤空时整卡不出）。组成员常量单源在 ToolTypes，本表只决定「哪几组排在同一
// 张卡」——新组漏归时落「其他能力」兜底卡，不静默消失，见 cardBundles。
const TOOL_BUNDLES: string[][] = [
  [TOOL_GROUP_BASIC, TOOL_GROUP_LOCATION, TOOL_GROUP_CALENDAR, TOOL_GROUP_CLIPBOARD,
    TOOL_GROUP_APP],
  [TOOL_GROUP_WEB, TOOL_GROUP_BROWSE, TOOL_GROUP_HTTP],
  [TOOL_GROUP_WORKSPACE, TOOL_GROUP_MOUNT, TOOL_GROUP_CODE, TOOL_GROUP_PYTHON,
    TOOL_GROUP_NODE, TOOL_GROUP_CHART],
  [TOOL_GROUP_MEMORY, TOOL_GROUP_KNOWLEDGE, TOOL_GROUP_LOCAL, TOOL_GROUP_SKILL]
];
// 未归组兜底卡名（将来新注册组未进 TOOL_BUNDLES 时落此卡——防「加了工具页上看不见」）
const TOOL_BUNDLE_OTHER: string = '其他能力';
// 卡外板块标题：四张组卡按归并表首组 title 映射；兜底卡用「其他能力」
const TOOL_SECTION_LOCAL_DEVICE: string = '本机与设备';
const TOOL_SECTION_NETWORK: string = '联网与请求';
const TOOL_SECTION_FILE_CODE: string = '文件与代码';
const TOOL_SECTION_MEMORY: string = '记忆与检索';

// 组卡条目（一张卡 = 若干功能组；title 只作键与兜底卡名，卡面不显示）
interface ToolCardBundle {
  title: string;
  // 卡外板块标题（四张组卡 + 兜底卡渲染；原单组卡免标题分支已随归并笔退役）
  sectionTitle: string;
  groups: ToolGroup[];
}

@Component
export struct AssistantToolsPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id）
  private rowId: string = '';
  // 卡视图（aboutToAppear 一次性读取——注册表进程级不变，无需刷新链）
  private groups: ToolGroup[] = [];
  // 启用集合（卡开关显示态单一真源；@State 驱动重建）
  @State enabledIds: string[] = [];
  // 卡重建纪元（坑44/80 家族）：GroupSettingCard.items 是普通成员入参，父组件重渲不更新它
  // → 行定格首帧。本纪元进卡 ForEach 键（键变重建 = 规范 §3 主通道）：库读回、卡开关批量
  // 交互都自增 → 组卡整体重建 → 行内容拉新值
  @State toggleEpoch: number = 0;

  // 卡视图（aboutToAppear 一次性读取）。★ 模式驱动件（search_memory / use_skill）自视图
  // 过滤不出页——声明由模式开关驱动，页上再放开关即「模式开关 × 工具页开关」双重控制打架。
  // 过滤与卡显示态判定上迁 ToolTypes（visibleToolGroups / toolGroupAllOn），本页与编辑页
  // 卡面摘要同源（原页内三方法已改为薄委托）

  aboutToAppear(): void {
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_TOOLS_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    // 卡视图（模式驱动件过滤——注册表进程级不变，一次读取即定）
    this.groups = visibleToolGroups();
    queryAssistant(param)
      .then((row): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.enabledIds = parseEnabledToolIds(row.tools);
        this.toggleEpoch += 1;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 联网域从属件压制判定（B 案单向绑定；从属件现 = scrape_web 一件——浏览三件已出域独立
  // 成卡）：归属助手启用清单不含「联网搜索」（能力上限未给）时整体不可用（search_web
  // 本体不做自压制，判据单源 ToolTypes；压制单维——总开关已退役）。★ 只影响显示态与开启
  // 拦截，enabledIds 与 DB 的 assistants.tools 一个字不动（显示压制不改写存储）——放开
  // 闸门后回到用户原态；批路径吃候选集合形参（缺省 = 当前集合）：卡批量开时「联网搜索」与
  // 从属件同卡同批，按批后目标集合判定才不误挡
  private isToolSuppressed(name: string, candidateIds: string[] = this.enabledIds): boolean {
    return isToolSuppressedInList(name, candidateIds);
  }

  // 开启/关闭判定——卡批量开/关的双判定**单一来源**（规范 §4.2：禁另写一套放行逻辑，两处
  // 各写一套 = 漂移源）。被拦原因文案也由 enableBlockReason 单源产出（toast 禁另写裸条件）；
  // canEnable 吃候选集合形参（缺省 = 当前集合），卡批量传批后目标集合，显示态分母求值传当前集合
  private enableBlockReason(name: string, candidateIds: string[]): string {
    // （console-exclusive 拦截与脚本工作台总开关两分支已分别随控制台合并笔 / 键退役删除
    //——三件脚本族改随「脚本工作台」卡开关进出）
    if (!this.isToolSuppressed(name, candidateIds)) {
      return '';
    }
    return '「' + toolTitle(name) + '」依赖「联网搜索」，请先开启「联网搜索」';
  }

  private canEnable(name: string, candidateIds: string[] = this.enabledIds): boolean {
    return this.enableBlockReason(name, candidateIds) === '';
  }

  // 集合等价（空转守卫用）：卡批量目标集合与当前集合一致时跳过落库（如整卡被闸全挡——
  // 无成员可动，白写一次库）
  private isSameSet(a: string[], b: string[]): boolean {
    return a.length === b.length && a.every((id: string): boolean => b.includes(id));
  }

  // 卡内可开件（卡开关显示态与受限标注的分母）：判定上迁 ToolTypes.enablableToolMembers
  //（被压制的联网从属件不进分母——若进，联网卡永不全开，开关点开后仍显示关〔用户困惑源〕）；
  // 求值传当前集合（压制判定依赖候选集合含联网搜索）
  private groupEnablableMembers(group: ToolGroup): ToolEntry[] {
    return enablableToolMembers(group, this.enabledIds);
  }

  // 卡开关显示态 = 可开件全开（可开件 0 = 恒关；判定单源 toolGroupAllOn，与编辑页卡面摘要同源）
  private groupAllOn(group: ToolGroup): boolean {
    return toolGroupAllOn(group, this.enabledIds);
  }

  // ── 组卡装配 ──

  // 组卡板块标题映射（入参 = 归并表首组 title）：四张归并组卡按能力域定名；未映射的新组回
  // 自身 title（不留空标题——SectionHeader 空主标题仍占一行）
  private bundleSectionTitle(firstGroupTitle: string): string {
    if (firstGroupTitle === TOOL_GROUP_BASIC) {
      return TOOL_SECTION_LOCAL_DEVICE;
    }
    if (firstGroupTitle === TOOL_GROUP_WEB) {
      return TOOL_SECTION_NETWORK;
    }
    if (firstGroupTitle === TOOL_GROUP_WORKSPACE) {
      return TOOL_SECTION_FILE_CODE;
    }
    if (firstGroupTitle === TOOL_GROUP_MEMORY) {
      return TOOL_SECTION_MEMORY;
    }
    return firstGroupTitle;
  }

  // 按归并表把可见组装成卡序列（单一入口，页序与空卡过滤都在此）：①四张组卡按 TOOL_BUNDLES
  // 表序；②过滤后无成员的组卡整张不出（不留空壳）；③未进表的新组收「其他能力」兜底卡
  //（有才出）。每卡带 sectionTitle——按首组 title 映射板块标题，兜底卡用「其他能力」
  //（原末尾两张单组卡机制已随归并笔退役——应用管理归组卡1、图表归组卡3）
  private cardBundles(): ToolCardBundle[] {
    const bundles: ToolCardBundle[] = [];
    const used: string[] = [];
    for (const titles of TOOL_BUNDLES) {
      const groups: ToolGroup[] = [];
      for (const title of titles) {
        const group: ToolGroup | undefined =
          this.groups.find((g: ToolGroup): boolean => g.title === title);
        if (group !== undefined) {
          groups.push(group);
          used.push(title);
        }
      }
      if (groups.length > 0) {
        bundles.push({
          title: titles[0],
          sectionTitle: this.bundleSectionTitle(titles[0]),
          groups: groups
        });
      }
    }
    const others: ToolGroup[] = this.groups.filter((g: ToolGroup): boolean =>
      !used.includes(g.title));
    if (others.length > 0) {
      bundles.push({ title: TOOL_BUNDLE_OTHER, sectionTitle: TOOL_BUNDLE_OTHER, groups: others });
    }
    return bundles;
  }

  // 组卡行数据（每行 = 原一张功能卡：图标 + 组名 + 副标题 + 开关，行尾 Toggle 为唯一控制面；
  // items 走方法返回类型化数组，ArkTS 禁 build 内对象字面量数组）。★ 底色按**卡**取
  //（bundle.title = 归并表首组），同卡所有行同色——按 group.title 逐行取色会让一张归并卡
  // 内出现多色。
  private bundleItems(bundle: ToolCardBundle): GroupEntryItem[] {
    const rows: GroupEntryItem[] = [];
    for (const group of bundle.groups) {
      rows.push({
        icon: this.cardIcon(group.title),
        iconBg: this.cardIconBg(bundle.title),
        label: group.title,
        secondary: this.cardSecondary(group),
        toggleValue: (): boolean => this.groupAllOn(group),
        onToggle: (isOn: boolean): void => this.toggleGroup(group, isOn)
      });
    }
    return rows;
  }

  // 卡副标题显示态：①可开件 0 = 整卡受限（副标题报受限，开关恒关，点击走 toggleGroup 汇总
  // toast）；②正常报 cardDescOf 功能描述。①现为**兜底**——将来再出「混排卡被全挡」形态时
  // 仍如实报因（届时改文案即可），勿当死码删
  private cardSecondary(group: ToolGroup): string {
    if (this.groupEnablableMembers(group).length === 0) {
      return '暂无可开启的工具';
    }
    // （原「本地检索卡控制台缩单件副标题」分支已随控制台合并笔退役）
    return this.cardDescOf(group.title);
  }

  // 卡副标题功能描述（新主副标题的副行：描述该卡能力，不逐件枚举；受「面向用户文案
  // 写作规约」约束；单行 ≤14 字防组卡行 64vp 固定行高溢出）
  private cardDescOf(title: string): string {
    if (title === TOOL_GROUP_BASIC) {
      return '获取时间，需要时向你提问';
    }
    // 位置：自基础能力卡剥出——敏感面显式单开
    if (title === TOOL_GROUP_LOCATION) {
      return '获取设备当前位置';
    }
    // 日程：四件（查询/创建/修改/删除），敏感面显式单开
    if (title === TOOL_GROUP_CALENDAR) {
      return '查询与管理日程';
    }
    // 剪贴板：写入剪贴板单件——零权限、默认关
    if (title === TOOL_GROUP_CLIPBOARD) {
      return '让助手写入剪贴板';
    }
    // 图表：chart_display 单件——把数据画成图表显示在对话里
    if (title === TOOL_GROUP_CHART) {
      return '把数据画成图表';
    }
    // 联网：http_request 已移出单列 HTTP 请求卡
    if (title === TOOL_GROUP_WEB) {
      return '搜索网络，读取网页';
    }
    // 浏览器控制：打开/浏览/操作网页三件，与联网搜索各自独立开关
    if (title === TOOL_GROUP_BROWSE) {
      return '打开、浏览与操作网页';
    }
    // HTTP 请求：与联网搜索各自独立开关，不随其可用性
    if (title === TOOL_GROUP_HTTP) {
      return '调用接口，发送网络请求';
    }
    // 文件工作区：助手读写工作区文件三件
    if (title === TOOL_GROUP_WORKSPACE) {
      return '助手保存与你上传的文件';
    }
    // 文件夹挂载：六件——系统选择器授权的本机文件夹，写入与删除走确认链
    if (title === TOOL_GROUP_MOUNT) {
      return '读取、写入与删除本机文件夹';
    }
    // 脚本工作台：三件脚本族自文件工作区卡拆出
    if (title === TOOL_GROUP_CODE) {
      return '编写并运行脚本';
    }
    // Python 运行：内嵌 CPython 执行域（拍板「独立卡、默认关、紧邻脚本工作台、互不联动」
    // ——归并形态下即本行独立开关，与脚本工作台行开关互不牵连；副标题 ≤14 字防组卡行溢出）
    if (title === TOOL_GROUP_PYTHON) {
      return '运行 Python 分析数据';
    }
    // Node 运行：内嵌 Node.js 执行域（门 2；拍板「独立卡、默认关、紧随 Python 运行、
    // 三张执行卡互不联动」——归并形态下即本行独立开关；副标题 ≤14 字防组卡行溢出）
    if (title === TOOL_GROUP_NODE) {
      return '真实运行 Node 代码';
    }
    // 记忆：检索记忆 + 管理长期记忆两件都在本卡
    if (title === TOOL_GROUP_MEMORY) {
      return '查看与整理长期记忆';
    }
    // 知识库：检索知识库 + 管理知识库两件都在本卡
    if (title === TOOL_GROUP_KNOWLEDGE) {
      return '查看与整理知识库条目';
    }
    // 本地检索：search_knowledge 已移出成卡，只剩帮助与历史会话
    if (title === TOOL_GROUP_LOCAL) {
      return '检索帮助与历史会话';
    }
    if (title === TOOL_GROUP_SKILL) {
      return '会话中查看与创建技能';
    }
    if (title === TOOL_GROUP_APP) {
      return '管理应用设置、提示词与数据';
    }
    return '';
  }

  // 卡图标（24vp 系统符号）：注册表不带 UI 资源，映射单源在此——符号名全部沿用已核验已
  // 编译名（本 SDK 有 bubble_left 不存在的先例，弃用未验名）
  private cardIcon(title: string): Resource {
    if (title === TOOL_GROUP_BASIC) {
      return $r('sys.symbol.message');
    }
    // 位置：pin（SDK 表无裸 location 名，取定位针）
    if (title === TOOL_GROUP_LOCATION) {
      return $r('sys.symbol.pin');
    }
    // 日程：calendar（符号表在册名，坑72）
    if (title === TOOL_GROUP_CALENDAR) {
      return $r('sys.symbol.calendar');
    }
    // 剪贴板：text_clipboard（符号表在册名，坑72）
    if (title === TOOL_GROUP_CLIPBOARD) {
      return $r('sys.symbol.text_clipboard');
    }
    // 图表：histogram（符号表在册名，坑72）
    if (title === TOOL_GROUP_CHART) {
      return $r('sys.symbol.histogram');
    }
    if (title === TOOL_GROUP_WEB) {
      return $r('sys.symbol.magnifyingglass');
    }
    // 浏览器控制：website（SDK 表无裸 globe 名，取网页件）
    if (title === TOOL_GROUP_BROWSE) {
      return $r('sys.symbol.website');
    }
    // HTTP 请求：link（已核验，项目内既有用例）
    if (title === TOOL_GROUP_HTTP) {
      return $r('sys.symbol.link');
    }
    // 文件工作区：folder（项目内既有用例，坑72）
    if (title === TOOL_GROUP_WORKSPACE) {
      return $r('sys.symbol.folder');
    }
    // 文件夹挂载：externaldrive（设置页「文件夹挂载」行同图标同源，坑72）
    if (title === TOOL_GROUP_MOUNT) {
      return $r('sys.symbol.externaldrive');
    }
    // 脚本工作台：code（符号表在册名，坑72）
    if (title === TOOL_GROUP_CODE) {
      return $r('sys.symbol.code');
    }
    // Python 运行：doc_plaintext（本工程文档解析面在用的已核验名，坑72——未验名不引）
    if (title === TOOL_GROUP_PYTHON) {
      return $r('sys.symbol.doc_plaintext');
    }
    // Node 运行：code（任务书 §3.4 点名「已核验的 sys.symbol.code 或工程既有符号」；
    // 与脚本工作台同符号属有意复用——Node 与 JS 脚本同属代码执行语义，未验名不引）
    if (title === TOOL_GROUP_NODE) {
      return $r('sys.symbol.code');
    }
    // 记忆：memory_module / 知识库：bookshelf（均为他页在用的已核验名）
    if (title === TOOL_GROUP_MEMORY) {
      return $r('sys.symbol.memory_module');
    }
    if (title === TOOL_GROUP_KNOWLEDGE) {
      return $r('sys.symbol.bookshelf');
    }
    if (title === TOOL_GROUP_LOCAL) {
      return $r('sys.symbol.book');
    }
    if (title === TOOL_GROUP_SKILL) {
      return $r('sys.symbol.wand_and_stars');
    }
    if (title === TOOL_GROUP_APP) {
      return $r('sys.symbol.gearshape');
    }
    // 未来未知组兜底（不空白）
    return $r('sys.symbol.wrench_and_screwdriver');
  }

  // 组卡图标底色（★ 入参 = 卡名——归并表首组 title / 兜底卡名，同卡所有行共用返回值——按
  // group.title 逐行取色会让一张卡内多色；原单组卡自身 title 入参形态已随归并笔退役）。
  // 色相语义照旧：连接类蓝 / 交互操作类橙 / 数据与记忆类绿 / 内容与模型类紫 / 位置提醒橙 /
  // 未知组灰
  private cardIconBg(title: string): string {
    if (title === TOOL_GROUP_BASIC || title === TOOL_GROUP_WEB || title === TOOL_GROUP_MOUNT) {
      return SETTING_ICON_BLUE;
    }
    if (title === TOOL_GROUP_LOCATION) {
      return SETTING_ICON_ORANGE;
    }
    if (title === TOOL_GROUP_CALENDAR || title === TOOL_GROUP_BROWSE ||
      title === TOOL_GROUP_LOCAL || title === TOOL_GROUP_SKILL) {
      return SETTING_ICON_PURPLE;
    }
    if (title === TOOL_GROUP_CLIPBOARD || title === TOOL_GROUP_CODE ||
      title === TOOL_GROUP_MEMORY) {
      return SETTING_ICON_GREEN;
    }
    if (title === TOOL_GROUP_HTTP || title === TOOL_GROUP_WORKSPACE ||
      title === TOOL_GROUP_KNOWLEDGE) {
      return SETTING_ICON_ORANGE;
    }
    return SETTING_ICON_GRAY;
  }

  //（原 cardItems 单卡单行方法已随组卡归并删除——行数据改由 bundleItems 按卡整批产出）
  // 卡开关 = 用户唯一控制面：批量设置整卡启用态——逐个走 canEnable 判定（拦截单源，被挡
  // 成员保持原状并 toast）；落库一次（成员原序保留，卡内按组序追加；集合未变跳过——空转
  // 守卫）。关闭方向零拦截（无锁定件）。★ 批路径按批后目标态求值：「联网搜索」与联网域
  // 从属件同卡同批，按当前集合判会「点全开却少开」。两段式：第一段摘出联网域从属件并齐
  // 其余可开成员，第二段按批后目标集合 next 逐个复核（遍历按 isWebDomainTool 名单自动收窄
  //——从属件现 = scrape_web 一件，判据同 isToolSuppressed）。关闭分支不涉压制（用户主动
  // 关闭 = 合法落库，「不改写存储」只约束压制导致的显示态）
  private toggleGroup(group: ToolGroup, on: boolean): void {
    this.toggleEpoch += 1; // 卡重建纪元自增（开关显示态随批量同步刷新，见字段注释）
    const memberNames: string[] = group.members.map((m: ToolEntry): string => m.name);
    const next: string[] = this.enabledIds
      .filter((id: string): boolean => !memberNames.includes(id));
    let suppressReason: string = '';
    const suppressed: ToolEntry[] = group.members.filter((m: ToolEntry): boolean =>
      isWebDomainTool(m.name) && m.name !== TOOL_SEARCH_WEB);
    for (const member of group.members) {
      if (on) {
        if (isWebDomainTool(member.name) && member.name !== TOOL_SEARCH_WEB) {
          continue; // 第二段按批后目标集合复核（批量开时与联网搜索同批，见方法头注释）
        }
        if (!this.canEnable(member.name, next)) {
          continue;
        }
        next.push(member.name);
      }
    }
    if (on) {
      for (const member of suppressed) {
        if (!this.canEnable(member.name, next)) {
          suppressReason = this.enableBlockReason(member.name, next);
        } else {
          next.push(member.name);
        }
      }
    }
    if (suppressReason !== '') {
      // 压制挡下的分因文案（助手未开联网搜索）
      this.getUIContext().getPromptAction().showToast({ message: suppressReason });
    }
    const unchanged: boolean = this.isSameSet(next, this.enabledIds);
    this.enabledIds = next;
    if (unchanged) {
      return;
    }
    updateAssistantTools(this.rowId, serializeEnabledToolIds(next))
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // ──（脚本联网域名授权卡整簇已撤——域名管理迁设置侧总览/管理两页 + 编辑页入口卡，见文件头）──

  // ──（MCP 服务器绑定卡整簇已迁出为独立三级页 AssistantMcpPage——编辑页连接组卡「MCP」
  // 行 push，方法体原样搬迁；本页零残留，见文件头）──

  @Builder
  Content() {
    Scroll() {
      // 板块间 SECTION_GAP、板块头与组卡 SECTION_HEADER_GAP（Theme 三档常量）
      Column({ space: SECTION_GAP }) {
        // 页顶说明（InfoCard 单源件）：整组批量语义一条非显然信息
        InfoCard({ text: '工具按用途分组，每组一枚开关，一键全开或全关整组，不能单独控制某一件。' })
        // 组卡：页序由 cardBundles 单一产出——空组卡不渲染、未归组落兜底卡；每卡内一行 =
        // 一个功能组，行尾 Toggle 即该组的唯一控制面，无展开机制
        ForEach(this.cardBundles(), (bundle: ToolCardBundle) => {
          // 卡外标题：四张组卡全渲染 SectionHeader（无副标题；原单组卡免标题分支已随
          // 归并笔退役）
          Column({ space: SECTION_HEADER_GAP }) {
            SectionHeader({ title: bundle.sectionTitle })
            GroupSettingCard({ items: this.bundleItems(bundle), dividerLeft: DIVIDER_LEFT_ICON_LARGE })
          }
          .width('100%')
        }, (bundle: ToolCardBundle): string =>
          // 键含开关纪元（坑44/80 家族）：卡 items 为普通成员入参，键变才整卡重建（库读回/
          // 组开关交互）；键首段含组数（同一张组卡成员变动也须重建——组名不再是卡标题）
          bundle.title + '|' + bundle.groups.length + '|' + this.toggleEpoch)
        //（MCP 服务器绑定卡已迁出为独立三级页 AssistantMcpPage——见文件头）
        //（页尾「脚本联网域名」授权卡已撤——见文件头）
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  build() {
    PageShell({
      title: '工具调用',
      // 右上角无菜单键（纯开关列表页）
      onBackPressed: (): boolean => {
        // 开关行即时落库（本页无待保存项），完成返回带 result（坑17 姿势——编辑页 onPop
        // 刷「工具调用」卡面摘要）
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

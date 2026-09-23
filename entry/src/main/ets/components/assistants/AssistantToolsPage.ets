// 助手工具页签三级页（2026-09-02 工具调用底层一期）：编辑页「工具调用」分区卡 push，
// param = 助手 id。页面形态（★ 2026-09-18 分类卡重组，决明「工具太多独占通用混杂——
// 类似工具合为一个卡，只保留一个新的主副标题，不要留下多项」）：分组视图 =
// ToolTypes.visibleToolGroups() 功能卡轴八卡（基础能力 / 联网搜索 / HTTP 请求 / 记忆 /
// 知识库 / 本地检索 / 技能管理 / 应用管理——★ 2026-09-21 剥离笔自「本地检索」卡拆出
// 「记忆」「知识库」两卡），每卡一张 GroupSettingCard 单行开关卡（图标 +
// 卡名 + 副标题 + Toggle），一卡一枚开关 = 整卡工具批量进出启用清单；成员明细行 /
// 组头计数 / 展开折叠机制整体退役（演进：09-08 域分组组头 + 折叠展开 → 09-13 语义
// 合并两枚组开关 + 只读成员行 → 09-18 分类卡重组 → 本笔八卡，各笔细节见变更记录对应节）。
// ★ 2026-09-18 卡口径统一（七百三十二节）：卡显示态判定上迁 ToolTypes 单源——可见卡
//（visibleToolGroups）/ 卡内可开件分母（enablableToolMembers）/ 整卡开关（toolGroupAllOn）
// 三件由本页与助手编辑页「工具调用」卡面摘要（改报「已开卡数/卡总数」）共用，原页内
// 三方法退化为薄委托，禁两处各写一套放行逻辑。
// 开关切换即时落库（模型绑定同款口径「选择即落库不经保存键」），assistants.tools 列
//（DB v14）存启用 id 清单 JSON 串（'' = 默认集合）。
// 发送链 = ChatPromptState.load 同链解析 → ChatSendCtrl.defsFor 查声明（细则见 ToolTypes
// 头注释）——★ 底层链路零改动：本页只改分组呈现，逐件存取与逐件声明原样（当初拆成
// 多件正是为让模型按清晰的单件契约取名传参，防能力混淆，故注册表与声明面不动）。
// ★ 2026-09-05 控制台助手锁定：search_help 不可关（isConsoleLocked 拦截 + toast——核心
// 能力立身项；updateAssistantTools 的 UI 调用点唯一在本页，另一调用在 AssistantDb 存量
// 迁移为内部受控非用户路径——UI 守卫即唯一闸门；DB 外改致关闭态时点开可自愈）。
// ★ console-exclusive 工具族反向拦截（2026-09-05 立判定，2026-09-18 随分类卡收口）：
// 独占件全收「应用管理」卡（★ 2026-09-21 剥离笔后为九件——manage_memory 移出，记忆卡归
// 普通助手可开）——普通助手该卡可开件 0 → 副标题报受限 + 开关点击走
// toggleGroup 汇总拦截 toast；判定单源 enableBlockReason / canEnable（seed 层在
// AssistantDb），批量路径禁另写一套放行逻辑（规范 §4.2）。
// ★ 2026-09-11 联网域从属件单向绑定（B 案，scrape_web / browse_open / browse_read 三件
// 从属 search_web 本体）：从属件不进卡开关分母（groupEnablableMembers 可开件口径），
// 批量开时两段式按批后目标集合求值防「全开误挡」；显示压制不改写 enabledIds（放开
// 闸门回到用户原态）。总开关关闭时联网卡副标题改报总开关拦截（卡级标注，@StorageProp
// 自订阅随改随刷）。
// ★ 2026-09-13 记忆按需读取：isModeDriven 工具（search_memory / use_skill）不进本页
//——声明由模式开关驱动（ChatSendCtrl 追加），过滤落点 = ToolTypes.visibleToolGroups
//（成员与卡两级同做，卡开关批量同样吃过滤后成员——模式件不进 enabledIds）。
// ★ 2026-09-09 工具调用轮数上限（0 = 不限制〔由 ToolLimits 256 硬顶兜底〕/ 1~32 整数；
// 默认 32 = 旧全局常量同值零回归），assistants.toolStepLimit 列（DB v22）；★ 2026-09-10
// 搜索结果条数（助手级 1~25、默认 5），assistants.searchResultCount 列（DB v25）。两卡
// = 共用 SliderValueCard 同形制；保存模式 = 拖动/输入只改内存态，返回时统一落库一次
//（开关行仍即时落库，并存不冲突）；落库失败 toast 留页不静默。
// 刷新链：无保存动作 → onBackPressed pop({saved:true})（坑17「无保存动作的完成返回」
// 姿势）刷编辑页卡面摘要；开关落库失败 toast 不静默（开关状态回滚由 onPop 重拉兜底）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_ASSISTANT_TOOLS_PAGE } from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardDescColor } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';
import { InputDialog } from '../chat/InputDialog';
import { SliderValueCard } from '../SliderValueCard';
import { TOOL_STEP_HARD_CAP, TOOL_STEP_LIMIT_DEFAULT, TOOL_STEP_LIMIT_MAX }
  from '../../common/providers/ToolLimits';
import { SEARCH_RESULT_COUNT_DEFAULT, SEARCH_RESULT_COUNT_MAX, SEARCH_RESULT_COUNT_MIN,
  resolveSearchResultCount } from '../../common/search/SearchLimits';
import { ToolEntry, ToolGroup, enablableToolMembers, isConsoleExclusive, isToolSuppressedInList,
  isWebDomainTool, parseEnabledToolIds,
  serializeEnabledToolIds, TOOL_GROUP_APP, TOOL_GROUP_BASIC, TOOL_GROUP_HTTP,
  TOOL_GROUP_KNOWLEDGE, TOOL_GROUP_LOCAL, TOOL_GROUP_MEMORY, TOOL_GROUP_SKILL, TOOL_GROUP_WEB,
  TOOL_SEARCH_HELP, TOOL_SEARCH_WEB, toolGroupAllOn, toolTitle,
  visibleToolGroups } from '../../common/providers/ToolTypes';
import { ASSISTANT_CONSOLE_ID, queryAssistant, updateAssistantSearchResultCount,
  updateAssistantToolStepLimit, updateAssistantTools } from '../../common/store/AssistantDb';
import { PREF_SEARCH_SERVICE_ENABLED_KEY } from '../../common/AppPreferences';

@Component
export struct AssistantToolsPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 编辑对象行 id（push param = 助手 id）
  private rowId: string = '';
  // 卡视图（aboutToAppear 一次性读取——注册表进程级不变，无需刷新链）
  private groups: ToolGroup[] = [];
  // 启用集合（卡开关显示态单一真源；@State 驱动重建）
  @State enabledIds: string[] = [];
  // 卡重建纪元（2026-09-08 真机报障修复沿用）：GroupSettingCard.items 是普通成员入参，
  // 父组件重渲不更新它 → 行定格首帧。本纪元进卡 ForEach 键（键变重建 = 规范 §3 主通道）：
  // 库读回、卡开关批量交互都自增 → 组卡整体重建 → 行内容拉新值
  @State toggleEpoch: number = 0;
  // 工具调用轮数上限（2026-09-09；0 = 不限制，语义/换算见 ToolLimits）：拖动与输入只改本
  // 状态，返回时统一落库一次；initial 供无改动判定
  @State private toolStepLimit: number = TOOL_STEP_LIMIT_DEFAULT;
  private initialToolStepLimit: number = TOOL_STEP_LIMIT_DEFAULT;
  // 搜索结果条数（2026-09-10 搜索条数助手级可调；值域 1~25，语义/换算见 SearchLimits）：
  // 保存模式同上限卡；initial 供无改动判定
  @State private searchCount: number = SEARCH_RESULT_COUNT_DEFAULT;
  private initialSearchCount: number = SEARCH_RESULT_COUNT_DEFAULT;
  // 上限编辑键弹窗控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private limitEditCtrl: CustomDialogController | null = null;
  // 搜索条数编辑键弹窗控制器（同上，坑7）
  private searchCountEditCtrl: CustomDialogController | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 联网搜索总开关（2026-09-11 单向绑定）：联网卡压制标注消费它；@StorageProp
  // 自订阅 ⇒ 工具页存活期间在设置页改总开关、回来即刷新（appColorMode 同款姿势）
  @StorageProp(PREF_SEARCH_SERVICE_ENABLED_KEY) searchServiceEnabled: boolean = true;

  // 卡视图（aboutToAppear 一次性读取）。★ 2026-09-13 记忆按需读取：模式驱动件
  //（search_memory / use_skill）自视图过滤不出页——声明由模式开关驱动，页上再放开关即
  //「模式开关 × 工具页开关」双重控制打架。★ 2026-09-18 卡口径统一：过滤与卡显示态判定
  // 上迁 ToolTypes（visibleToolGroups / toolGroupAllOn），本页与助手编辑页卡面摘要同源
  //（原页内 loadVisibleGroups/groupEnablableMembers/groupAllOn 三方法已改为薄委托）

  aboutToAppear(): void {
    this.groups = visibleToolGroups();
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_TOOLS_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    queryAssistant(param)
      .then((row): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.enabledIds = parseEnabledToolIds(row.tools);
        this.toggleEpoch += 1;
        this.toolStepLimit = row.toolStepLimit;
        this.initialToolStepLimit = row.toolStepLimit;
        // 条数先过换算再上滑轨（脏数据 0/超界/小数回默认或收口——滑块值域 1~25 恒合法；
        // 未改动则回写零次，库内脏值仍由消费侧同函数换算，两侧同源）
        this.searchCount = resolveSearchResultCount(row.searchResultCount);
        this.initialSearchCount = this.searchCount;
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 控制台助手核心工具锁定判定（2026-09-05 决明拍板：帮助中心检索是控制台助手的立身
  // 能力，页内不可关——尝试关拦截回弹 + toast；其余工具照常可开关，其他助手不受限）
  private isConsoleLocked(name: string): boolean {
    return this.rowId === ASSISTANT_CONSOLE_ID && name === TOOL_SEARCH_HELP;
  }

  // 「读取网页」等联网域从属件压制判定（2026-09-11 单向绑定 B 案；内置浏览器 P1 起为
  // 从属三件——scrape_web / browse_open / browse_read）：归属助手启用清单不含
  // 「联网搜索」（能力上限未给）或联网搜索总开关关闭时整体不可用（从属三件不进
  // isWebDomainTool 就是 search_web 本体——域主件不做自压制，判据单源 ToolTypes）。
  // ★ 只影响显示态与开启拦截，enabledIds 与 DB 的 assistants.tools 一个字不动（显示压制
  // 不改写存储）——放开闸门后回到用户原来的状态；批路径吃候选集合形参（缺省 = 当前集合）：
  // 卡批量开时「联网搜索」与从属件同卡同批，按批后目标集合判定才不误挡
  private isToolSuppressed(name: string, candidateIds: string[] = this.enabledIds): boolean {
    return isToolSuppressedInList(name, candidateIds, this.searchServiceEnabled);
  }

  // 开启/关闭判定——卡批量开/关的双判定**单一来源**（规范 §4.2：禁另写一套放行逻辑，
  // 两处各写一套 = 漂移源）。开启的原因判定收敛 enableBlockReason（console-exclusive +
  // 读取网页压制两因，被拦原因文案也由它单源产出——toast 禁另写裸条件）；canEnable 吃
  // 候选集合形参（缺省 = 当前集合），卡批量传批后目标集合，显示态分母求值传当前集合
  private enableBlockReason(name: string, candidateIds: string[]): string {
    if (isConsoleExclusive(name) && this.rowId !== ASSISTANT_CONSOLE_ID) {
      return '「' + toolTitle(name) + '」仅控制台助手可用';
    }
    if (!this.isToolSuppressed(name, candidateIds)) {
      return '';
    }
    return this.searchServiceEnabled ?
      '「' + toolTitle(name) + '」依赖「联网搜索」，请先开启「联网搜索」' :
      '联网搜索总开关已关闭，' + toolTitle(name) + '也无法使用，可在设置的联网搜索页打开';
  }

  private canEnable(name: string, candidateIds: string[] = this.enabledIds): boolean {
    return this.enableBlockReason(name, candidateIds) === '';
  }

  private canDisable(name: string): boolean {
    return !this.isConsoleLocked(name);
  }

  // 集合等价（空转守卫用）：卡批量目标集合与当前集合一致时跳过落库（如整卡被闸全挡——
  // 无成员可动，白写一次库）
  private isSameSet(a: string[], b: string[]): boolean {
    return a.length === b.length && a.every((id: string): boolean => b.includes(id));
  }

  // 卡内可开件（卡开关显示态与受限标注的分母）：该助手当前可启用的成员。判定上迁
  // ToolTypes.enablableToolMembers（console-exclusive 与被压制的联网从属件不进分母——
  // 若进，普通助手联网卡永不全开，开关点开后仍显示关〔用户困惑源〕）；求值传当前集合
  //（压制判定依赖候选集合含联网搜索）
  private groupEnablableMembers(group: ToolGroup): ToolEntry[] {
    return enablableToolMembers(group, this.enabledIds,
      this.rowId === ASSISTANT_CONSOLE_ID, this.searchServiceEnabled);
  }

  // 卡开关显示态 = 可开件全开（可开件 0 = 恒关——普通助手的应用管理整卡不可开；判定上迁
  // ToolTypes.toolGroupAllOn，与助手编辑页卡面摘要计数同源）
  private groupAllOn(group: ToolGroup): boolean {
    return toolGroupAllOn(group, this.enabledIds, this.rowId === ASSISTANT_CONSOLE_ID,
      this.searchServiceEnabled);
  }

  // 卡内联网域从属件在场判定（压制标注只对含从属件的卡有意义——现役唯联网卡；
  // 判据与 toggleGroup 批路径同源 isWebDomainTool 且非 search_web 本体）
  private groupHasSuppressed(group: ToolGroup): boolean {
    return group.members.some((m: ToolEntry): boolean =>
      isWebDomainTool(m.name) && m.name !== TOOL_SEARCH_WEB);
  }

  // 卡副标题显示态（分类卡重组笔——「只保留一个新的主副标题」的副行）：①可开件 0 =
  // 整卡受限（应用管理卡对普通助手——副标题报受限，开关恒关，点击走 toggleGroup 汇总
  // toast）；②含联网从属件且总开关关闭 = 报总开关拦截（压制不改写存储，卡显示态仍按
  // 清单求值——放开闸门即恢复）；③正常报 cardDescOf 功能描述
  private cardSecondary(group: ToolGroup): string {
    if (this.groupEnablableMembers(group).length === 0) {
      return '仅控制台助手可用';
    }
    if (this.groupHasSuppressed(group) && !this.searchServiceEnabled) {
      return '联网搜索总开关已关闭';
    }
    return this.cardDescOf(group.title);
  }

  // 卡副标题功能描述（新主副标题的副行：描述该卡能力，不逐件枚举；受「面向用户文案
  // 写作规约」约束；单行 ≤14 字防组卡行 64vp 固定行高溢出）
  private cardDescOf(title: string): string {
    if (title === TOOL_GROUP_BASIC) {
      return '获取时间，需要时向你提问';
    }
    // 2026-09-20 HTTP 请求独立域笔：联网卡副标题回收「调用接口」——http_request 已移出本卡
    // 单列 HTTP 请求卡（副标题仍 ≤14 字）
    if (title === TOOL_GROUP_WEB) {
      return '搜索网络，读取网页';
    }
    // HTTP 请求卡（2026-09-20 独立域笔新立）：与联网搜索各自独立开关，不随其可用性
    if (title === TOOL_GROUP_HTTP) {
      return '调用接口，发送网络请求';
    }
    // 记忆卡（2026-09-21 剥离笔新立）：卡内两件（检索记忆 + 管理长期记忆）都在本卡
    if (title === TOOL_GROUP_MEMORY) {
      return '查看与整理长期记忆';
    }
    // 知识库卡（2026-09-21 剥离笔新立）：卡内两件（检索知识库 + 管理知识库）都在本卡
    //（2026-09-21 知识库第二笔下本加写工具后才写「整理」——上本只有检索件，措辞照实）
    if (title === TOOL_GROUP_KNOWLEDGE) {
      return '查看与整理知识库条目';
    }
    // 2026-09-21 剥离笔：本地检索卡副标题回收「知识库」——search_knowledge 已移出成卡
    //（2026-09-21 世界书知识库首版原句「检索帮助、会话与知识库」随之失效）；仍 ≤14 字
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

  // 卡图标（24vp 系统符号）：注册表不带 UI 资源，映射单源在此——符号名全部沿用原成员行
  // 图标的已核验已编译名（bubble_left 在本 SDK 编译期资源表不存在，弃用）
  private cardIcon(title: string): Resource {
    if (title === TOOL_GROUP_BASIC) {
      return $r('sys.symbol.message');
    }
    if (title === TOOL_GROUP_WEB) {
      return $r('sys.symbol.magnifyingglass');
    }
    // HTTP 请求卡图标（2026-09-20 独立域笔新立；link = 已核验系统符号名，项目内既有用例）
    if (title === TOOL_GROUP_HTTP) {
      return $r('sys.symbol.link');
    }
    // 记忆卡图标（2026-09-21 剥离笔新立；memory_module = 助手记忆页「沉淀记忆」行在用的
    // 已核验名）、知识库卡图标（同笔；bookshelf = 助手知识库页「管理知识库」行在用的已核验名）
    // ——两符号名均非自创（本 SDK 有 bubble_left 不存在的先例）
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

  // 卡数据源（单行开关卡 = GroupSettingCard 开关行形态：Toggle 可点自切换 = 唯一控制面，
  // 行不可点——规范 §4.1 统一形态；items 走方法返回类型化数组，ArkTS 禁 build 内对象
  // 字面量数组）
  private cardItems(group: ToolGroup): GroupEntryItem[] {
    const rows: GroupEntryItem[] = [{
      icon: this.cardIcon(group.title),
      label: group.title,
      secondary: this.cardSecondary(group),
      toggleValue: (): boolean => this.groupAllOn(group),
      onToggle: (isOn: boolean): void => this.toggleGroup(group, isOn)
    }];
    return rows;
  }

  // 卡开关 = 用户唯一控制面（分类卡重组笔）：批量设置整卡启用态——逐个走 canEnable/
  // canDisable 判定（两道闸单一来源），被挡成员保持原状并汇总 toast；落库一次（卡外
  // 成员原序保留，卡内按组序追加；集合未变则跳过落库——空转守卫）。
  // ★ 2026-09-11 批路径按批后目标态求值：「联网搜索」与联网域从属件同卡且同批，若按
  // 当前集合判，批量开时「联网搜索」还没进集合 → 从属件被判被压制 → 点「全开」却少开。
  // 两段式：第一段摘出联网域从属件并齐其余可开成员，第二段按批后目标集合 next 逐个复核
  //（★ 内置浏览器 P1：单件扩为从属三件遍历，判据同 isToolSuppressed——isWebDomainTool
  // 且非 search_web 本体）。
  // 关闭分支不涉压制（用户主动关闭 = 合法落库，「不改写存储」只约束压制导致的显示态）
  private toggleGroup(group: ToolGroup, on: boolean): void {
    this.toggleEpoch += 1; // 卡重建纪元自增（开关显示态随批量同步刷新，见字段注释）
    const memberNames: string[] = group.members.map((m: ToolEntry): string => m.name);
    const next: string[] = this.enabledIds
      .filter((id: string): boolean => !memberNames.includes(id));
    let blocked: number = 0;
    let locked: number = 0;
    let suppressReason: string = '';
    const suppressed: ToolEntry[] = group.members.filter((m: ToolEntry): boolean =>
      isWebDomainTool(m.name) && m.name !== TOOL_SEARCH_WEB);
    for (const member of group.members) {
      if (on) {
        if (isWebDomainTool(member.name) && member.name !== TOOL_SEARCH_WEB) {
          continue; // 第二段按批后目标集合复核（批量开时与联网搜索同批，见方法头注释）
        }
        if (!this.canEnable(member.name, next)) {
          blocked++;
          continue;
        }
        next.push(member.name);
      } else if (!this.canDisable(member.name)) {
        locked++;
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
    if (blocked > 0) {
      this.getUIContext().getPromptAction().showToast({ message: '卡内 ' + blocked + ' 个工具仅控制台助手可用' });
    }
    if (suppressReason !== '') {
      // 压制挡下的分因文案（总开关关 / 助手未开联网搜索），独立于 console-exclusive 汇总
      this.getUIContext().getPromptAction().showToast({ message: suppressReason });
    }
    if (locked > 0) {
      this.getUIContext().getPromptAction().showToast({ message: '帮助中心检索是控制台助手的核心能力，不可关闭' });
    }
    const unchanged: boolean = this.isSameSet(next, this.enabledIds);
    this.enabledIds = next;
    if (unchanged) {
      return;
    }
    updateAssistantTools(this.rowId, serializeEnabledToolIds(next))
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  // 上限手动输入解析（整数 + 范围校验；非法 toast 不静默）；合法则更新 @State（滑块联动）
  private applyLimitInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() || v < 0 || v > TOOL_STEP_LIMIT_MAX) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 0~' + TOOL_STEP_LIMIT_MAX + ' 的整数' });
      return;
    }
    this.toolStepLimit = v;
  }

  // 上限编辑键弹窗（InputDialog 数字型——上下文与输出页两卡同款形制；初值预填当前值）
  private openLimitEdit(): void {
    this.limitEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '工具调用轮数上限',
        initialText: String(this.toolStepLimit),
        placeholder: '0~' + TOOL_STEP_LIMIT_MAX + '，0 为不限制',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applyLimitInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.limitEditCtrl.open();
  }

  // 搜索条数手动输入解析（整数 + 范围校验；非法 toast 不静默）；合法则更新 @State（滑块联动）
  private applySearchCountInput(text: string): void {
    const v: number = parseInt(text, 10);
    if (!Number.isFinite(v) || String(v) !== text.trim() ||
      v < SEARCH_RESULT_COUNT_MIN || v > SEARCH_RESULT_COUNT_MAX) {
      this.getUIContext().getPromptAction().showToast({
        message: '请输入 ' + SEARCH_RESULT_COUNT_MIN + '~' + SEARCH_RESULT_COUNT_MAX + ' 的整数'
      });
      return;
    }
    this.searchCount = v;
  }

  // 搜索条数编辑键弹窗（InputDialog 数字型——上限卡同款形制；初值预填当前值）
  private openSearchCountEdit(): void {
    this.searchCountEditCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '搜索结果条数',
        initialText: String(this.searchCount),
        placeholder: SEARCH_RESULT_COUNT_MIN + '~' + SEARCH_RESULT_COUNT_MAX + ' 的整数',
        confirmLabel: '确认',
        number: true,
        onConfirm: (text: string): void => {
          this.applySearchCountInput(text);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.searchCountEditCtrl.open();
  }

  // 返回时统一落库（两卡共用；只写有改动的列，失败以 reject 上抛——调用方 toast 留页不静默）
  private saveChangedSettings(limitChanged: boolean, countChanged: boolean): Promise<void> {
    let chain: Promise<void> = Promise.resolve();
    if (limitChanged) {
      chain = chain.then((): Promise<void> =>
        updateAssistantToolStepLimit(this.rowId, this.toolStepLimit));
    }
    if (countChanged) {
      chain = chain.then((): Promise<void> =>
        updateAssistantSearchResultCount(this.rowId, this.searchCount));
    }
    return chain;
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        Text('工具按用途分卡，每卡一枚开关，开启后该卡全部工具对助手开放，关闭即整卡停用，不能单独控制某一件。仅控制台助手可用的卡会标注。模型在对话中按需调用，结果自动回传继续生成')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
        // 上限滑轨卡（2026-09-09 首卡；卡体 = 共用 SliderValueCard，与上下文与输出页两卡
        // 同形制——可滑可输入，返回时落库）
        SliderValueCard({
          title: '工具调用轮数上限', value: $toolStepLimit,
          min: 0, max: TOOL_STEP_LIMIT_MAX, step: 1,
          format: (v: number): string => v === 0 ? '不限制' : v + ' 轮',
          desc: '限制一次提问中模型调用工具的最大轮数，0 为不限制，由内置 ' + TOOL_STEP_HARD_CAP + ' 轮硬顶兜底',
          onEdit: (): void => { this.openLimitEdit(); }
        })
        // 搜索结果条数滑轨卡（2026-09-10 搜索条数助手级可调；卡体同上限卡）：值域 1~25、
        // 默认 5 = 旧行为零回归；消费 = 联网搜索请求体条数字段与解析上限同源。本卡只对
        // 已开启「联网搜索」工具的助手有意义，未开启时值照常可调但不产生效果（不额外加
        // 显隐守卫——config 与能力上限分离，避免界面随开关跳变）
        SliderValueCard({
          title: '搜索结果条数', value: $searchCount,
          min: SEARCH_RESULT_COUNT_MIN, max: SEARCH_RESULT_COUNT_MAX, step: 1,
          format: (v: number): string => v + ' 条',
          desc: '联网搜索单次返回的结果条数。返回的条目会作为引文进入对话上下文，条数越多消耗越多。免配置的 Bing 由结果页决定条数，通常十条上下',
          onEdit: (): void => { this.openSearchCountEdit(); }
        })
        // 分类卡（2026-09-18 重组：每卡恒一张 GroupSettingCard 单行开关卡，无展开机制——
        // 卡副标题即全貌，成员明细不再展示）
        ForEach(this.groups, (group: ToolGroup) => {
          GroupSettingCard({ items: this.cardItems(group) })
        }, (group: ToolGroup): string =>
          // 键含开关纪元 + 联网总开关（2026-09-08 真机报障修复沿用）：卡 items 为普通成员
          // 入参，父组件重渲不更新它 → 行定格首帧；键含 toggleEpoch，库读回/卡开关交互即
          // 键变 → 卡整体重建（规范 §3「ForEach 键变重建」主通道）。再拼联网总开关——
          // 卡副标题压制标注与开关显示态（可开件分母含压制判定）随全局开关变化刷新
          //（@StorageProp 变化只重跑 build，不更新组卡普通成员入参）
          group.title + '|' + this.toggleEpoch + (this.searchServiceEnabled ? 1 : 0))
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  build() {
    PageShell({
      title: '工具调用',
      // 右上角无菜单键（纯开关列表页）
      onBackPressed: (): boolean => {
        // 两卡有改动 → 先落库再 pop（失败 toast 留页不静默，P0-1）；均无改动直接 pop。
        // 无保存动作的完成返回带 result（坑17 姿势——编辑页 onPop 刷卡面摘要）
        const limitChanged: boolean = this.toolStepLimit !== this.initialToolStepLimit;
        const countChanged: boolean = this.searchCount !== this.initialSearchCount;
        if (!limitChanged && !countChanged) {
          this.pathStack.pop({ saved: true });
          return true;
        }
        this.saveChangedSettings(limitChanged, countChanged)
          .then((): void => {
            this.pathStack.pop({ saved: true });
          })
          .catch((e: Object): void => {
            this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
          });
        return true; // 拦截返回——落库结果回调内再 pop（失败留页）
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}

// 设置页：九入口组卡（分组 = 决明拍板），组卡数据单源 = settingGroups()；卡序 = 卡1 服务商管理+功能模型 →
// 卡2 提示词+技能库+知识库 → 卡3 记忆+主动消息 → 卡4 工具调用+文件工作区+文件夹挂载 → 卡5 网络+Web 服务 →
// 卡6 偏好与外观（单行——原「偏好设置+外观显示」两行随重梳笔并一行，外观三段拆进偏好与外观页三入口行）→
// 卡7 用量统计+费用估计 → 卡8 数据与同步+存储管理 → 卡9 更多信息（恒最下），行点击
// push 同名二级页。应用内自检已全量退役（「自检」卡、检测页、域件、路由一并删除）。★ 入口迁址：联网搜索入口
// 在「工具调用」页首组卡、系统提示词入口在「会话提示词」页首卡、外观显示入口在「偏好与外观」页「外观」板块
//（三独立页整页保留，内容零改动）；新增卡/行照加卡 Checklist 八步同步。
// ★ 版块标题：九张组卡归五板块（模型接入 / 助手能力 / 工具与网络 / 偏好与用量 / 数据与更多），组卡上方加
// SectionHeader（无副标题——空副标题整行不渲染；标题 = 版块大致职能的极简概括，决明指令「不需要覆盖版块内
// 所有功能，要短」）。组卡本身零变化，settingSections() 只做归组（外层 ForEach 键 = 版块标题，静态唯一）。
// 版式照 PreferencesPage 板块头先例（间距三档走 Theme 常量：板块间 SECTION_GAP / 标题与卡 SECTION_HEADER_GAP /
// 板块内卡间 CARD_SPACING，条文 = 列表卡规范「卡片层级纵向间距」节）。
// 组卡样式 = components/GroupSettingCard.ets（官方系统设置卡真机实测规格复刻：行高 56/64vp / 24vp 符号 /
// 16vp 间距 / 14fp 副标题 / 0.5vp 分割线 / 卡圆角 CARD_RADIUS；选型理由与实测表见该组件头注释，本页不展开）。
// 副标题 = 原文案（领导指令「副标题 = 对卡功能的简介描述」，SUBTITLE_* 常量动词开头一句简介，只此一处使用、
// 不入搜索注册表）；卡片点击 recordRecentUse 记「最近使用」（搜索跳转 + 卡片点击两处记录）——九行同构，经
// openCard 收口 + settingGroups() 类型化数据（ArkTS 禁 build 内匿名对象字面量数组——10605038）。
// ★ 组卡化取代原 HdsListItemCard 单卡：组卡为官方基础组件拼装，hdsListCardAvailable /
// SettingRow 双分支与回退自制卡整体退役；行卡不挂 .width() 的 HDS 口径随之失效（组卡自持 CARD_PANEL_WIDTH）。
import { CARD_SPACING, SECTION_GAP, SECTION_HEADER_GAP } from '../../common/Theme';
import { searchBandContentTop } from '../SearchTopBand';
import { recordRecentUse, SETTING_TITLE_COST_STATS, SETTING_TITLE_DATA_SYNC, SETTING_TITLE_FUNCTIONAL_MODEL, SETTING_TITLE_KNOWLEDGE_LIBRARY, SETTING_TITLE_MORE_INFO, SETTING_TITLE_MEMORY, SETTING_TITLE_MOUNT, SETTING_TITLE_NETWORK, SETTING_TITLE_PREFERENCES, SETTING_TITLE_PROMPT, SETTING_TITLE_PROVIDER, SETTING_TITLE_PROACTIVE, SETTING_TITLE_SKILL_LIBRARY, SETTING_TITLE_STORAGE, SETTING_TITLE_TOOLS, SETTING_TITLE_USAGE_STATS, SETTING_TITLE_WEB_SERVICE, SETTING_TITLE_WORKSPACE } from '../../common/SettingSearch';
import { DIVIDER_LEFT_ICON_LARGE, GroupEntryItem, GroupSettingCard, SETTING_ICON_BLUE, SETTING_ICON_GREEN, SETTING_ICON_ORANGE, SETTING_ICON_PURPLE } from '../GroupSettingCard';
import { SectionHeader } from '../SectionHeader';

// 行卡副标题（动词开头一句简介口径，见文件头）
const SUBTITLE_PROVIDER: string = '管理 AI 服务商连接、密钥与模型';
const SUBTITLE_MORE_INFO: string = '帮助中心、运行日志与关于';
// 「会话提示词」行卡副标题（系统提示词入口就在「会话提示词」页首卡）
const SUBTITLE_PROMPT: string = '管理系统提示词与会话提示词';
// 偏好与外观副标题（原外观显示入口已并入偏好与外观页「外观」板块——副标题随之涵盖外观域）
const SUBTITLE_PREFERENCES: string = '调整输入、会话与外观的偏好';
// 数据与同步副标题（S3 已落地为页内第三分段）
const SUBTITLE_DATA_SYNC: string = '全量备份、恢复与 WebDAV、S3 同步';
// 功能模型副标题（功能级模型配置集中页，首项「默认模型」）
const SUBTITLE_FUNCTIONAL_MODEL: string = '集中设置 AI 功能默认使用的模型';
// 用量统计副标题
const SUBTITLE_USAGE_STATS: string = '查看 token 消耗与生成速度';
// 费用估计副标题（「费用花销」语意重复已回收为「费用」）
const SUBTITLE_COST_STATS: string = '估算各模型的费用';
// 记忆副标题（跨会话长期记忆管理页；卡序在提示词卡后）
const SUBTITLE_MEMORY: string = '管理跨会话的长期记忆';
// 存储管理副标题（六分类占用与可安全清理）
const SUBTITLE_STORAGE: string = '查看本机存储占用与清理';
// 工具调用副标题（二级页现为五行跳转组卡〔联网搜索/HTTP 请求/脚本工作台/Python 运行环境/MCP〕
// + 数据管理确认卡 + 轮数卡；★ 2026-11-16 随改题顺核：原注释「四行…浏览器控制」已过时——
// 浏览器控制整页 2026-11-09 退役，Python 运行环境与 MCP 两行其后新增）
const SUBTITLE_TOOLS: string = '管理内置工具的全局设置';
// 文件工作区副标题（工作区 = 工具产出文件的用户管理面，同属对话工具域）
const SUBTITLE_WORKSPACE: string = '管理助手保存和你上传的文件';
// 文件夹挂载副标题（与工作区行形成域区分——沙箱域 vs 授权外部域）
const SUBTITLE_MOUNT: string = '授权 AI 访问本机文件夹';
// 主动消息副标题（总开关 + 触发间隔的二级页入口）
const SUBTITLE_PROACTIVE: string = '管理助手主动发消息';
// 技能库副标题（技能 = 助手的「怎么做某件事」说明书，按触发描述被模型自主加载）
const SUBTITLE_SKILL_LIBRARY: string = '创建和维护助手可用的技能';
// 知识库副标题（知识库 = 用户手写的词条本，助手觉得需要某领域知识时自己去查）
const SUBTITLE_KNOWLEDGE_LIBRARY: string = '让助手按需查阅的词条本';
// 网络副标题（全局请求标识 UA 设置页入口）
const SUBTITLE_NETWORK: string = '设置应用发出请求时的身份标识';
// Web 服务副标题（卡5「网络」第二行——浏览器远程访问设置页入口）
const SUBTITLE_WEB_SERVICE: string = '开启浏览器远程访问';

// 板块标题（只此一处使用，不入搜索注册表；无副标题——SectionHeader 空副标题整行不渲染），标题 = 版块大致职能
const SECTION_TITLE_ACCESS: string = '模型接入';
// 板块2 = 卡2（提示词·技能库·知识库）+ 卡3（记忆·主动消息）——塑造助手会什么、知道什么、怎么主动找你
const SECTION_TITLE_ASSISTANT: string = '助手能力';
// 板块3 = 卡4（工具调用·文件工作区·文件夹挂载）+ 卡5（网络·Web 服务）——工具与联网出口
const SECTION_TITLE_TOOLS_NET: string = '工具与网络';
// 板块4 = 卡6（偏好与外观）+ 卡7（用量统计·费用估计）——偏好与花销账目
const SECTION_TITLE_PREFS_USAGE: string = '偏好与用量';
// 板块5 = 卡8（数据与同步·存储管理）+ 卡9（更多信息）——数据底座与杂项收口
const SECTION_TITLE_DATA_MORE: string = '数据与更多';

// 版块（只承载「归组」视图；组卡数据仍单源 settingGroups()，ArkTS 禁 build 内匿名对象字面量——10605038）
interface SettingSection {
  title: string;
  groups: GroupEntryItem[][];
}

@Component
export struct SettingsPage {
  // 顶部/底部留白（vp，导航壳下发）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 滚动联动两件（导航壳下发，2026-11-02 设置页搜索互斥切换笔）：
  // scroller = 本页 Scroll 控制器（导航壳 .bindToScrollable 绑定作官方滚动感知来源——
  // dynamicHideTitleBar 收带依赖）；onScrollOffset = 偏移上抛回调（onDidScroll 高频回调
  // 直通导航壳收带状态机，本页不落状态）
  scroller: Scroller = new Scroller();
  onScrollOffset: (yOffset: number) => void = (yOffset: number): void => {
  };
  // 行卡点击回调（导航壳执行 push 对应二级页）
  onOpenProvider: () => void = () => {
  };
  onOpenInfo: () => void = () => {
  };
  onOpenPrompts: () => void = () => {
  };
  // 偏好设置行卡点击（导航壳 push 偏好设置页——pushPreferences）
  onOpenPreferences: () => void = () => {
  };
  // 数据与同步行卡点击（导航壳 push DataSyncPage——pushDataSync）
  onOpenDataSync: () => void = () => {
  };
  // 功能模型行卡点击（导航壳 push FunctionalModelPage——pushFunctionalModel）
  onOpenFunctionalModel: () => void = () => {
  };
  // 用量统计行卡点击（导航壳 push UsageStatsPage——pushUsageStats）
  onOpenUsageStats: () => void = () => {
  };
  // 费用估计行卡点击（导航壳 push CostStatsPage——pushCostStats；与用量统计组成两行组卡）
  onOpenCostStats: () => void = () => {
  };
  // 记忆行卡点击（导航壳 push MemoryPage——pushMemory）
  onOpenMemory: () => void = () => {
  };
  // 存储管理行卡点击（导航壳 push StoragePage——pushStorage）
  onOpenStorage: () => void = () => {
  };
  // 工具调用行卡点击（导航壳 push ToolsSettingsPage——pushTools）
  onOpenTools: () => void = () => {
  };
  // 文件工作区行卡点击（导航壳 push WorkspaceManagePage——pushWorkspace）
  onOpenWorkspace: () => void = () => {
  };
  // 文件夹挂载行卡点击（导航壳 push MountManagePage——pushMount）
  onOpenMount: () => void = () => {
  };
  // 网络行卡点击（导航壳 push NetworkSettingsPage——pushNetwork）
  onOpenNetwork: () => void = () => {
  };
  // Web 服务行卡点击（导航壳 push WebServiceSettingsPage——pushWebService）
  onOpenWebService: () => void = () => {
  };
  // 主动消息行卡点击（导航壳 push ProactivePage——pushProactive）
  onOpenProactive: () => void = () => {
  };
  // 技能库行卡点击（导航壳 push SkillLibraryPage——pushSkillLibrary）
  onOpenSkillLibrary: () => void = () => {
  };
  // 知识库行卡点击（导航壳 push KnowledgeLibraryPage——pushKnowledgeLibrary）
  onOpenKnowledgeLibrary: () => void = () => {
  };
  // 行卡点击统一收口：先记「最近使用」再上抛导航壳 push
  private openCard(recordTitle: string, callback: () => void): void {
    recordRecentUse(recordTitle);
    callback();
  }

  // 组卡行数据（张数随演进，以实际返回为准；分组 = 决明拍板；单行组卡例外形态已收敛为组卡常例；类型化返回
  // ——ArkTS 禁 build 内匿名字面量数组——10605038，onClick 闭包 = 原 SettingRow 回调逐行平移，openCard 收口不变）。
  // 组内顺序 = 组卡内行序；图标符号与搜索页「最近使用」映射保持一致（勿单独改）。
  // ★ 本方法 = 组卡数据单源（渲染经 settingSections() 归组下发，组序与组内行序零变化）
  private settingGroups(): GroupEntryItem[][] {
    // ★ 组卡同色：每张卡内所有行 iconBg 同色（取卡内主色，并列取首行），跨卡保留五色分布；色板见 GroupSettingCard
    return [
      // 卡1：服务商管理 + 功能模型（两行同属「AI 服务接入」域：服务商接模型、功能模型配默认）
      [
        {
          icon: $r('sys.symbol.link'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_PROVIDER,
          secondary: SUBTITLE_PROVIDER,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PROVIDER, this.onOpenProvider)
          }
        },
        {
          icon: $r('sys.symbol.wand_and_stars'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_FUNCTIONAL_MODEL,
          secondary: SUBTITLE_FUNCTIONAL_MODEL,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_FUNCTIONAL_MODEL, this.onOpenFunctionalModel)
          }
        }
      ],
      // 卡2：提示词 + 技能库 + 知识库（给模型的指令面；系统提示词入口在「会话提示词」页首卡）
      [
        {
          icon: $r('sys.symbol.textformat'),
          iconBg: SETTING_ICON_PURPLE,
          label: SETTING_TITLE_PROMPT,
          secondary: SUBTITLE_PROMPT,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PROMPT, this.onOpenPrompts)
          }
        },
        // 技能库行（与提示词同属「给模型的指令面」，挂同一张组卡语义连贯）
        {
          icon: $r('sys.symbol.wand_and_stars'),
          iconBg: SETTING_ICON_PURPLE,
          label: SETTING_TITLE_SKILL_LIBRARY,
          secondary: SUBTITLE_SKILL_LIBRARY,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_SKILL_LIBRARY, this.onOpenSkillLibrary)
          }
        },
        // 知识库行（提示词/技能/知识库同属指令面；行序 = 提示词/技能库/知识库，PageMapBuilder 的库页分支位次
        // 与此对齐——该件文件头的硬性约定）
        {
          icon: $r('sys.symbol.bookshelf'),
          iconBg: SETTING_ICON_PURPLE,
          label: SETTING_TITLE_KNOWLEDGE_LIBRARY,
          secondary: SUBTITLE_KNOWLEDGE_LIBRARY,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_KNOWLEDGE_LIBRARY, this.onOpenKnowledgeLibrary)
          }
        }
      ],
      // 卡3：记忆 + 主动消息（主动消息内容基于会话上下文与长期记忆，两入口同属记忆与主动触达域；组内序 =
      // 记忆在前主动消息在后，与合卡前两卡相邻序一致）
      [
        {
          icon: $r('sys.symbol.memory_module'),
          iconBg: SETTING_ICON_GREEN,
          label: SETTING_TITLE_MEMORY,
          secondary: SUBTITLE_MEMORY,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_MEMORY, this.onOpenMemory)
          }
        },
        {
          icon: $r('sys.symbol.paperplane_fill'),
          iconBg: SETTING_ICON_GREEN,
          label: SETTING_TITLE_PROACTIVE,
          secondary: SUBTITLE_PROACTIVE,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PROACTIVE, this.onOpenProactive)
          }
        }
      ],
      // 卡4：工具调用 + 文件工作区 + 文件夹挂载（三行；联网搜索入口已迁「工具调用」页首组卡，组键随之变
      //「工具调用」——外层 ForEach 键 = 组首行标题，仅作静态组标识、不承载状态）。三行同属对话工具域：工作区
      // 是 workspace 三工具产出文件的用户管理面，文件夹挂载是授权外部域（沙箱域 vs 授权外部域，两文件域平行）
      [
        {
          icon: $r('sys.symbol.wrench_and_screwdriver'),
          iconBg: SETTING_ICON_ORANGE,
          label: SETTING_TITLE_TOOLS,
          secondary: SUBTITLE_TOOLS,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_TOOLS, this.onOpenTools)
          }
        },
        {
          // 文件工作区行（图标 folder 与助手工具页「文件工作区」工具卡同源符号）
          icon: $r('sys.symbol.folder'),
          iconBg: SETTING_ICON_ORANGE,
          label: SETTING_TITLE_WORKSPACE,
          secondary: SUBTITLE_WORKSPACE,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_WORKSPACE, this.onOpenWorkspace)
          }
        },
        {
          // 文件夹挂载行（图标 externaldrive = 外部存储域语义；副标题与工作区行形成域区分）
          icon: $r('sys.symbol.externaldrive'),
          iconBg: SETTING_ICON_ORANGE,
          label: SETTING_TITLE_MOUNT,
          secondary: SUBTITLE_MOUNT,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_MOUNT, this.onOpenMount)
          }
        }
      ],
      // 卡5：网络 + Web 服务（网络出口域紧随联网域；Web 服务 = 浏览器远程访问设置页入口，同属网络域——
      // 组键仍 = 首行「网络设置」不变）
      [
        {
          icon: $r('sys.symbol.network_acceleration'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_NETWORK,
          secondary: SUBTITLE_NETWORK,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_NETWORK, this.onOpenNetwork)
          }
        },
        {
          // Web 服务行（图标 website = 浏览器访问语义；iconBg 同卡同色——SETTING_ICON_BLUE）
          icon: $r('sys.symbol.website'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_WEB_SERVICE,
          secondary: SUBTITLE_WEB_SERVICE,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_WEB_SERVICE, this.onOpenWebService)
          }
        }
      ],
      // 卡6：偏好与外观（单行——原「偏好设置 + 外观显示」两行随重梳笔并一行，外观域入口在
      // 偏好与外观页「外观」板块三行：背景 / 字体 / 图标）
      [
        {
          icon: $r('sys.symbol.slider_horizontal_2'),
          iconBg: SETTING_ICON_PURPLE,
          label: SETTING_TITLE_PREFERENCES,
          secondary: SUBTITLE_PREFERENCES,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PREFERENCES, this.onOpenPreferences)
          }
        }
      ],
      // 卡7：用量统计 + 费用估计（两行同属「用量与费用」统计域，费用估计的时段口径与数据源均与用量统计同构；
      // 居偏好外观卡下、数据与同步卡上）
      [
        {
          icon: $r('sys.symbol.data_proportion'),
          iconBg: SETTING_ICON_GREEN,
          label: SETTING_TITLE_USAGE_STATS,
          secondary: SUBTITLE_USAGE_STATS,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_USAGE_STATS, this.onOpenUsageStats)
          }
        },
        {
          icon: $r('sys.symbol.yuansign_circle'),
          iconBg: SETTING_ICON_GREEN,
          label: SETTING_TITLE_COST_STATS,
          secondary: SUBTITLE_COST_STATS,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_COST_STATS, this.onOpenCostStats)
          }
        }
      ],
      // 卡8：数据与同步 + 存储管理（两入口同属数据域，存储管理本就是数据与同步的下级语义）
      [
        {
          icon: $r('sys.symbol.externaldrive'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_DATA_SYNC,
          secondary: SUBTITLE_DATA_SYNC,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_DATA_SYNC, this.onOpenDataSync)
          }
        },
        {
          icon: $r('sys.symbol.externaldrive_3'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_STORAGE,
          secondary: SUBTITLE_STORAGE,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_STORAGE, this.onOpenStorage)
          }
        }
      ],
      // 卡9：更多信息（恒最下；原「自检」独立卡已随应用内自检全量退役删除）
      [
        {
          icon: $r('sys.symbol.doc_text'),
          iconBg: SETTING_ICON_BLUE,
          label: SETTING_TITLE_MORE_INFO,
          secondary: SUBTITLE_MORE_INFO,
          chevron: true,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_MORE_INFO, this.onOpenInfo)
          }
        }
      ]
    ];
  }

  // 版块归组：九张组卡归五板块，只做「归组」，组卡数据仍单源 settingGroups()（组序与组内行序零变化——决明
  //「组卡不要变」）；卡序由 assert-ui-shape ㊾ 组、assert-mount-domain 335 组等组卡序钉守（漂移先红），故按位取卡。
  // 标题 = 版块大致职能的极简概括（决明指令「不需要覆盖版块内所有功能，要短」），无副标题；不入搜索注册表
  private settingSections(): SettingSection[] {
    const all: GroupEntryItem[][] = this.settingGroups();
    return [
      // 板块1 = 卡1（服务商管理 + 功能模型）
      { title: SECTION_TITLE_ACCESS, groups: [all[0]] },
      // 板块2 = 卡2（提示词·技能库·知识库）+ 卡3（记忆·主动消息）
      { title: SECTION_TITLE_ASSISTANT, groups: [all[1], all[2]] },
      // 板块3 = 卡4（工具调用·文件工作区·文件夹挂载）+ 卡5（网络·Web 服务）
      { title: SECTION_TITLE_TOOLS_NET, groups: [all[3], all[4]] },
      // 板块4 = 卡6（偏好与外观）+ 卡7（用量统计·费用估计）
      { title: SECTION_TITLE_PREFS_USAGE, groups: [all[5], all[6]] },
      // 板块5 = 卡8（数据与同步·存储管理）+ 卡9（更多信息）
      { title: SECTION_TITLE_DATA_MORE, groups: [all[7], all[8]] }
    ];
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: SECTION_GAP }) {
        // 五个版块（组卡上方 SectionHeader；组卡零变化——数据单源 settingGroups()，经 settingSections() 归组）。
        // 外层 ForEach key = 版块标题（五标题静态唯一），内层 key = 组首行标题（互不重复，仅用于稳定标识）
        ForEach(this.settingSections(), (section: SettingSection) => {
          Column({ space: SECTION_HEADER_GAP }) {
            SectionHeader({ title: section.title })
            Column({ space: CARD_SPACING }) {
              ForEach(section.groups, (group: GroupEntryItem[]) => {
                GroupSettingCard({ items: group, dividerLeft: DIVIDER_LEFT_ICON_LARGE })
              }, (group: GroupEntryItem[]): string => group[0].label)
            }
            .width('100%')
          }
          .width('100%')
        }, (section: SettingSection): string => section.title)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      // 顶部让位 = searchBandContentTop（算式单源 = SearchTopBand 同名函数，三库页同款
      // gap 28）：带内框位（带顶 = topPad − 蒙层下延 16，框底 = topPad + 32）+ gap。让位
      // 恒定不随收带切换——下滑收带后此处留白随内容滚出视口（滚动中无感），回顶时带恢复、
      // 留白正好让出框位，两态自洽；不随 settingsBandHidden 切换省一次整页重排
      .padding({ top: searchBandContentTop(this.topPad, 28), bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（Scroll align 默认 Center——坑18）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    // 偏移上抛（高频回调直通导航壳状态机，本页不落状态、不做阈值判断——单源在
    // HomeNavigation.onSettingsScrollOffset）
    .onDidScroll((): void => {
      this.onScrollOffset(this.scroller.currentOffset().yOffset);
    })
    .scrollBar(BarState.Off)
  }
}

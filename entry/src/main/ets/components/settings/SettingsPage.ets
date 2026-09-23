// 设置页（2026-08-29 M2a 建，轮 7~9 改版；M2c 反馈轮 1 扩三行卡；2026-09-04 扩至九行卡；
// ★ 2026-09-07 组卡化）：九入口合并为组卡（分组 = 决明拍板；★ 2026-09-08 决明卡序调整，
// ★ 2026-09-09 附件落盘第二轮增「存储管理」卡、同日决明指令与「数据与同步」合并为一张
// 双行组卡；★ 2026-09-10 决明指令联网搜索自卡1迁出、记忆卡下与新增「工具调用」组成两行
// 主卡——卡1 服务商管理+功能模型 → 卡2 系统提示词+提示词 → 卡3 记忆 → 卡4 联网搜索
// +工具调用 → 卡5 偏好设置+外观显示 → 卡6 用量统计+费用估计 → 卡7 数据与同步+存储
// 管理 → 卡8 更多信息；★ 2026-09-10 费用估计笔卡6 由单行扩两行组卡；★ 2026-09-12 决明
// 指令应用内自检入口自更多信息页应用信息板块迁出——新增「自检」单独卡插更多信息上
//（现卡1 服务商管理+功能模型 → 卡2 系统提示词+提示词 → 卡3 记忆 → 卡4 联网搜索+工具调用
// → 卡5 偏好设置+外观显示 → 卡6 用量统计+费用估计 → 卡7 数据与同步+存储管理 → 卡8 自检
// → 卡9 更多信息），行点击 push 同名二级页；★ 2026-09-12 主动消息第一笔新增「主动消息」
// 单独卡插记忆卡后（现卡1 服务商管理+功能模型 → 卡2 系统提示词+提示词 → 卡3 记忆 →
// 卡4 主动消息 → 卡5 联网搜索+工具调用 → 卡6 偏好设置+外观显示 → 卡7 用量统计+费用
// 估计 → 卡8 数据与同步+存储管理 → 卡9 自检 → 卡10 更多信息）；★ 同日决明指令主动消息
// 与记忆合卡——主动消息内容基于会话上下文与长期记忆，两入口同域，两张单行组卡回归组卡
// 常例（现卡1 服务商管理+功能模型 → 卡2 系统提示词+提示词 → 卡3 记忆+主动消息 →
// 卡4 联网搜索+工具调用 → 卡5 偏好设置+外观显示 → 卡6 用量统计+费用估计 → 卡7 数据与
// 同步+存储管理 → 卡8 更多信息）；★ 2026-09-13 技能层笔 1：「技能库」入卡2
// 第三行（与系统提示词/提示词同属「给模型的指令面」——提示词是身份与规则、技能是怎么做
// 的流程，同一张卡里语义连贯）；★ 2026-09-20 应用内自检全量退役：「自检」单独卡与
// 检测页、域件、路由一并删除（卡数九张回八张，更多信息卡序不变仍恒最下）。
// 组卡样式 = components/GroupSettingCard.ets（2026-09-07 新建：官方系统设置「星闪和蓝牙 →
// 已配对设备」卡真机实测规格复刻——行高 56/64vp 固定分档 / 24vp 符号 / 16vp 间距 / 14fp
// 副标题 / 0.5vp 分割线 / 卡圆角 16 项目统一；选型理由与实测表见该组件头注释，本页不展开）。
// 行卡片内容 = 原文案（2026-08-30 反馈轮 10 领导指令「副标题 = 对卡功能的简介描述」，
// SUBTITLE_* 常量动词开头一句简介；2026-08-30 系统提示词改名口径同步——文案九条不变）。
// 卡片点击 recordRecentUse 记「最近使用」（dshinhm 口径：搜索跳转 + 卡片点击两处记录，
// 展示经注册表反查）——九行同构，经 openCard 收口 + settingGroups() 类型化数据
// （ArkTS 禁 build 内匿名对象字面量数组——10605038）。
// ★ 2026-09-07 组卡化取代原 HdsListItemCard 单卡（反馈轮 11 拍板样式）——组卡为官方基础
// 组件拼装，无 HDSComponent.Full 门槛，hdsListCardAvailable/SettingRow 双分支与回退自制卡
// 整体退役；行卡不挂 .width() 的 HDS 口径随之失效（组卡自持 CARD_PANEL_WIDTH）。
import { CARD_SPACING } from '../../common/Theme';
import { recordRecentUse, SETTING_TITLE_APPEARANCE, SETTING_TITLE_COST_STATS, SETTING_TITLE_DATA_SYNC, SETTING_TITLE_FUNCTIONAL_MODEL, SETTING_TITLE_KNOWLEDGE_LIBRARY, SETTING_TITLE_MORE_INFO, SETTING_TITLE_MEMORY, SETTING_TITLE_PREFERENCES, SETTING_TITLE_PROMPT, SETTING_TITLE_PROVIDER, SETTING_TITLE_PROACTIVE, SETTING_TITLE_SEARCH_ENGINE, SETTING_TITLE_SKILL_LIBRARY, SETTING_TITLE_STORAGE, SETTING_TITLE_SYSTEM_PROMPT, SETTING_TITLE_TOOLS, SETTING_TITLE_USAGE_STATS } from '../../common/SettingSearch';
import { GroupEntryItem, GroupSettingCard } from '../GroupSettingCard';

// 行卡副标题（官方 TextItemOptions.secondaryText 文案——动词开头一句功能简介，轮 10 领导
// 指令「副标题是对卡功能的简介描述，你写」；只此一处使用，不入搜索注册表）
const SUBTITLE_PROVIDER: string = '管理 AI 服务商连接、密钥与模型';
const SUBTITLE_APPEARANCE: string = '调整沉浸光感与背景壁纸';
const SUBTITLE_MORE_INFO: string = '帮助中心、运行日志与关于';
// 2026-08-30 系统提示词改名：子标题与行卡名统一口径
const SUBTITLE_SYSTEM_PROMPT: string = '会话未启用会话提示词时自动注入';
const SUBTITLE_PROMPT: string = '管理提示词库：系统提示词与会话提示词';
// 2026-09-01 偏好设置第 4 卡（放会话提示词后——领导指令；副标题同「动词开头一句简介」口径）
const SUBTITLE_PREFERENCES: string = '设置默认展开思考等偏好';
// 2026-09-03 新增（第三批③：全量导入导出 + WebDAV 同步；2026-09-05 决明调序移到更多信息上）
const SUBTITLE_DATA_SYNC: string = '全量备份、恢复与 WebDAV 同步';
// 2026-09-05 新增（功能模型页：功能级模型配置集中页，首项「默认模型」；同日决明调序
// 放服务商管理下）
const SUBTITLE_FUNCTIONAL_MODEL: string = '集中设置 AI 功能默认使用的模型';
// 2026-09-06 新增（用量统计：token 消耗与生成速度纯列表统计页；放偏好设置后——口径⑤）
const SUBTITLE_USAGE_STATS: string = '查看 token 消耗与生成速度';
// 2026-09-10 新增（费用估计：模型价格 × 用量折算的估算页——与用量统计同组卡第二行；
// 副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_COST_STATS: string = '估算各模型的费用花销';
// 2026-09-08 新增（记忆域：跨会话长期记忆管理页；同日决明卡序调整 = 移至提示词卡后——卡序
// 与 PageMap 分支同步；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_MEMORY: string = '管理跨会话的长期记忆';
// 2026-09-09 新增（附件全量落盘第二轮·存储管理页：数据与同步卡内第二行——六分类占用
// 与可安全清理；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_STORAGE: string = '查看本机存储占用与清理';
// 2026-09-10 新增（多引擎一期·联网搜索页：原卡1第三行，同日决明指令迁记忆卡下与工具调用
// 组成两行主卡——引擎列表〔分段已启用/已停用〕与详情配置；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_SEARCH_ENGINE: string = '配置联网搜索的引擎与密钥';
// 2026-09-10 新增（决明指令：工具调用行卡——二级页现承载「网页高危操作确认」全局工具卡
//〔2026-09-18 七百五十五节，建卡时曾为空占位〕；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_TOOLS: string = '管理内置工具的全局设置';
// 2026-09-12 新增（主动消息第一笔「触发链底层」：设置页「主动消息」单行卡——总开关 +
// 触发间隔的二级页入口；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_PROACTIVE: string = '管理助手主动发消息';
// 2026-09-13 新增（技能层笔 1：技能库管理页入口——技能 = 助手的「怎么做某件事」说明书，
// 按触发描述被模型自主加载；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_SKILL_LIBRARY: string = '创建和维护助手可用的技能';
// 2026-09-21 新增（世界书知识库首版：知识库管理页入口——知识库 = 用户手写的词条本，
// 助手觉得需要某领域知识时自己去查；副标题动词开头一句简介口径，≤13 字）
const SUBTITLE_KNOWLEDGE_LIBRARY: string = '让助手按需查阅的词条本';

@Component
export struct SettingsPage {
  // 顶部/底部留白（vp，导航壳下发）
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  // 行卡点击回调（导航壳执行 push 对应二级页）
  onOpenProvider: () => void = () => {
  };
  onOpenAppearance: () => void = () => {
  };
  onOpenInfo: () => void = () => {
  };
  onOpenPrompts: () => void = () => {
  };
  // 系统提示词行卡点击（导航壳 push 编辑页——pushSystemPrompt）
  onOpenSystemPrompt: () => void = () => {
  };
  // 偏好设置行卡点击（导航壳 push 偏好设置页——pushPreferences，2026-09-01）
  onOpenPreferences: () => void = () => {
  };
  // 数据与同步行卡点击（导航壳 push DataSyncPage——pushDataSync，2026-09-03）
  onOpenDataSync: () => void = () => {
  };
  // 功能模型行卡点击（导航壳 push FunctionalModelPage——pushFunctionalModel，2026-09-05）
  onOpenFunctionalModel: () => void = () => {
  };
  // 用量统计行卡点击（导航壳 push UsageStatsPage——pushUsageStats，2026-09-06）
  onOpenUsageStats: () => void = () => {
  };
  // 费用估计行卡点击（导航壳 push CostStatsPage——pushCostStats，2026-09-10 费用估计；
  // 与用量统计组成两行组卡）
  onOpenCostStats: () => void = () => {
  };
  // 记忆行卡点击（导航壳 push MemoryPage——pushMemory，2026-09-08 记忆域）
  onOpenMemory: () => void = () => {
  };
  // 存储管理行卡点击（导航壳 push StoragePage——pushStorage，2026-09-09 附件落盘第二轮）
  onOpenStorage: () => void = () => {
  };
  // 联网搜索行卡点击（导航壳 push SearchEnginePage——pushSearchEngine，2026-09-10 多引擎
  // 一期；同日迁记忆卡下两行主卡首行）
  onOpenSearchEngine: () => void = () => {
  };
  // 工具调用行卡点击（导航壳 push ToolsSettingsPage——pushTools，2026-09-10 决明指令，
  // 建卡时曾为空占位、现承载高危确认卡）
  onOpenTools: () => void = () => {
  };
  // 主动消息行卡点击（导航壳 push ProactivePage——pushProactive，2026-09-12 主动消息
  // 第一笔）
  onOpenProactive: () => void = () => {
  };
  // 技能库行卡点击（导航壳 push SkillLibraryPage——pushSkillLibrary，2026-09-13 技能层笔 1）
  onOpenSkillLibrary: () => void = () => {
  };
  // 知识库行卡点击（导航壳 push KnowledgeLibraryPage——pushKnowledgeLibrary，2026-09-21）
  onOpenKnowledgeLibrary: () => void = () => {
  };
  // 行卡点击统一收口：先记「最近使用」（dshinhm 卡片点击口径）再上抛导航壳 push
  private openCard(recordTitle: string, callback: () => void): void {
    recordRecentUse(recordTitle);
    callback();
  }

  // 组卡行数据（张数随合卡/入列演进，以本方法实际返回为准——2026-09-07 组卡化——分组 =
  // 决明拍板；★ 2026-09-08 决明卡序调整 =
  // 记忆 → 偏好外观 → 用量 → 数据与同步；★ 2026-09-09 存储管理卡插数据与同步下、同日
  // 决明指令两卡合并为一张双行组卡〔同属数据域，单行组卡例外形态收敛为组卡常例〕；
  // ★ 2026-09-10 决明指令联网搜索迁记忆卡下与工具调用组成两行主卡；★ 2026-09-12 决明
  // 指令记忆 + 主动消息两单行卡并为一张双行组卡；
  // 类型化返回（ArkTS 禁 build 内匿名字面量数组
  // ——10605038），onClick 闭包 = 原 SettingRow 回调逐行平移（openCard 收口不变；图标/副
  // 标题常量照旧）。
  // 组内顺序 = 组卡内行序；图标符号与搜索页「最近使用」映射保持一致（勿单独改）
  private settingGroups(): GroupEntryItem[][] {
    return [
      // 卡1：服务商管理 + 功能模型（两行同属「AI 服务接入」域：服务商接模型、功能模型配
      // 默认；联网搜索原第三行，2026-09-10 决明指令迁记忆卡下与工具调用组卡）
      [
        {
          icon: $r('sys.symbol.link'),
          label: SETTING_TITLE_PROVIDER,
          secondary: SUBTITLE_PROVIDER,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PROVIDER, this.onOpenProvider)
          }
        },
        {
          icon: $r('sys.symbol.wand_and_stars'),
          label: SETTING_TITLE_FUNCTIONAL_MODEL,
          secondary: SUBTITLE_FUNCTIONAL_MODEL,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_FUNCTIONAL_MODEL, this.onOpenFunctionalModel)
          }
        }
      ],
      // 卡2：系统提示词 + 提示词
      [
        {
          icon: $r('sys.symbol.doc_text'),
          label: SETTING_TITLE_SYSTEM_PROMPT,
          secondary: SUBTITLE_SYSTEM_PROMPT,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_SYSTEM_PROMPT, this.onOpenSystemPrompt)
          }
        },
        {
          icon: $r('sys.symbol.textformat'),
          label: SETTING_TITLE_PROMPT,
          secondary: SUBTITLE_PROMPT,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PROMPT, this.onOpenPrompts)
          }
        },
        // ★ 2026-09-13 技能层笔 1：技能库入本卡第三行——与提示词同属「给模型的指令面」
        //（提示词是身份与规则、技能是怎么做的流程），挂在同一张指令面组卡里语义连贯；
        // 单行组卡会让设置页再多一张卡，而技能库入口还有个助手技能页的深层入口兜底
        {
          icon: $r('sys.symbol.wand_and_stars'),
          label: SETTING_TITLE_SKILL_LIBRARY,
          secondary: SUBTITLE_SKILL_LIBRARY,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_SKILL_LIBRARY, this.onOpenSkillLibrary)
          }
        },
        // ★ 2026-09-21 世界书知识库首版：知识库入本卡第四行——与提示词/技能同属「给模型的
        // 指令面」（提示词是身份与规则、技能是怎么做的流程、知识库是用户可以喂的领域知识），
        // 挂在同一张组卡里语义连贯；行序 = 系统提示词/提示词/技能库/知识库，PageMapBuilder
        // 的库页分支位次与此对齐（该件文件头的硬性约定）
        {
          icon: $r('sys.symbol.bookshelf'),
          label: SETTING_TITLE_KNOWLEDGE_LIBRARY,
          secondary: SUBTITLE_KNOWLEDGE_LIBRARY,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_KNOWLEDGE_LIBRARY, this.onOpenKnowledgeLibrary)
          }
        }
      ],
      // 卡3：记忆 + 主动消息（★ 2026-09-12 决明指令合卡——记忆 2026-09-08 域新增单行卡、
      // 主动消息 2026-09-12 第一笔以单行卡插记忆卡后，同日拍板并为一张双行组卡：主动消息
      // 内容基于会话上下文与已记住的长期记忆，两入口同属记忆与主动触达域，合并后由
      // 「独立成行」例外回归组卡常例〔先例 = 2026-09-09 数据与同步 + 存储管理合并卡〕；
      // 组内序 = 记忆在前主动消息在后，与合卡前两卡相邻序一致）
      [
        {
          icon: $r('sys.symbol.memory_module'),
          label: SETTING_TITLE_MEMORY,
          secondary: SUBTITLE_MEMORY,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_MEMORY, this.onOpenMemory)
          }
        },
        {
          icon: $r('sys.symbol.paperplane_fill'),
          label: SETTING_TITLE_PROACTIVE,
          secondary: SUBTITLE_PROACTIVE,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PROACTIVE, this.onOpenProactive)
          }
        }
      ],
      // 卡4：联网搜索 + 工具调用（★ 2026-09-10 决明指令：联网搜索自卡1迁此置记忆卡下，
      // 与新增工具调用行组成两行主卡——两行同属对话工具与联网能力配置域；工具调用二级页
      // 现承载「网页高危操作确认」全局工具卡，建卡时曾为空占位）
      [
        {
          icon: $r('sys.symbol.magnifyingglass'),
          label: SETTING_TITLE_SEARCH_ENGINE,
          secondary: SUBTITLE_SEARCH_ENGINE,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_SEARCH_ENGINE, this.onOpenSearchEngine)
          }
        },
        {
          icon: $r('sys.symbol.wrench_and_screwdriver'),
          label: SETTING_TITLE_TOOLS,
          secondary: SUBTITLE_TOOLS,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_TOOLS, this.onOpenTools)
          }
        }
      ],
      // 卡5：偏好设置 + 外观显示（组卡化后将原 5/7 两行合并——偏好与显示同置一卡）
      [
        {
          icon: $r('sys.symbol.slider_horizontal_2'),
          label: SETTING_TITLE_PREFERENCES,
          secondary: SUBTITLE_PREFERENCES,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_PREFERENCES, this.onOpenPreferences)
          }
        },
        {
          icon: $r('sys.symbol.paintpalette'),
          label: SETTING_TITLE_APPEARANCE,
          secondary: SUBTITLE_APPEARANCE,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_APPEARANCE, this.onOpenAppearance)
          }
        }
      ],
      // 卡6：用量统计 + 费用估计（2026-09-06 用量统计卡；★ 2026-09-10 费用估计笔由单行
      // 组卡改两行组卡——两行同属「用量与费用」统计域，费用估计的时段口径与数据源均与
      // 用量统计同构，组合卡顺理成章〔方案拍板「与用量统计合组卡」〕；组卡化后居偏好
      // 外观卡下、数据与同步卡上）
      [
        {
          icon: $r('sys.symbol.data_proportion'),
          label: SETTING_TITLE_USAGE_STATS,
          secondary: SUBTITLE_USAGE_STATS,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_USAGE_STATS, this.onOpenUsageStats)
          }
        },
        {
          icon: $r('sys.symbol.yuansign_circle'),
          label: SETTING_TITLE_COST_STATS,
          secondary: SUBTITLE_COST_STATS,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_COST_STATS, this.onOpenCostStats)
          }
        }
      ],
      // 卡7：数据与同步 + 存储管理（★ 2026-09-09 决明指令合并——原卡6「数据与同步」与
      // 卡7「存储管理」两张单行组卡并为一张双行组卡；两入口同属数据域，存储管理本就是
      // 数据与同步的下级语义，合并后由「独立成行」例外回归组卡常例）
      [
        {
          icon: $r('sys.symbol.externaldrive'),
          label: SETTING_TITLE_DATA_SYNC,
          secondary: SUBTITLE_DATA_SYNC,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_DATA_SYNC, this.onOpenDataSync)
          }
        },
        {
          icon: $r('sys.symbol.externaldrive_3'),
          label: SETTING_TITLE_STORAGE,
          secondary: SUBTITLE_STORAGE,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_STORAGE, this.onOpenStorage)
          }
        }
      ],
      // 卡8：更多信息（永远最下——2026-08-30 领导指令余留；原「自检」独立单行卡
      // 2026-09-20 随应用内自检全量退役删除，更多信息卡序不变）
      [
        {
          icon: $r('sys.symbol.doc_text'),
          label: SETTING_TITLE_MORE_INFO,
          secondary: SUBTITLE_MORE_INFO,
          onClick: (): void => {
            this.openCard(SETTING_TITLE_MORE_INFO, this.onOpenInfo)
          }
        }
      ]
    ];
  }

  build() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        // ── 八张组卡（2026-09-07 组卡化：九单卡 → 六组卡，2026-09-08 记忆卡入列成七张，
        // 2026-09-09 存储管理卡入列成八张、同日与数据与同步合并回七张，2026-09-10 联网
        // 搜索+工具调用卡入列回八张，2026-09-12 自检卡入列、主动消息卡入列成十张，同日
        // 记忆+主动消息合卡回九张，2026-09-20 自检卡随功能退役删除回八张，分组/组序见
        // settingGroups()；
        // 组卡样式与官方实测规格见 GroupSettingCard.ets 头注释；ForEach key = 组首行标题，
        // 各组首行标题互不重复——组为静态数据无增删，key 仅用于稳定标识）──
        ForEach(this.settingGroups(), (group: GroupEntryItem[]) => {
          GroupSettingCard({ items: group })
        }, (group: GroupEntryItem[]) => group[0].label)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.topPad, bottom: this.bottomPad + 16 })
    }
    .width('100%')
    .height('100%')
    // 滚动内容不足视口时顶对齐（Scroll align 默认 Center——坑18）+ 短内容可拖拽回弹（坑76）
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}

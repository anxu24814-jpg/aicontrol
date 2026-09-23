// 助手编辑页（2026-09-01 助手域分区化，同日按钮区退役轮领导指令定稿；2026-09-01 详情卡
// 轮更新）：**纯分区导航枢纽**——顶部助手详情卡 + 模型设置首卡 + 分区列表卡（提示词/
// 工具调用/记忆/技能/知识库/高级设定，RikkaHub 助手编辑多分区形态的 aicontrol 取型；
// 功能边界 = 提示词 + 模型设置 + 高级设定〔2026-09-01 真卡 DB v11〕+ 工具调用
//〔2026-09-02 真卡 DB v14〕+ 记忆〔2026-09-08 真卡 DB v20——AssistantMemoryPage 注入/
// 沉淀两开关〕+ 技能〔2026-09-13 真卡 DB v30——AssistantSkillPage 技能开关组卡 +
// 管理技能库入口，SkillsCard 对控制台助手不渲染〕+ 知识库〔2026-09-21 真卡 DB v38——
// AssistantKnowledgePage 知识库开关组卡 + 管理知识库入口〕**七项全部落地、无占位项**；
// 原共享占位页（components/assistants 下 71 行纯展示件）随知识库摘出而零消费点，同笔
// 删除（沿革见 docs/变更记录.md 本笔条目——此处不留该件名，理由同 RouteNames 同名注释）。
// ★ 详情卡（2026-09-01 领导指令「每个助手页顶部加类似助手详情卡」）：圆形首字头像 + 助手
// 名 + 右上角编辑键（square_and_pencil 图标键——点弹重命名对话框即落库，原「名称行卡」
// 同日退役——改名入口从行卡点击改卡片右上角按键，弹窗逻辑与时机不变）；★ 内置默认助手
// 同样显示详情卡但不渲染编辑键（名恒定禁改——2026-09-01 反馈轮 3 定稿，禁改不删）——
// 用户助手可改名、默认助手只读同口径；卡上不做换头像/模型/记忆/技能/知识库徽章（领导
// 指令裁剪：头像 = 首字圆底形制，无自定义头像功能）。
// ★ 按钮区退役（领导指令：删除键去掉——一级页助手卡已有删除；保存键去掉——需要时按项
// 落在各设置页加，提示词页已有保存）：底部删除/保存整体退役；名称修改经详情卡右上角
// **重命名对话框即时落库**（InputDialog——会话卡/Key 池 label 改名同款先例拍板口径
// 「即时落库不经保存键」；InputDialog 自带空值校验/同值静默跳过）。
// ★ 新建态退役：「＋」改为列表页弹新建对话框（RikkaHub 同款）——确认 insert 落行、取消
// 不落行，本页恒编辑态（只从点列表卡进入，行必已存在；空参 push = 异常路径弹回）。
// 取参：push param = 助手 id（AssistantPage 点卡 push）。
// · 内置默认助手：详情卡照显（头像+名）但**无编辑键**（名恒定禁改）——仅六张分区卡；
// 提示词卡进只读提示词页（反馈轮 3 只读语义在 AssistantPromptPage，不改）。★ 内置控制台
// 助手（2026-09-05）同口径：名恒定禁改 + 提示词只读（内容 = AssistantDb 读时联结的内置
// 路由提示词）；模型绑定/工具/高级设定照常可改。
// ★ 模型设置卡（2026-09-01 领导指令，放首卡 = 详情卡后）：助手级模型绑定 + 思考档位
// 入口——进独立页 ModelSettingsPage（选择半模态/强度菜单同会话页机制，DB v10）；卡面
// 副行摘要 = 绑定模型 + 档位，onPop 重拉（DB 单一真源，删服务商/删模型级联清列自动跟随）。
// ★ 高级设定卡（2026-09-01 高级设定，DB v11）：原占位分区卡转真卡（占位清单摘项）——
// 进二级页 AssistantAdvancedPage（采样参数/上下文与输出两行卡 → 各三级页，采样与
// 上下文参数落 assistants.advancedParams JSON 列）；卡面副行摘要 = '默认'/'已自定义'，
// onPop 重拉（模型设置卡同链）。
// 刷新链（规范-数据存储获取刷新方案）：本页无保存动作——返回经 **onBackPressed 拦截 →
// pop({saved:true})** 触发列表页 onPop reload（坑17「无保存动作的完成返回」标准姿势，
// 排序页先例；覆盖重命名后返回的列表名称刷新；未改动返回 reload 幂等无害）；提示词页
// pop 带 result → onPop 重拉提示词摘要（★ 只刷 this.prompt 不动 this.name——名称已即时
// 落库但仍防竞态覆盖对话框外输入，两状态独立）；占位页无保存动作不挂 onPop（死链自查）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import {
  ROUTE_ASSISTANT_ADVANCED_PAGE, ROUTE_ASSISTANT_EDIT_PAGE, ROUTE_ASSISTANT_KNOWLEDGE_PAGE,
  ROUTE_ASSISTANT_MEMORY_PAGE, ROUTE_ASSISTANT_PROMPT_PAGE, ROUTE_ASSISTANT_SKILL_PAGE,
  ROUTE_ASSISTANT_TOOLS_PAGE, ROUTE_MODEL_SETTINGS_PAGE
} from '../../common/RouteNames';
import { CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, DETAIL_CARD_TITLE_FONTSIZE } from '../../common/Theme';
import { overlayMaterial } from '../../common/ImmersiveLevel';
import {
  ASSISTANT_CONSOLE_ID, ASSISTANT_DEFAULT_ID, ASSISTANT_NAME_MAX,
  AssistantRow, queryAssistant, updateAssistantName
} from '../../common/store/AssistantDb';
import { MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
import { ModelRow, ProviderRow, queryModels, queryProviders } from '../../common/store/ProviderDb';
import { PREF_SEARCH_SERVICE_ENABLED_KEY } from '../../common/AppPreferences';
import { parseEnabledToolIds, TOOL_SEARCH_WEB, ToolGroup, toolGroupAllOn, visibleToolGroups }
  from '../../common/providers/ToolTypes';
import { parseEnabledKnowledgeIds } from '../../common/KnowledgeText';
import { parseEnabledSkillIds } from '../../common/SkillText';
import { InputDialog } from '../chat/InputDialog';

// ★ 占位分区机制整体退役（2026-09-21 世界书知识库首版）：原「知识库」是占位清单里最后
// 一项，本笔摘出转真卡 KnowledgeCard（DB v38——AssistantKnowledgePage 启用开关组卡 +
// 管理知识库入口）后，占位清单常量、占位项接口、ForEach 渲染块与占位页跳转方法一并删除，
// 占位页文件与路由常量零消费点随之同笔删除（死代码清理，非顺手重构）。自此本页七张卡
// 全部是真卡：模型设置（v10）/ 工具调用（v14）/ 记忆（v20）/ 技能（v30）/ 知识库（v38）
// + 提示词（v1 起）/ 高级设定（v11）。

@Component
export struct AssistantEditPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 助手名称（详情卡展示 + 重命名对话框初值；改名即时落库后本状态同步刷新）
  @State private name: string = '';
  // 提示词摘要（分区卡副行展示用——非编辑值，编辑在提示词二级页；提示词页保存返回经
  // onPop 重拉刷新）
  @State private prompt: string = '';
  // 模型设置卡副行摘要（2026-09-01 模型绑定起：绑定模型名 + 思考档位，'' = 未绑定显示
  // 兜底「未选择模型」；模型设置页返回经 onPop 重拉刷新——DB 单一真源，级联清列自动反映）
  @State private modelSummary: string = '';
  // 高级设定卡副行摘要（2026-09-01 高级设定：'默认'/'已自定义'——advancedParams 列空/
  // 非空；二级页返回经 onPop 重拉刷新）
  @State private advancedSummary: string = '默认';
  // 工具卡副行摘要（2026-09-02 工具调用底层：恒报实际状态——★ 2026-09-18 卡口径统一
  //〔七百三十二节〕：按**用户可见入口**计数——工具页分类卡重组后入口 = 八张卡（★ 2026-09-21
  // 记忆与知识库剥离笔后自六张增至八张），摘要改报「已开卡数/卡总数」（'联网开 · 2/8 项启用'），
  // 底层逐件 id 数不再上屏；联网态前缀保留
  //〔联网是唯一在别处还有全局闸的工具，须一眼可见——该词在本页 = 出厂默认集合、在高级设定
  // 卡 = 没配过，同词两义，故前缀恒报实际态不写「默认」〕。工具页返回经 onPop 重拉刷新；
  // 初值 '' 待 aboutToAppear 查询回填）
  @State private toolsSummary: string = '';
  // 摘要重算入参缓存（tools 列原串——联网总开关翻转时摘要须重算，见 onWebServiceChanged）
  private toolsRaw: string = '';
  // 联网搜索总开关（★ 卡口径统一配套订阅）：卡是否已开含联网压制判定（总开关关闭时联网
  // 从属件不进可开件分母），故摘要口径与工具页卡开关一样受它影响；改在设置页时经 @Watch
  // 在场重算（工具页同名订阅同源、appColorMode 同款姿势）。★ 本订阅是「无 pop 返回」路径
  // 的唯一刷新源——三页签共用同一 NavPathStack，切 tab 回来不发生 pop，onPop 只管从工具页
  // 返回；勿按「onPop 兜底」删本订阅
  @StorageProp(PREF_SEARCH_SERVICE_ENABLED_KEY) @Watch('onWebServiceChanged') searchServiceEnabled: boolean =
    true;
  // 记忆卡副行摘要（2026-09-08 记忆域：'注入开 · 沉淀开' 形态——memoryInject/memorySink
  // 两列布尔映射；助手记忆页返回经 onPop 重拉刷新）
  @State private memorySummary: string = '注入开 · 沉淀开';
  // 技能卡副行摘要（2026-09-13 技能层：'已启用 N 个技能' / '未启用' 形态——skills 列解析
  // 计数；助手技能页返回经 onPop 重拉刷新）
  @State private skillSummary: string = '未启用';
  // 知识库卡副行摘要（2026-09-21 世界书知识库：'已启用 N 个知识库' / '未启用' 形态——
  // knowledge 列解析计数；助手知识库页返回经 onPop 重拉刷新）
  @State private knowledgeSummary: string = '未启用';
  // 编辑对象行 id（本页恒编辑态——空参 push = 异常路径弹回）
  private rowId: string = '';
  // 重命名对话框控制器（★ 组件成员位——坑7：普通类成员构造 open() 静默无效）
  private renameCtrl: CustomDialogController | null = null;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  aboutToAppear(): void {
    // push 参数（getParamByName 取末条，ModelEditPage 先例）：string id（点列表卡 push，
    // 必非空；空/缺参 = 异常路径弹回——新建已改走列表页对话框，不再进本页）
    const params: Array<string> =
      this.pathStack.getParamByName(ROUTE_ASSISTANT_EDIT_PAGE) as Array<string>;
    const param: string | undefined = params.length > 0 ? params[params.length - 1] : undefined;
    if (param === undefined || param === '') {
      this.getUIContext().getPromptAction().showToast({ message: '缺少助手参数' });
      this.pathStack.pop();
      return;
    }
    this.rowId = param;
    // 读时联结：默认助手 prompt = 系统提示词当前值（分区摘要即时同步）
    queryAssistant(param)
      .then((row): void => {
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '助手不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.name = row.name;
        this.prompt = row.prompt;
        this.advancedSummary = row.advancedParams === '' ? '默认' : '已自定义';
        this.refreshToolsSummary(row.tools);
        this.refreshMemorySummary(row);
        this.refreshSkillSummary(row.skills);
        this.refreshKnowledgeSummary(row.knowledge);
        // 模型卡摘要（绑定行解析异步——失败 toast 不静默，卡面兜底「未选择模型」）
        this.refreshModelSummary();
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '助手读取失败：' + (e as Error).message });
        this.pathStack.pop();
      });
  }

  // 内置默认助手判定（详情卡无编辑键——名恒定禁改，仅分区卡）
  private isDefault(): boolean {
    return this.rowId === ASSISTANT_DEFAULT_ID;
  }

  // 内置助手判定（2026-09-05 控制台助手扩展：默认/控制台均名恒定禁改——详情卡不渲染
  // 编辑键；提示词分区均只读，文案分支各自区分）
  private isBuiltin(): boolean {
    return this.rowId === ASSISTANT_DEFAULT_ID || this.rowId === ASSISTANT_CONSOLE_ID;
  }

  // 重命名（详情卡右上角编辑键弹对话框——即时落库不经保存键，Key 池/会话重命名同款口径；
  // InputDialog 自带空值 toast 留窗/同值静默跳过；失败 toast 不静默；列表刷新 = 返回时
  // pop 带 result → onPop reload）
  private openRenameDialog(): void {
    this.renameCtrl = new CustomDialogController({
      systemMaterial: overlayMaterial(),
      builder: InputDialog({
        title: '重命名助手',
        initialText: this.name,
        placeholder: '如 翻译助手、代码顾问',
        confirmLabel: '确认',
        maxLength: ASSISTANT_NAME_MAX,
        onConfirm: (text: string): void => {
          updateAssistantName(this.rowId, text)
            .then((): void => {
              this.name = text;
              this.getUIContext().getPromptAction().showToast({ message: '已重命名' });
            })
            .catch((e: Object): void => {
              this.getUIContext().getPromptAction().showToast({ message: '重命名失败：' + (e as Error).message });
            });
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.renameCtrl.open();
  }

  // 提示词分区卡副行摘要：内置助手明示只读——默认助手 = 与系统提示词恒同步，控制台助手 =
  // 内置指引；用户助手 = 内容单行省略 / 空时未设置明示（2026-09-04 回退口径 = 发送时用
  // 系统提示词）
  private promptSummary(): string {
    if (this.rowId === ASSISTANT_CONSOLE_ID) {
      return '内置指引，只读';
    }
    if (this.isDefault()) {
      return '与系统提示词恒同步，只读';
    }
    const prompt: string = this.prompt.trim();
    return prompt !== '' ? prompt : '未设置（发送时用系统提示词）';
  }

  // 提示词页跳转：onPop 重拉摘要（子页保存 pop 必带 result，坑17 契约；★ 只刷 prompt 不动
  // name——两状态独立防对话框外竞态覆盖；刷新失败 toast 不静默）
  private openPromptPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_PROMPT_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row): void => {
          if (row !== null) {
            this.prompt = row.prompt;
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '提示词摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 模型设置页跳转（2026-09-01 模型绑定首卡；onPop 重拉摘要——子页 pop 必带 result 坑17
  // 契约；★ 只刷 modelSummary 不动 name/prompt——三状态独立；★ 只刷不重入页——onPop 在
  // 本页驻留期回调，直接改 @State 驱动卡面重建）
  private openModelSettingsPage(): void {
    this.pathStack.pushPathByName(ROUTE_MODEL_SETTINGS_PAGE, this.rowId, (): void => {
      this.refreshModelSummary();
    });
  }

  // 高级设定页跳转（2026-09-01 高级设定卡；onPop 重拉摘要——子页 pop 必带 result 坑17
  // 契约；只刷 advancedSummary，其余状态独立）
  private openAdvancedPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_ADVANCED_PAGE, this.rowId, (): void => {
      this.refreshAdvancedSummary();
    });
  }

  // 工具页跳转（2026-09-02 工具调用底层真卡；onPop 重拉摘要——子页 pop 必带 result
  // 坑17 契约；只刷 toolsSummary，其余状态独立）
  private openToolsPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_TOOLS_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row): void => {
          if (row !== null) {
            this.refreshToolsSummary(row.tools);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '工具摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 工具卡摘要计算（入参 = tools 列原串；'' = 默认集合；解析在 ToolTypes——★ 卡口径统一
  // 〔七百三十二节〕：不报底层 id 数（原 '联网开 · N 项启用'，N = ids.length 与页面八卡
  // 脱钩），改报可见卡中已开张数 = '联网开 · 已开卡/卡总数 项启用'；「卡是否已开」判定
  // 走 ToolTypes 单一来源（toolGroupAllOn——与工具页卡开关显示态逐条同口径：console-
  // exclusive 与联网压制件不进分母），故口径受联网总开关影响，与页面所见一致）
  private refreshToolsSummary(toolsJson: string): void {
    this.toolsRaw = toolsJson;
    const ids: string[] = parseEnabledToolIds(toolsJson);
    const web: string = ids.includes(TOOL_SEARCH_WEB) ? '联网开' : '联网关';
    const groups: ToolGroup[] = visibleToolGroups();
    let on: number = 0;
    for (const group of groups) {
      if (toolGroupAllOn(group, ids, this.rowId === ASSISTANT_CONSOLE_ID,
        this.searchServiceEnabled)) {
        on++;
      }
    }
    this.toolsSummary = web + ' · ' + on + '/' + groups.length + ' 项启用';
  }

  // 联网总开关变更 → 工具卡摘要重算（★ 卡口径统一配套：摘要含压制口径，总开关翻转会改
  // 「联网卡算不算已开」——如清单只开 search_web 时，总开关关闭该卡算已开、打开则算未开）。
  // 未加载（rowId 未就位）直接返回——首帧空摘要不写假值（P0-1）
  private onWebServiceChanged(): void {
    if (this.rowId === '') {
      return;
    }
    this.refreshToolsSummary(this.toolsRaw);
  }

  // 记忆卡摘要计算（2026-09-08 记忆域：两开关布尔 → '注入开/关 · 沉淀开/关'；
  // ★ v35（2026-09-20 助手级记忆）前置作用域段——'全局记忆 · 注入开 · 沉淀开' / '助手记忆
  // · 注入开 · 沉淀开'，脏值兜底全局）
  private refreshMemorySummary(row: AssistantRow): void {
    const scope: string = row.memoryScope === MEMORY_SCOPE_ASSISTANT ? '助手记忆' : '全局记忆';
    this.memorySummary = scope + ' · ' + (row.memoryInject ? '注入开' : '注入关') + ' · ' +
      (row.memorySink ? '沉淀开' : '沉淀关');
  }

  // 技能卡摘要计算（2026-09-13 技能层：入参 = skills 列原串；'' = 空集合 = 未启用——解析
  // 在 SkillText（与 tools 列语义相反，故不复用工具计数口径））
  private refreshSkillSummary(skillsJson: string): void {
    const count: number = parseEnabledSkillIds(skillsJson).length;
    this.skillSummary = count === 0 ? '未启用' : '已启用 ' + count + ' 个技能';
  }

  // 助手技能页跳转（2026-09-13 技能层真卡；onPop 重拉摘要——子页 pop 必带 result 坑17
  // 契约；只刷 skillSummary，其余状态独立）。★ 控制台助手不渲染本卡（一期不开放技能），
  // 但本方法保留：入口由 SkillCard 的渲染条件把守，链路层封锁在 ChatPromptState
  private openSkillPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_SKILL_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row: AssistantRow | null): void => {
          if (row !== null) {
            this.refreshSkillSummary(row.skills);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '技能摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 知识库卡摘要计算（2026-09-21 世界书知识库：入参 = knowledge 列原串；'' = 空集合 = 未启用
  // ——解析在 KnowledgeText，与 skills 列同义、与 tools 列相反，故不复用工具计数口径）
  private refreshKnowledgeSummary(knowledgeJson: string): void {
    const count: number = parseEnabledKnowledgeIds(knowledgeJson).length;
    this.knowledgeSummary = count === 0 ? '未启用' : '已启用 ' + count + ' 个知识库';
  }

  // 助手知识库页跳转（2026-09-21 世界书知识库真卡；onPop 重拉摘要——子页 pop 必带 result
  // 坑17 契约；只刷 knowledgeSummary，其余状态独立）
  private openKnowledgePage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_KNOWLEDGE_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row: AssistantRow | null): void => {
          if (row !== null) {
            this.refreshKnowledgeSummary(row.knowledge);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({
            message: '知识库摘要刷新失败：' + (e as Error).message
          });
        });
    });
  }

  // 助手记忆页跳转（2026-09-08 记忆域真卡；onPop 重拉摘要——子页 pop 必带 result 坑17
  // 契约；只刷 memorySummary，其余状态独立）
  private openMemoryPage(): void {
    this.pathStack.pushPathByName(ROUTE_ASSISTANT_MEMORY_PAGE, this.rowId, (): void => {
      queryAssistant(this.rowId)
        .then((row): void => {
          if (row !== null) {
            this.refreshMemorySummary(row);
          }
        })
        .catch((e: Object): void => {
          this.getUIContext().getPromptAction().showToast({ message: '记忆摘要刷新失败：' + (e as Error).message });
        });
    });
  }

  // 高级设定卡摘要重读（advancedParams 列空/'' = 默认；非空 = 已自定义——细摘要在二级
  // 页，本卡只报状态。读取失败 toast 不静默 P0-1）
  private refreshAdvancedSummary(): void {
    queryAssistant(this.rowId)
      .then((row): void => {
        if (row !== null) {
          this.advancedSummary = row.advancedParams === '' ? '默认' : '已自定义';
          this.refreshToolsSummary(row.tools);
        }
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '高级设定摘要读取失败：' + (e as Error).message });
      });
  }

  // 模型卡摘要重读（DB 单一真源：绑定行 + 服务商/模型显示名解析；行/服务商/模型任一
  // 缺失 = '' → 卡面兜底「未选择模型」——删服务商/删模型级联清列后的显示自动跟随；
  // 刷新失败 toast 不静默 P0-1）
  private async refreshModelSummary(): Promise<void> {
    try {
      const row: AssistantRow | null = await queryAssistant(this.rowId);
      if (row === null || row.providerId === '' || row.modelId === '') {
        this.modelSummary = '';
        return;
      }
      const providers: ProviderRow[] = await queryProviders();
      const provider: ProviderRow | undefined =
        providers.find((p: ProviderRow): boolean => p.id === row.providerId);
      if (provider === undefined) {
        this.modelSummary = '';
        return;
      }
      const models: ModelRow[] = await queryModels(provider.id, 'chat');
      const model: ModelRow | undefined =
        models.find((m: ModelRow): boolean => m.modelId === row.modelId);
      if (model === undefined) {
        this.modelSummary = '';
        return;
      }
      const effort: string = row.thinkLevel === '' ? '默认' :
        row.thinkLevel === 'off' ? '关闭' : row.thinkLevel;
      this.modelSummary = (model.name !== '' ? model.name : model.modelId) + ' · 思考 ' + effort;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '模型摘要读取失败：' + (e as Error).message });
    }
  }

  // 助手详情卡（2026-09-01 详情卡轮，领导指令「类似 RikkaHub 助手详情卡」——参考图形态
  // 裁剪：圆形首字大头像 + 助手名 + 右上角编辑键；★ 不做换头像/模型/记忆/技能/知识库
  // 徽章（领导明确裁剪——头像 = 首字圆底形制，无自定义头像；模型/记忆/技能/知识库当前
  // 无数据或功能建设中，卡面保持极简——分区信息在下方各卡）。编辑键逻辑 = 原名称行卡
  // 点击（2026-09-01 按钮区退役轮口径）：square_and_pencil 图标键（坑72 口径，项目内
  // ProviderCardMenu/SessionCardMenu 同符号实锤）→ openRenameDialog 即时落库；★ 内置
  // 默认助手详情卡照显但**不渲染编辑键**（名恒定禁改——反馈轮 3 定稿）。无参 @Builder
  // 内直读 this.name（坑16 家族——值参传递快照不刷新，名称 @State 变更须驱动本卡重建）
  @Builder
  DetailCard() {
    Row({ space: 12 }) {
      // 圆形首字大头像（反馈轮 4 列表卡同形制放大版：官方强调色圆 + 反白字；空名兜底 '?'）
      Text(this.name !== '' ? this.name.substring(0, 1) : '?')
        .fontSize(28)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_on_primary'))
        .width(64)
        .height(64)
        .borderRadius(32)
        .backgroundColor($r('sys.color.ohos_id_color_emphasize'))
        .textAlign(TextAlign.Center)
      Text(this.name)
        .fontSize(DETAIL_CARD_TITLE_FONTSIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      // 右上角编辑键（★ 内置助手不渲染——名恒定禁改，默认与控制台同口径）
      if (!this.isBuiltin()) {
        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor([$r('sys.color.font_secondary')])
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick((): void => {
          this.openRenameDialog();
        })
      }
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
  }

  // 模型设置分区卡（2026-09-01 模型绑定首卡，放详情卡后——领导指令；icon dial 符号表
  // 实锤坑72 口径；★ 动态摘要行——无参 @Builder 内直读 this.modelSummary〔坑16 值参
  // 快照勿改〕；点击进模型设置页，摘要随 onPop 重拉）
  @Builder
  ModelCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.dial'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('模型设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.modelSummary !== '' ? this.modelSummary : '未选择模型')
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openModelSettingsPage();
    })
  }

  // 工具调用分区卡（2026-09-02 工具调用底层真卡——占位清单已摘项；icon 沿用原占位
  // 符号 wrench_and_screwdriver；★ 动态摘要行——无参 @Builder 内直读 this.toolsSummary
  // 〔坑16 值参快照勿改〕；点击进工具页，摘要随 onPop 重拉）
  @Builder
  ToolsCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('工具调用')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.toolsSummary)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openToolsPage();
    })
  }

  // 记忆分区卡（2026-09-08 记忆域真卡——原占位卡摘出转真；icon memory_module 沿用原占位
  // 符号；★ 动态摘要行——无参 @Builder 内直读 this.memorySummary〔坑16 值参快照勿改〕；
  // 点击进助手记忆页，摘要随 onPop 重拉）
  @Builder
  MemoryCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.memory_module'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('记忆')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.memorySummary)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openMemoryPage();
    })
  }

  // 技能分区卡（2026-09-13 技能层真卡——原占位卡摘出转真；icon wand_and_stars 沿用原占位
  // 符号；★ 动态摘要行——无参 @Builder 内直读 this.skillSummary〔坑16 值参快照勿改〕；
  // 点击进助手技能页，摘要随 onPop 重拉）。★ 控制台助手不渲染（一期不开放技能，方案 §2.8
  // #4——发送链另有硬封锁，两处守卫）
  @Builder
  SkillCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.wand_and_stars'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('技能')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.skillSummary)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openSkillPage();
    })
  }

  // 知识库分区卡（2026-09-21 世界书知识库真卡——原占位卡摘出转真〔占位清单最后一项〕；
  // icon bookshelf 沿用原占位符号；★ 动态摘要行——无参 @Builder 内直读 this.knowledgeSummary
  // 〔坑16 值参快照勿改〕；点击进助手知识库页，摘要随 onPop 重拉）
  @Builder
  KnowledgeCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.bookshelf'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('知识库')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.knowledgeSummary)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openKnowledgePage();
    })
  }

  // 高级设定分区卡（2026-09-01 高级设定：原占位卡转真卡——占位清单已摘项；icon
  // gearshape 沿用原占位符号；★ 动态摘要行——无参 @Builder 内直读 this.advancedSummary
  // 〔坑16 值参快照勿改〕；点击进二级页，摘要随 onPop 重拉）
  @Builder
  AdvancedCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('高级设定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.advancedSummary)
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openAdvancedPage();
    })
  }

  // 提示词分区卡（★ 动态摘要行——无参 @Builder 内直读 this.prompt，勿改值参传递〔坑16
  // 按值快照〕；icon doc_text 与设置页提示词行卡同符号）
  @Builder
  PromptCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(20)
        .fontColor([cardTitleColor()])
      Column({ space: 4 }) {
        Text('提示词')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .width('100%')
        Text(this.promptSummary())
          .fontSize(13)
          .fontColor(cardDescColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.openPromptPage();
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 12 }) {
        // ── 助手详情卡（2026-09-01 详情卡轮：圆形头像 + 助手名 + 右上角编辑键；内置助手
        //〔默认/控制台〕同样显示但无编辑键——恒显卡，原「名称行卡」只显示用户助手的口径
        // 同期退役，删除原 if (!this.isDefault()) 包裹）──
        this.DetailCard()

        // ── 模型设置卡（2026-09-01 模型绑定首卡——领导指令；摘要 = 绑定模型 + 思考档位）──
        this.ModelCard()

        // ── 分区卡 ──
        this.PromptCard()
        // ── 工具调用卡（2026-09-02 真卡：原占位位次——提示词之后首张）──
        this.ToolsCard()
        // ── 记忆卡（2026-09-08 记忆域真卡：原占位位次——工具调用之后，占位清单已摘项）──
        this.MemoryCard()
        // ── 技能卡（2026-09-13 技能层真卡：原占位位次——记忆之后，占位清单已摘项；
        //    控制台助手不渲染——一期不开放技能，方案 §2.8 #4）──
        if (this.rowId !== ASSISTANT_CONSOLE_ID) {
          this.SkillCard()
        }
        // ── 知识库卡（2026-09-21 世界书知识库真卡：原占位位次——技能之后；
        //    占位清单已清空退役，六张卡全部转真）──
        this.KnowledgeCard()

        // ── 高级设定卡（2026-09-01 高级设定：原占位位次保持分区末位）──
        this.AdvancedCard()
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
      title: '助手编辑',
      // 右上角无菜单键（纯导航枢纽——保存/重命名/删除均有各自交互位）
      onBackPressed: (): boolean => {
        // 完成返回带 result（坑17「无保存动作」姿势——列表页 onPop reload，覆盖重命名后
        // 的名称刷新；未改动返回 reload 幂等无害）
        this.pathStack.pop({ saved: true });
        return true;
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}

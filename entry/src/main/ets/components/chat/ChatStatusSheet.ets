// 会话状态半模态面板（入口 = 输入框工具行「状态」裸图标键）：收录「本轮生效 + 请求注入」
// 两组只读行卡。面板内容件（不含 bindSheet——宿主 ChatPage 页面根唯一挂载点
// sheetKind='status' 分支，坑64 姿势；规范-半模态 §8「面板内容件」先例）。形制 =
// SessionStatsSheet 同款三件套（HdsNavigation MODAL 壳 + sheetTitleBarOptions +
// bindToScrollable + 底部安全区延伸），滚动容器 clip(false)（规范 §2——渐变模糊要有
// 内容可透）。
// ★ 只读纪律（层界）：全组件零 onClick / 零 Toggle / 零 Button——行 = 「标签左·数值右」
// 只读行（SessionStatsSheet/ContextUsageSheet 同族形制）。切换入口各在其原位不搬家（模型/
// 思考 = 标题栏热区、联网 = 标题栏「更多」菜单、技能 = 附件与提示词面板「技能」卡、提示词 =
// 同面板注入卡）——本面板复制操作面 = 双控制面，禁止。
// ★ 数据三路（禁在面板侧复算判别）：①refs 闭包现读——模型/服务商/思考/指定技能名（页面
// @State）+ ChatStatusSource 整包（提示词生效来源/技能 id 集与封锁/记忆注入与作用域/知识
// 自动注入——单源 = ChatPromptState.statusSource，经 ChatSendCtrl 一枚薄口；面板禁逐项
// 自算）；②AppStorage 现读——联网两键（值键 = 本会话生效值，闸键 = 能力上限，写点见
// ChatPage.refreshWebSearchFlag）；③面板自拉——技能名清单（querySkills +
// selectEnabledSkills 求交，与发送链 buildSkillContext 同函数同语义）；零启用/封锁零查询。
// ★ 用量面（「已用/上限」）不在本面板：归输入条圆环与上下文用量面板（刻意不收，防两处
// 口径漂移；后续要加先回来改本节与 chip 换色判据的边界说明）。
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import {
  cardBg, cardBorderColor, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING, CARD_RADIUS
} from '../../common/Theme';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import {
  CHAT_WEBSEARCH_ALLOWED_KEY, CHAT_WEBSEARCH_ON_KEY, thinkingDisplayLabel
} from './ChatParamChipBar';
import { SkillBriefItem, selectEnabledSkills } from '../../common/SkillText';
import { querySkills, SkillRow } from '../../common/store/SkillDb';
import { MEMORY_SCOPE_ASSISTANT } from '../../common/store/MemoryDb';
import { ChatStatusSource } from '../../common/chat/ChatPromptState';

// 面板数据供给（宿主 ChatPage 注入；全部闭包 = 装载/渲染时现读，禁值参快照——
// CompressPreviewSheet refs 同款姿势。解析单源：页面四值读页面 @State；注入侧整包读
// ChatPromptState.statusSource（经 ChatSendCtrl 一枚薄口）——面板零复算零缓存）
export interface ChatStatusRefs {
  modelLabel: () => string;
  providerLabel: () => string;
  thinkingValue: () => string;
  designatedSkillName: () => string;
  statusSource: () => ChatStatusSource;
}

@Component
export struct ChatStatusSheet {
  // 页面存活守卫：置位后本组件迟到异步回调不写状态、不碰 UI、不上行；写库等数据层意图
  // 照常完成
  private departed: boolean = false;
  refs: ChatStatusRefs = {
    modelLabel: (): string => '',
    providerLabel: (): string => '',
    thinkingValue: (): string => '',
    designatedSkillName: (): string => '',
    statusSource: (): ChatStatusSource => ({
      promptSourceKind: 'none', promptSourceName: '', skillIds: [],
      memoryInjectEnabled: false, memoryScope: '', knowledgeAutoInjectEnabled: false
    })
  };
  onClose: () => void = () => {
  };
  // 底部系统导航条高（vp，宿主 bottomPad 注入——尾部占位，坑66 方案 B）
  bottomInset: number = 0;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 联网两键（AppStorage 自订阅现读；本面板只读——打开面板期间的改值经写点广播自动刷）
  @StorageProp(CHAT_WEBSEARCH_ON_KEY) webSearchOn: boolean = true;
  @StorageProp(CHAT_WEBSEARCH_ALLOWED_KEY) webSearchAllowed: boolean = false;
  // 启用技能名清单（面板自拉）：null = 读取中；[] = 未启用或库内全不存在（当未启用——
  // 与发送链同口径）；非空 = 求交后的名称序（库内序 = 卡片序，querySkills 三键序）
  @State private skillNames: string[] | null = null;
  // 清单读取失败（P0-1 不静默：行值显示「读取失败」，不装「未启用」）
  @State private skillsLoadFailed: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadSkillNames();
  }

  // 技能名装载（开面板一次）：零启用零查询（同发送链 buildSkillContext 短路）；
  // 求交单源 = SkillText.selectEnabledSkills（与发送链同一函数——显示与实际注入同判据）
  private loadSkillNames(): void {
    const src: ChatStatusSource = this.refs.statusSource();
    if (src.skillIds.length === 0) {
      this.skillNames = [];
      return;
    }
    const ids: string[] = src.skillIds;
    querySkills()
      .then((rows: SkillRow[]): void => {
        if (this.departed) {
          return;
        }
        const items: SkillBriefItem[] = [];
        for (const row of rows) {
          items.push({ id: row.id, name: row.name, description: row.description });
        }
        this.skillNames = selectEnabledSkills(items, ids)
          .map((item: SkillBriefItem): string => item.name);
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.skillsLoadFailed = true;
        hilog.warn(0xD5A0, 'ChatStatus',
          '技能清单读取失败（面板按读取失败行显示）：%{public}s', (e as Error).message);
      });
  }

  // ── 行值文案（文案规约：分句句号、无冒号分号连环；单冒号「标签：说明」为允许形态）──
  private modelText(): string {
    const model: string = this.refs.modelLabel();
    return model !== '' ? model : '未选择';
  }

  private providerText(): string {
    const provider: string = this.refs.providerLabel();
    return provider !== '' ? provider : '未解析';
  }

  // 联网三态：助手启用清单不含 search_web = 能力上限未开放（与更多菜单项同判据两键）
  private webText(): string {
    if (!this.webSearchAllowed) {
      return '助手未开放';
    }
    return this.webSearchOn ? '已开启' : '已关闭';
  }

  private designatedText(): string {
    const name: string = this.refs.designatedSkillName();
    return name !== '' ? name : '未指定';
  }

  // 提示词生效来源四源 + 未注入（kind 判别单源在 ChatPromptState，本处只做文案映射）
  private promptText(): string {
    const src: ChatStatusSource = this.refs.statusSource();
    const kind: string = src.promptSourceKind;
    const name: string = src.promptSourceName;
    if (kind === 'template') {
      return name !== '' ? '会话提示词：' + name : '会话提示词';
    }
    if (kind === 'assistant') {
      return name !== '' ? '助手提示词：' + name : '助手提示词';
    }
    if (kind === 'system') {
      return '系统提示词';
    }
    return '未注入';
  }

  // 启用技能行值：零启用 > 读取失败 > 读取中 > 求交结果（空 = 当未启用）
  private skillsText(): string {
    const src: ChatStatusSource = this.refs.statusSource();
    if (src.skillIds.length === 0) {
      return '未启用';
    }
    if (this.skillsLoadFailed) {
      return '读取失败';
    }
    if (this.skillNames === null) {
      return '读取中';
    }
    if (this.skillNames.length === 0) {
      return '未启用';
    }
    return this.skillNames.length + ' 个';
  }

  // 技能名清单行（有名单才显——与行值同拍，不显空行）
  private skillNamesLine(): string {
    if (this.skillNames === null || this.skillNames.length === 0) {
      return '';
    }
    return this.skillNames.join('、');
  }

  private memoryText(): string {
    const src: ChatStatusSource = this.refs.statusSource();
    if (!src.memoryInjectEnabled) {
      return '已关闭';
    }
    return src.memoryScope === MEMORY_SCOPE_ASSISTANT ? '已开启 · 助手独立库' : '已开启 · 全局库';
  }

  private knowledgeText(): string {
    return this.refs.statusSource().knowledgeAutoInjectEnabled ? '已开启' : '已关闭';
  }

  // 卡骨架（SessionStatsSheet.StatCard 同族：标题 15 加粗 + 分割线 + 行距 12 行列）
  @Builder
  CardTitle(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(cardTitleColor())
    Divider()
      .strokeWidth(1)
      .color(cardBorderColor(this.appColorMode))
  }

  // 只读行（标签左·数值右；数值吃余宽右对齐 + 单行省略——防长模型名/长技能名撑破行；
  // 与 SessionStatsSheet.StatRow 同族形制，多出的收窄是为本面板长值面）
  @Builder
  StatRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(cardDescColor())
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(cardTitleColor())
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  // 「本轮生效」卡：模型与服务商 / 思考档位 / 联网搜索 / 本条指定技能
  @Builder
  EffectiveCard() {
    Column({ space: 10 }) {
      this.CardTitle('本轮生效')
      Column({ space: 12 }) {
        this.StatRow('模型', this.modelText())
        this.StatRow('服务商', this.providerText())
        this.StatRow('思考档位', thinkingDisplayLabel(this.refs.thinkingValue()))
        this.StatRow('联网搜索', this.webText())
        this.StatRow('本条指定技能', this.designatedText())
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  // 「请求注入」卡：提示词生效来源 / 启用技能（值 + 名单行） / 记忆注入 / 知识自动注入
  @Builder
  InjectCard() {
    Column({ space: 10 }) {
      this.CardTitle('请求注入')
      Column({ space: 12 }) {
        this.StatRow('提示词', this.promptText())
        this.StatRow('启用技能', this.skillsText())
        if (this.skillNamesLine() !== '') {
          Text(this.skillNamesLine())
            .fontSize(13)
            .fontColor(cardDescColor())
            .width('100%')
        }
        this.StatRow('记忆注入', this.memoryText())
        this.StatRow('知识自动注入', this.knowledgeText())
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(cardBg(this.appColorMode))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: CARD_SPACING }) {
          this.EffectiveCard()
          this.InjectCard()
          // 尾部安全区让位（ignoreLayoutSafeArea BOTTOM 后末卡不贴导航条；Row 空占位——
          // Blank 在部分容器下编译 10905201，规范-半模态 §2 先例用 Row）
          Row()
            .height(this.bottomInset)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 12, bottom: 12 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      // 滚动内容穿透标题栏背后被 GRADIENT_BLUR 模糊采样（规范-半模态 §2：缺省裁剪 = 模糊空转）
      .clip(false)
      .align(Alignment.TopStart)
    }
    .titleBar(sheetTitleBarOptions('会话状态', '当前会话的生效参数与注入', (): void => {
      this.onClose();
    }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}

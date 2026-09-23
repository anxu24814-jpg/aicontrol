// 聊天页「附件与提示词」半模态面板域（2026-08-30 提示词注入新建；二改按领导指令
// 「留卡占位与旧项目 UI 完全一致；卡片形状位置照 old；顶部渐变模糊必须有——先研读旧项目
// 沉淀与代码再动手」）——本实现自 dshinhm 半模态沉淀（docs/kimi重写/半模态实践沉淀与
// 最后实现.md）+ FileSheet/KimiChatPage 代码对照复刻：
// · 壳 = 声明式 bindSheet（页面根）+ HdsNavigation MODAL 标题栏 + sheetTitleBarOptions
//  （主副标题粗体左对齐 / xmark 圆钮关闭 / AUTO 分割线 / **静止渐变模糊** + 标题栏 HDS
//   材质随沉浸光感总档——KimiSheetCommon 随迁版一字同源）；
// · ★ 动态模糊生效前提（沉淀「列表类」节）：滚动容器 List **clip(false)**——滚动内容穿透
//   标题栏背后，GRADIENT_BLUR 才能透出内容（上一版 Scroll 默认裁剪 = 模糊无内容可透 =
//   领导实测「顶部没渐变模糊」根因）；
// · 面板一（照 FileSheet 第一图）：上排**三格方卡**（SheetGridOption 规格：图标上+文字下、
//   圆角 20、高 88、cardBg 底、layoutWeight(1) 三等分）——camera 拍照 / picture 照片 /
//   folder 系统文件（三符号旧项目真机实锤——坑72 口径；2026-08-31 附件上传接线：三卡
//   点击上行 onPick(kind) → 页面交 AttachmentPickCtrl 拉选择器，面板保持打开——dshinhm
//   FileSheet 同款行为）= 三入口与旧项目一致；下排 = 提示词注入卡（HdsListItemCard：
//   PrefixIcon + 主标题 + 副标题 + **SuffixText 右侧状态文字**——旧项目 SheetRunParamCard
//   形态：状态「未使用/当前：xx」）→ 点击进选词面板；★控制台助手会话封锁（2026-09-05
//   决明拍板）：归属 = 内置控制台助手时点击本卡 toast 拒绝不进选词面板，卡状态恒显
//   「不可用」——注入恒走其内置只读路由提示词（语义侧封锁在 ChatPromptState.resolveInject，
//   UI/语义两侧同口径防旁路）；
// · 面板二（照 CommandPanel 第二图）：列表卡行（自制行卡：
//   图标 + 主 = 模板名 / 副 = 内容摘要（系统提示词行副标题 = 「系统提示词（默认）」）+
//   ★ 右侧官方开关（2026-08-31 领导指令：去「使用中」提示改开关——单注入语义：互斥
//   单选，已有一个开关开启再开另一个 → toast「不支持注入多提示词」拒绝（开关弹回，由
//   ForEach 键含开关纪元重建回弹——Toggle 非受控）；点行卡不再启用（启用逻辑删除），
//   由开关控制；★2026-09-04 归属与注入解耦：关掉当前开启的开关 = 清引用回退**归属
//   助手提示词**（原「回退系统提示词」随单注入互斥撤销）；未选任何模板 = 注入归属
//   助手提示词）；选中 → 有行会话 updateConversationPromptId 落库
//   （引用跟随即时生效）、无行会话（新会话/隐私会话，2026-09-04 开放）跳库上行内存
//   覆盖（ChatPromptState.promptOverride）→ onPromptChanged 上行 + 回面板一；同
//   bindSheet 实例内容切换（dshinhm 命令卡先例）；
// · 面板三（2026-09-01 助手域）：助手选择（AssistantSheetPanel.ets——行卡+开关同面板二
//   交互语言，单选/拒绝 toast/纪元弹回同款）；★ 2026-09-04 归属与注入解耦（决明拍板）：
//   助手 = 会话恒归属（行显式绑定 ?? 面板覆盖 ?? 当前助手 ?? 内置默认助手），提示词注入 =
//   独立开关——选助手不再清提示词引用、选提示词不再清助手引用，两卡状态可并存；注入
//   优先级 = 会话提示词 > 助手提示词 > 系统提示词（解析在 ChatPromptState）；选择完成经
//   onPromptChanged 双参上行（2026-09-04：promptId + assistantId，未变化侧传当前值——
//   页面透传两覆盖 + 刷新注入缓存）；三格附件方卡 2026-09-01
//   曾域拆 AttachGridRow.ets（当日
//   超线拆分）——同日宪法修订（600 软引导 / 1000 硬线 + 反碎片下限）后反碎片并回本文件
//  （单消费方、同域「附件与提示词面板」，行为原样）。
// · 数据自持有（aboutToAppear 自拉——每次打开重建即重拉，无陈旧缓存面）。
import { TextModifier } from '@kit.ArkUI';
import {
  HdsListItemCard, HdsNavigation, HdsNavigationTitleMode, PrefixIcon, SuffixText
} from '@kit.UIDesignKit';
import { cardBg, cardDescColor, cardTitleColor, CARD_PANEL_WIDTH, CARD_SPACING } from '../../common/Theme';
import { IMMERSIVE_LEVEL_KEY } from '../../common/ImmersiveLevel';
import { sheetTitleBarOptions } from './KimiSheetCommon';
import { FilePickKind } from './AttachmentPickCtrl';
import { AssistantSheetPanel } from './AssistantSheetPanel';
import { PromptPickPanel } from './PromptPickPanel';
import {
  ASSISTANT_CONSOLE_ID, ASSISTANT_DEFAULT_ID, queryAssistant, queryConversationAssistantId
} from '../../common/store/AssistantDb';
import {
  PromptTemplateRow, queryConversationPromptId, queryTemplates
} from '../../common/store/PromptTemplateDb';
import { ConfigurationConstant } from '@kit.AbilityKit';

// ═══ 三格附件方卡行（2026-09-01 自 AttachGridRow.ets 并回——当日拆出/当日并回，纯 UI
// 哑组件零状态，行为原样搬迁）═══
// 拍照 / 照片 / 系统文件三格（SheetGridOption 规格照旧项目一字不差：图标上+文字下、
// 圆角 20、高 88、cardBg 底、layoutWeight(1) 三等分）；外观官方正色（icon_primary /
// cardTitleColor——旧项目同款，深浅色随动）；点击上行 onPick 拉系统选择器（面板保持
// 打开，附件条在胶囊内可见——dshinhm FileSheet 同款行为）。★ 对齐（旧项目 FileSheet
// 同款）：本行自带左右 padding 16——HDS 卡官方宽度语义 = 容器 −32，两端齐平不双重收窄。
@Component
struct AttachGridRow {
  // 附件入口上行（页面交 AttachmentPickCtrl 拉选择器）
  onPick: (kind: FilePickKind) => void = () => {
  };
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // 单格方卡（图标上 + 文字下）
  @Builder
  Grid(icon: Resource, label: string, kind: FilePickKind) {
    Button() {
      Column({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([$r('sys.color.icon_primary')])
        Text(label)
          .fontSize(14)
          .fontColor(cardTitleColor())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .type(ButtonType.Normal)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(20)
    .layoutWeight(1)
    .height(88)
    .onClick((): void => {
      this.onPick(kind);
    })
  }

  build() {
    Row({ space: 8 }) {
      this.Grid($r('sys.symbol.camera'), '拍照', 'camera')
      this.Grid($r('sys.symbol.picture'), '照片', 'photo')
      this.Grid($r('sys.symbol.folder'), '系统文件', 'file')
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct ChatPromptSheet {
  // 目标会话 id（页面透传；进入即加载，创建后不变——坑30 口径）
  @Prop conversationId: string = '';
  // 底部避让区高（面板内容底部让位）
  @Prop bottomInset: number = 0;
  // 面板底部留白（BottomInset + 固定 24——面板形态内容不贴手势条）
  private bottomPadInset: number = 0;
  // 深浅色（卡片底色 cardBg 函数驱动；EntryAbility 写键）
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 标题栏材质档位（@StorageProp 自订阅——面板壳同 dshinhm 姿势，页面无需透传）
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 选择变化上行（2026-09-04 双参签名：promptId / assistantId = 两面板各自选中值，未变化
  // 侧传本卡当前值——ChatPage 透传 ChatSendCtrl 两覆盖 + 刷新注入缓存——立即生效；
  // 归属与注入并存，无互斥清空；'' = 关闭侧（注入关 / 归属回退默认——面板三关闭非默认卡
  // 上行默认 id，'' 仅初始未选防御）
  onPromptChanged: (promptId: string, assistantId: string) => void = () => {
  };
  // 会话无行兜底归属（页面下发，创建期同步值——坑30 口径）：仅会话行不存在（新会话或隐私
  // 会话）时主面板「助手」卡与助手面板的显示态（= 有效归属 = 面板覆盖 ?? 当前助手 ?? 内置
  // 默认助手——存量 '' 行由行侧解析为默认助手，不经本值，2026-09-04 晚定稿）
  @Prop assistantBound: string = '';
  // 会话提示词引用覆盖（2026-09-04 隐私会话开放提示词选择，页面下发创建期同步值）：
  // 会话行不存在（新会话/隐私）时主面板「提示词注入」卡显示态（无行无库可查——覆盖 =
  // 注入真源）
  @Prop promptBound: string = '';
  // 本轮指定技能名（2026-09-16 单条消息指定技能，页面下发创建期同步值——本页只显示态：
  // '' = 未指定 → 副标题「未指定」；非空 → 「下一条消息：X」。真源在 ChatPage 两 @State）
  @Prop designateName: string = '';
  // 「技能」卡点击上行（2026-09-16 单条消息指定技能）：零参——先关面板再 push 指定页由
  // ChatPage 完成（面板不自推）；控制台封锁咽喉点在 openSkillPage（toast 拒绝后不上行）
  onOpenSkillPage: () => void = () => {
  };
  // 附件三卡入口上行（2026-08-31 附件上传：拍照/照片/系统文件——页面交
  // AttachmentPickCtrl 拉系统选择器；面板保持打开，附件条在胶囊内可见）
  onPick: (kind: FilePickKind) => void = () => {
  };
  // 面板关闭上行（页面置 sheetKind='none'）
  onClose: () => void = () => {
  };
  // 面板内容（'main' 主面板 / 'pick' 选词面板 / 'assistant' 助手面板——同 bindSheet 实例
  // 切换；选词/助手列表数据与开关逻辑在各自域件内自持有）
  @State private panelMode: string = 'main';
  @State private templates: PromptTemplateRow[] = [];
  @State private currentId: string = '';
  @State private currentName: string = '';
  // 会话当前助手（主面板「助手」卡状态显示；2026-09-01 助手域）
  @State private assistantId: string = '';
  @State private assistantName: string = '';
  // 滚动控制器（选词/助手面板 List 共用——标题栏 bindToScrollable 绑渐变模糊；随 dshinhm
  // 面板壳姿势）
  private scroller: Scroller = new Scroller();
  // 官方 HDS 列表卡可用性（HdsListItemCard 要求 HDSComponent.Full——SettingsPage 同款门槛）
  private hdsListCardAvailable: boolean = canIUse('SystemCapability.UIDesign.HDSComponent.Full');

  aboutToAppear(): void {
    this.bottomPadInset = this.bottomInset + 24;
    this.reload();
  }

  private reload(): void {
    queryTemplates()
      .then((rows: PromptTemplateRow[]): void => {
        this.templates = rows;
      })
      .catch((): void => {
        this.templates = [];
      });
    // 会话行三态为枢（2026-09-04 提示词卡无行显示态随行）：有行 = 两卡读行内引用
    //（既有链）；无行（新会话/隐私会话）= 助手卡显 assistantBound、提示词卡显
    // promptBound（页面下发内存覆盖 = 注入真源，无行无库可查）
    queryConversationAssistantId(this.conversationId)
      .then((assistantId: string | null): Promise<void> | void => {
        const noRow: boolean = assistantId === null;
        // 有效归属（主面板「助手」卡状态；名称经 queryAssistant 取——查不到 = 已删防御
        // 显空）：行显式绑定优先；行 ''（存量未绑定）= 内置默认助手；null（无行新会话）→
        // 页面下发 assistantBound（= 面板覆盖 ?? 当前助手 ?? 默认助手——★2026-09-04 晚定稿
        // 恒显式归属，提示词注入开关不影响本卡显示）
        const shownId: string = assistantId !== null && assistantId !== '' ? assistantId :
          (assistantId === null ? this.assistantBound : ASSISTANT_DEFAULT_ID);
        this.assistantId = shownId;
        if (shownId === '') {
          this.assistantName = '';
        } else {
          queryAssistant(shownId)
            .then((row): void => {
              this.assistantName = row !== null ? row.name : '';
              if (row === null) {
                this.assistantId = '';
              }
            })
            .catch((): void => {
              this.assistantName = '';
            });
        }
        if (noRow) {
          this.currentId = this.promptBound;
          this.currentName = this.promptBound !== '' ? this.nameOf(this.promptBound) : '';
          return;
        }
        return queryConversationPromptId(this.conversationId)
          .then((promptId: string): void => {
            this.currentId = promptId;
            this.currentName = promptId === '' ? '' : this.nameOf(promptId);
          });
      })
      .catch((): void => {
        this.assistantId = '';
        this.assistantName = '';
        this.currentId = '';
        this.currentName = '';
      });
  }

  private nameOf(promptId: string): string {
    for (const row of this.templates) {
      if (row.id === promptId) {
        return row.name;
      }
    }
    return '';
  }

  // 选词面板选中上行（PromptPickPanel 域件）：更新主面板提示词卡状态 + onPromptChanged
  // 通知页面重载注入缓存 + 回主面板；★2026-09-04 解耦：不再互斥清助手（归属侧传当前值，
  // 两卡并存）
  private onPromptPicked(promptId: string, promptName: string): void {
    this.currentId = promptId;
    this.currentName = promptId === '' ? '' : promptName;
    this.panelMode = 'main';
    this.onPromptChanged(promptId, this.assistantId);
  }

  // ── 面板一：三格附件方卡（AttachGridRow 域件——2026-09-01 拆出）+ 助手卡 + 提示词注入卡 ──
  @Builder
  MainPanel() {
    Column({ space: CARD_SPACING }) {
      // 三格方卡（域件自带左右 padding 16——两端齐平不双重收窄，规格照旧项目一字不差）
      AttachGridRow({
        onPick: (kind: FilePickKind): void => {
          this.onPick(kind);
        }
      })

      // 助手卡（2026-09-01 助手域；★2026-09-04 归属定稿：恒显式归属 = 行绑定 ?? 行 '' 默认
      // 兜底 ?? 无行有效归属——状态恒「使用中」；副标题当前归属助手名；点击进面板三选择；
      // 注入优先级见 ChatPromptState——本卡与提示词注入卡可并存）
      if (this.hdsListCardAvailable) {
        HdsListItemCard({
          prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.person') } }),
          textItem: {
            primaryText: { text: '助手' },
            secondaryText: { text: this.assistantId !== '' ?
              '当前使用：' + this.assistantName : '未使用（默认助手兜底）' }
          },
          suffixItem: new SuffixText({
            text: this.assistantId !== '' ? '使用中' : '未使用',
            modifier: new TextModifier().fontColor($r('sys.color.font_tertiary'))
          }),
          cardHeight: 72,
          cardBorderRadius: 16,
          cardBackgroundColor: cardBg(this.appColorMode),
          onClick: (): void => {
            this.panelMode = 'assistant';
          }
        })
      } else {
        this.SelfListCard('助手',
          this.assistantId !== '' ? '当前使用：' + this.assistantName : '未使用（默认助手兜底）',
          $r('sys.symbol.person'),
          (): void => {
            this.panelMode = 'assistant';
          })
      }

      // 提示词注入卡（旧项目 SheetRunParamCard 同款：PrefixIcon + 主副标题 + SuffixText
      // 右侧状态文字——「未使用」/「当前：xx」；★2026-09-04 解耦：= 独立注入开关——
      // 开 = 模板覆盖（本会话不注入归属助手提示词）；关 = 注入归属助手提示词——与助手卡
      // 状态可并存，切换经各自面板开关一次完成；★2026-09-05 控制台助手封锁：归属 =
      // 控制台助手时状态恒显「不可用」（显示态经 injectSubtitle/injectSuffix 与门闩同源，
      // 存量引用不假显「使用中」），点击 toast 拒绝——咽喉点在 openPick）
      if (this.hdsListCardAvailable) {
        HdsListItemCard({
          prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.doc_text') } }),
          textItem: {
            primaryText: { text: '提示词注入' },
            secondaryText: { text: this.injectSubtitle() }
          },
          suffixItem: new SuffixText({
            text: this.injectSuffix(),
            modifier: new TextModifier().fontColor($r('sys.color.font_tertiary'))
          }),
          cardHeight: 72,
          cardBorderRadius: 16,
          cardBackgroundColor: cardBg(this.appColorMode),
          onClick: (): void => {
            this.openPick();
          }
        })
      } else {
        this.SelfListCard('提示词注入',
          this.injectSubtitle(),
          $r('sys.symbol.doc_text'),
          (): void => {
            this.openPick();
          })
      }

      // 技能卡（2026-09-16 单条消息指定技能，第四件——「本条消息」家族聚拢在下）：副标题两态
      //（未指定 / 下一条消息：X）+ SuffixText 状态字；点击关面板进技能选择页（点一件即指定，
      // 只对本轮生效、发完自动清，不落库）。★ 三侧不对称注释：模型 = 可越过助手且随会话存续 /
      // 联网 = 上限不可越过 / 技能 = 只此一轮不落库——三者不同构是**刻意的**（技能是用户自写
      // 的惰性说明书，只占清单 token 不引入新调用面），防后续自检「顺手统一」
      if (this.hdsListCardAvailable) {
        HdsListItemCard({
          prefixItem: new PrefixIcon({ iconValue: { symbol: $r('sys.symbol.wand_and_stars') } }),
          textItem: {
            primaryText: { text: '技能' },
            secondaryText: { text: this.skillSubtitle() }
          },
          suffixItem: new SuffixText({
            text: this.skillSuffix(),
            modifier: new TextModifier().fontColor($r('sys.color.font_tertiary'))
          }),
          cardHeight: 72,
          cardBorderRadius: 16,
          cardBackgroundColor: cardBg(this.appColorMode),
          onClick: (): void => {
            this.openSkillPage();
          }
        })
      } else {
        this.SelfListCard('技能',
          this.skillSubtitle(),
          $r('sys.symbol.wand_and_stars'),
          (): void => {
            this.openSkillPage();
          })
      }
    }
    .width('100%')
    .padding({ top: 20, bottom: this.bottomPadInset })
  }

  // 注入卡显示态（2026-09-05 控制台助手封锁，与 openPick 门闩同源判定）：归属 = 控制台
  // 助手时固定「不可用」——即便会话残留存量引用，发送也不再消费（ChatPromptState 封锁
  // 同口径），不假显「当前使用：xx / 使用中」
  private isConsoleBound(): boolean {
    return this.assistantId === ASSISTANT_CONSOLE_ID;
  }

  private injectSubtitle(): string {
    if (this.isConsoleBound()) {
      return '控制台助手固定使用内置帮助指引';
    }
    return this.currentId !== '' ? '当前使用：' + this.currentName : '未使用（发送时用助手提示词）';
  }

  private injectSuffix(): string {
    return this.isConsoleBound() ? '不可用' : (this.currentId !== '' ? '使用中' : '未使用');
  }

  // 打开选词面板（面板数据/开关逻辑在 PromptPickPanel 域件内自持有——每次打开重建即
  // 重拉播种开关态；滚动归零由域件 aboutToAppear 处理）。
  // ★ 控制台助手封锁（2026-09-05 决明拍板）：归属 = 内置控制台助手时点击注入卡 toast
  // 拒绝不进选词面板——HDS 卡与回退卡两变体共走本咽喉点；toast 按新码纪律走 UIContext
  // 形态。文案口径与帮助中心「控制台助手」条目一致
  private openPick(): void {
    if (this.isConsoleBound()) {
      this.getUIContext().getPromptAction().showToast(
        { message: '控制台助手不开放提示词注入，发送时固定使用内置帮助指引' });
      return;
    }
    this.panelMode = 'pick';
  }

  // 技能卡显示态（2026-09-16 单条消息指定技能）：有指定 → 「下一条消息：X」（X = 技能名，
  // 页面下发）；未指定 → 「未指定」；控制台助手 → 恒「控制台助手不开放技能」（与注入卡同
  // 口径——链路侧 skillBlocked 压掉指定，双层防旁路）
  private skillSubtitle(): string {
    if (this.isConsoleBound()) {
      return '控制台助手不开放技能';
    }
    return this.designateName !== '' ? '下一条消息：' + this.designateName : '未指定';
  }

  private skillSuffix(): string {
    if (this.isConsoleBound()) {
      return '不可用';
    }
    return this.designateName !== '' ? '已指定' : '未指定';
  }

  // 打开技能选择页（2026-09-16 单条消息指定技能，「技能」卡咽喉点）：控制台封锁照 openPick
  // 同姿势（toast 拒绝不上行——链路侧 ChatPromptState.skillBlocked 压掉指定，UI/语义两侧
  // 同口径防旁路；文案口径与帮助中心「控制台助手」条目一致）。零参上行——关面板与 push
  // 由 ChatPage 完成
  private openSkillPage(): void {
    if (this.isConsoleBound()) {
      this.getUIContext().getPromptAction().showToast(
        { message: '控制台助手不开放技能，发送时固定不使用技能' });
      return;
    }
    this.onOpenSkillPage();
  }

  // 回退自制行卡（SettingsPage 回退分支同款式；宽度 CARD_PANEL_WIDTH = 容器 −32——
  // 面板容器不设左右边距，与 HDS 卡 −32 语义同宽对齐）。图标经参数传入（2026-09-16：第四卡
  // 与助手/注入卡两变体要求不同图标，硬编码 doc_text 收为形参——两既有调用点同步传各自现值）
  @Builder
  SelfListCard(title: string, subtitle: string, icon: Resource, onTap: () => void) {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([cardTitleColor()])
        Column({ space: 2 }) {
          Text(title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(cardTitleColor())
          Text(subtitle)
            .fontSize(13)
            .fontColor(cardDescColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .type(ButtonType.Normal)
    .width(CARD_PANEL_WIDTH)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .onClick((): void => {
      onTap();
    })
  }

  build() {
    HdsNavigation() {
      if (this.panelMode === 'main') {
        Scroll() {
          this.MainPanel()
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        // 模糊穿透（内容滚入标题栏背后——沉淀「列表类」同款；面板一内容短，标配一致兜底）
        .clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
      } else if (this.panelMode === 'pick') {
        // 面板二：选词（PromptPickPanel 域件自持有数据与开关逻辑；scroller 传引用共用——
        // 标题栏 bindToScrollable 渐变模糊）
        PromptPickPanel({
          conversationId: this.conversationId,
          currentId: this.currentId,
          bottomPadInset: this.bottomPadInset,
          scroller: this.scroller,
          onPicked: (promptId: string, promptName: string): void => {
            this.onPromptPicked(promptId, promptName);
          }
        })
      } else {
        // 面板三：助手选择（AssistantSheetPanel 自持有数据；选择完成上行回主面板并刷新
        // 注入缓存——onPromptChanged 同一通道，页面侧零新增回调；scroller 共用同上）
        AssistantSheetPanel({
          conversationId: this.conversationId,
          // ★ 2026-09-04 自检修复（决明实测「切 B 后重进面板显示默认开」）：boundId 必须传
          // 本组件 @State 有效归属而非 @Prop assistantBound——后者是半模态打开时刻快照，
          // 选 B 后 ChatPage 无 @State 变化不重建 → @Prop 不刷新 → 重新播种旧值（坑30/坑75
          // 族值参快照）；@State assistantId 经 onPicked 即时更新；'' 窗口（reload 未定）
          // 回落 @Prop 快照防初始闪空
          boundId: this.assistantId !== '' ? this.assistantId : this.assistantBound,
          bottomPadInset: this.bottomPadInset,
          scroller: this.scroller,
          onPicked: (assistantId: string, assistantName: string): void => {
            // 面板三上行恒非空（2026-09-04 晚定稿：关闭非默认卡 = 回退默认 id，'' 不再
            // 上行）——'' 分支仅防御保留（异常上行）：显示兜底有效归属 + 异步取名，覆盖
            // 上行仍传原值
            const shownId: string = assistantId !== '' ? assistantId : this.assistantBound;
            this.assistantId = shownId;
            if (assistantId === '') {
              queryAssistant(this.assistantBound)
                .then((row): void => {
                  this.assistantName = row !== null ? row.name : '';
                })
                .catch((): void => {
                  this.assistantName = '';
                });
            } else {
              this.assistantName = assistantName;
            }
            // 2026-09-04 解耦：归属选中不再清提示词引用——注入侧传当前值，两卡并存
            this.panelMode = 'main';
            this.onPromptChanged(this.currentId, assistantId);
          }
        })
      }
    }
    // 标题栏（旧项目面板壳同款：主副标题 + xmark 关闭 + AUTO 分割线 + 静止渐变模糊 +
    // 材质随沉浸光感总档——KimiSheetCommon.sheetTitleBarOptions 随迁版，勿另写）
    .titleBar(sheetTitleBarOptions(
      this.panelMode === 'main' ? '附件与提示词' : this.panelMode === 'pick' ? '选择提示词' : '选择助手',
      this.panelMode === 'main' ? '添加附件、绑定助手或注入提示词到当前会话' :
        this.panelMode === 'pick' ? '选择一个提示词注入本会话' : '选择一个助手绑定本会话',
      (): void => {
        this.onClose();
      }, this.immersiveLevel))
    .titleMode(HdsNavigationTitleMode.MODAL)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}

// 记忆导入页：记忆库管理页「更多」→「从其他平台导入」push 的三级页——复制提示词 → 外部 AI
// 平台生成 → 粘贴回来 →「AI 整理」→ 条目预览确认 → 批量写入当前库（写入前自动留可回退快照）。
// · 三态单页（'paste' → 'loading' → 'preview'）有意为之：整理结果是页内上下文，省一次跨页
//   传参，「返回重来」只需一次赋值而不是退栈再进。
// · push 参数 MemoryImportParam 单源在 MemoryLibraryPage.ets，本页只 import 禁复写（字段漂移
//   编译不报错，undefined 被兜到 'global' 会静默写进全局库，D3-5 事故同族）。
// · 模型归属 =「记忆提取」两键，本页不做页内换模型（会隐式改写共享键）；配置唯一真源在功能
//   模型页，未配置时 startPrepare 前置拦截，modelId 镜像只供该判据。
// · 页面文字键一律走内容区 fallbackButton* 四件套双态（主键 primary=true 强调蓝恒白字，次钮
//   false）；次钮底色按**所坐的面**分叉：「复制提示词」「返回重来」坐 page_bg 无卡体 →
//   fallbackButtonBgOffCard 白底（决明「把背景上的灰底键改为白底，卡片内不动」）。
// · **页级块一律挂 CARD_PANEL_WIDTH**（宿主滚动列无左右 padding，左右收窄责任在页级块，写
//   '100%' 会贴屏缘）：输入区三行、主键、页级次钮、预览态双键 Row。**只有卡内子元素**才写
//   width('100%')（规范-列表卡片与组卡 §4.3）；★ 勿套宽度壳再给子元素挂 CARD_PANEL_WIDTH。
// · alive 守卫：aboutToDisappear 置 false，异步结果回来先判——已离开即丢弃结果、不落库、不
//   提示、不 pop（退出导入页 = 放弃本次导入）；同钩子复位三态与在途闸防残留。
// · importing 落库在途闸（域侧闸只盖 prepare 不盖 apply）：apply 是单句柄全局事务，落库键
//   落库期间无视觉变化，连点即嵌套 beginTransaction 抛错；在途禁用落库/删除/返回三键。
// · 本页不自行刷库列表（无列表数据源）：落库链内已广播，父页 onPop 重拉兜底。
// 事务、容量二次校验、存档与广播次序全在 common/MemoryImport.ets
import { pasteboard } from '@kit.BasicServicesKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { bumpBusyOverlay, confirmLeaveBusyPage, releaseBusyOverlay } from '../BusyOverlay';
import { ROUTE_MEMORY_IMPORT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_HEADER_GAP, SECTION_TITLE_FONTSIZE,
  cardBg, cardDescColor, cardTitleColor, CARD_RADIUS
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import { InfoCard } from '../InfoCard';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonBgOffCard, fallbackButtonFont,
  fallbackButtonMaterial, fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { MEMORY_FULL_TIP, MemoryModelPick, resolveMemoryModel } from '../../common/MemoryGen';
import {
  applyMemoryImport, MEMORY_IMPORT_EXTERNAL_PROMPT, MEMORY_IMPORT_INPUT_MAX,
  MEMORY_IMPORT_STATUS_CONFIG, MEMORY_IMPORT_STATUS_FAILED, MEMORY_IMPORT_STATUS_INSERTED,
  MEMORY_IMPORT_STATUS_LIMIT, MEMORY_IMPORT_STATUS_NONE, MEMORY_IMPORT_STATUS_READY,
  MEMORY_IMPORT_STATUS_TOO_LARGE, MemoryImportPlan, MemoryImportResult, prepareMemoryImport
} from '../../common/MemoryImport';
import { MEMORY_SCOPE_GLOBAL } from '../../common/store/MemoryDb';
// push 参数载体（声明单源在 MemoryLibraryPage.ets，禁本地复写——见文件头）
import { MemoryImportParam } from './MemoryLibraryPage';

const STAGE_PASTE: string = 'paste';
const STAGE_LOADING: string = 'loading';
const STAGE_PREVIEW: string = 'preview';

// 模型未配置提示（与库管理页「立即整理」逐字同句，禁另写）
const IMPORT_NO_MODEL_TIP: string = '请先在功能模型页的「记忆提取」卡选择模型';

@Component
export struct MemoryImportPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 目标库（aboutToAppear 从 push param 解析；缺省 'global' 全局库 / 助手 id = 助手库）
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  @State private stage: string = STAGE_PASTE;
  // 粘贴文本（「返回重来」时保留）
  @State private pasteText: string = '';
  // 生效模型 id 镜像（主键前置判定用；aboutToAppear / onShown 现读）
  @State private modelId: string = '';
  // 待导入条目（预览态本地清单——删除只改本数组，**不写库**）
  @State private items: string[] = [];
  // 库剩余容量不足被丢弃的条数（0 = 没丢；预览态据此出说明行）
  @State private truncated: number = 0;
  // 落库在途闸：apply 是单句柄全局事务（MemoryDb 申报不得嵌套），连点即嵌套 beginTransaction
  // 抛错；域侧 in-flight 只盖 prepare 不盖 apply，故闸设本页——在途禁用落库/删除/返回三键
  // （在途删条会让「已导入 N 条」的 N 与所见不符）并显「正在导入」行。
  @State private importing: boolean = false;
  // 页面存活守卫（见文件头；普通成员不驱动 UI）
  private alive: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    // push param 解析（对象形态 { libraryId }；缺省/异常 = 全局库兜底）
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_MEMORY_IMPORT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last !== null && typeof last !== 'string') {
      const parsed = last as MemoryImportParam;
      if (typeof parsed.libraryId === 'string' && parsed.libraryId !== '') {
        this.libraryId = parsed.libraryId;
      }
    }
    this.reloadModel();
  }

  aboutToDisappear(): void {
    // 离开 = 放弃本次导入（见文件头）；复位三态与在途闸防残留
    this.alive = false;
    this.stage = STAGE_PASTE;
    this.items = [];
    this.truncated = 0;
    this.importing = false;
  }

  // 生效模型现读（缺一键即未配置；主键前置判定用）
  private reloadModel(): void {
    const picked: MemoryModelPick = resolveMemoryModel();
    this.modelId = picked.providerId !== '' && picked.modelId !== '' ? picked.modelId : '';
  }

  // 复制提示词（失败 toast 不静默——ModelEditPage.copyModelId 同款）
  private copyExternalPrompt(): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, MEMORY_IMPORT_EXTERNAL_PROMPT);
    pasteboard.getSystemPasteboard().setData(data)
      .then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '已复制' });
      })
      .catch((e: Object): void => {
        this.getUIContext().getPromptAction().showToast({ message: '复制失败：' + (e as Error).message });
      });
  }

  // ── 整理（主键）：前置两拦 + 置「整理中」+ 调 prepare 链（结果回来先判 alive）──
  private startPrepare(): void {
    if (this.stage === STAGE_LOADING) {
      return; // 键已禁用，此处兜底防连点
    }
    if (this.pasteText.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先粘贴内容' });
      return;
    }
    if (this.modelId === '') {
      // 模型未配置 = 不可导入（与「立即整理」同口径）；起请求前拦，不让用户白等
      this.getUIContext().getPromptAction().showToast({ message: IMPORT_NO_MODEL_TIP });
      return;
    }
    this.stage = STAGE_LOADING;
    // 执行段遮罩 + 拦返回（finally 归还令牌）；离开 = alive 丢弃结果 = 放弃本次导入，
    // 离开文案与帮助中心同口径
    const busyToken: number =
      bumpBusyOverlay('正在整理记忆', '现在离开，等于放弃本次导入，已写入的条目不受影响。');
    prepareMemoryImport(this.pasteText, this.libraryId)
      .then((plan: MemoryImportPlan): void => {
        // ★ alive 守卫：已离开即丢弃结果——不落库、不提示、不 pop
        if (!this.alive) {
          return;
        }
        if (plan.status === MEMORY_IMPORT_STATUS_READY) {
          this.items = plan.items;
          this.truncated = plan.truncated;
          this.stage = STAGE_PREVIEW;
          return;
        }
        // 其余态一律回粘贴态（文本保留可直接重试）
        this.stage = STAGE_PASTE;
        const tip: string = this.planToastText(plan.status);
        if (tip !== '') {
          this.getUIContext().getPromptAction().showToast({ message: tip });
        }
      })
      .catch((e: Object): void => {
        // 域内已吞错（失败落 failed 态），此处只兜「连结果对象都没拿到」的意外
        if (!this.alive) {
          return;
        }
        this.stage = STAGE_PASTE;
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请稍后重试' });
      })
      .finally((): void => {
        releaseBusyOverlay(busyToken);
      });
  }

  // 整理结果态 → 提示（'' = 不提示）；skipped（库未就绪/总开关关/在途重复）沉默——用户无事
  // 可做。limit 复用 MEMORY_FULL_TIP（与「＋」新建、立即整理同一句）。
  private planToastText(status: string): string {
    if (status === MEMORY_IMPORT_STATUS_LIMIT) {
      return MEMORY_FULL_TIP;
    }
    if (status === MEMORY_IMPORT_STATUS_FAILED) {
      return '导入失败，请稍后重试';
    }
    if (status === MEMORY_IMPORT_STATUS_NONE) {
      return '未整理出可导入的记忆条目';
    }
    if (status === MEMORY_IMPORT_STATUS_CONFIG) {
      return IMPORT_NO_MODEL_TIP;
    }
    if (status === MEMORY_IMPORT_STATUS_TOO_LARGE) {
      // 双保险（输入框 maxLength 已拦一次，程序化写入/旧草稿才走到这里）
      return '粘贴内容过长，请控制在 ' + MEMORY_IMPORT_INPUT_MAX + ' 字以内';
    }
    return '';
  }

  // 预览态删一条（只改本地数组，不写库）
  private removeItem(index: number): void {
    if (this.importing) {
      return; // 在途闸兜底（落库读本清单，删条会让提示条数与所见不符）
    }
    const next: string[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (i !== index) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
  }

  // 返回重来（回粘贴态，保留文本——多半只想改几个字再试）
  private backToPaste(): void {
    this.stage = STAGE_PASTE;
  }

  // ── 落库（主键「导入 N 条」）：失败一律留在预览态、不得 pop（条目清单保留可重试）──
  private doImport(): void {
    if (this.importing) {
      return; // 在途闸兜底（嵌套事务的唯一防线）
    }
    if (this.items.length === 0) {
      return; // 空清单主键已禁用，此处兜底
    }
    const planned: number = this.items.length;
    this.importing = true;
    // 执行段遮罩 + 拦返回（finally 归还令牌；落库写入不受离开影响）
    const busyToken: number = bumpBusyOverlay('正在导入记忆');
    applyMemoryImport(this.items, this.libraryId)
      .then((result: MemoryImportResult): void => {
        this.importing = false;
        if (!this.alive) {
          return; // 已离开页面：库已写入（事务已提交），但不提示不 pop
        }
        if (result.status === MEMORY_IMPORT_STATUS_INSERTED) {
          // 条数口径：实际落库数少于预览数 = 事务内二次容量校验截断了尾部
          const tip: string = result.count < planned ?
            '已导入 ' + result.count + ' 条，库空间不足其余未导入' :
            '已导入 ' + result.count + ' 条记忆';
          this.getUIContext().getPromptAction().showToast({ message: tip });
          this.pathStack.pop({ saved: true }); // 坑17：pop 必带 result 父页才 onPop 重拉
          return;
        }
        if (result.status === MEMORY_IMPORT_STATUS_LIMIT) {
          this.getUIContext().getPromptAction().showToast({ message: MEMORY_FULL_TIP });
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请稍后重试' });
      })
      .catch((e: Object): void => {
        // 事务已 rollBack（库内零改动），留在预览态可重试
        this.importing = false;
        if (!this.alive) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请稍后重试' });
      })
      .finally((): void => {
        releaseBusyOverlay(busyToken);
      });
  }

  // 条目列表重建键（含下标与内容——删除后键变必重建；清单已去重，内容不会重复）
  private itemKey(item: string, index: number): string {
    return index.toString() + '|' + item;
  }

  // 板块标题（14fp 常规字重官方强调蓝 + 卡宽对齐，同 MemoryEditPage「内容」行；存量自绘件，
  // 2026-11-01 随板块标题改档）
  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(SECTION_TITLE_FONTSIZE)
      .fontColor($r('sys.color.ohos_id_color_emphasize'))
      .width(CARD_PANEL_WIDTH)
  }

  // 粘贴态：说明卡 → 复制提示词键 → 粘贴区 → 主键
  @Builder
  PasteStage() {
    // 说明卡 = InfoCard 单源件（title + text 两排，先说明后操作）；「复制提示词」为卡外独立
    // 元素，坐 page_bg 故底色用 fallbackButtonBgOffCard，宽挂 CARD_PANEL_WIDTH
    InfoCard({
      title: '从其他 AI 平台迁移记忆',
      text: '1. 点下面的键复制提示词　2. 粘贴到 ChatGPT 或 Claude 等平台运行　' +
        '3. 把它们的回答粘贴到下面的输入框　4. 点 AI 整理，确认条目后导入'
    })
    Button('复制提示词')
      .width(CARD_PANEL_WIDTH)
      .fontColor(fallbackButtonFont(this.contentFallback, false))
      .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false))
      .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
      .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
      .onClick((): void => {
        this.copyExternalPrompt();
      })

    // 粘贴区（板块标题 + 多行输入 + 计数行 + 出网事实说明）
    Column({ space: SECTION_HEADER_GAP }) {
      this.SectionTitle('粘贴其他平台的输出')
      TextArea({ placeholder: '在此粘贴其他 AI 平台的回答', text: this.pasteText })
        .width(CARD_PANEL_WIDTH)
        .height(240)
        .maxLength(MEMORY_IMPORT_INPUT_MAX)
        .onChange((value: string): void => {
          this.pasteText = value;
        })
      Text(this.pasteText.length + ' / ' + MEMORY_IMPORT_INPUT_MAX)
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
        .textAlign(TextAlign.End)
      Text('粘贴内容会发给你配置的服务商整理。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
    .width('100%')

    // 主键（宽 = CARD_PANEL_WIDTH 与各卡左右缘齐平，写 '100%' 会贴屏缘）；整理中禁用。
    // 「解析模型」板块已撤——配置唯一真源在功能模型页，未配置时由 startPrepare 前置拦截
    Button('AI 整理')
      .width(CARD_PANEL_WIDTH)
      .enabled(this.stage !== STAGE_LOADING)
      .fontColor(fallbackButtonFont(this.contentFallback, true))
      .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
      .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
      .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
      .onClick((): void => {
        this.startPrepare();
      })
    if (this.stage === STAGE_LOADING) {
      Text('正在整理')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
  }

  // 预览态：条目清单 → 说明行 → 底部双键（间距三档：标题后 SECTION_HEADER_GAP、块间 CARD_SPACING）
  @Builder
  PreviewStage() {
    Column({ space: SECTION_HEADER_GAP }) {
      SectionHeader({
        title: '待导入条目',
        hint: ''
      })
      Column({ space: CARD_SPACING }) {
        if (this.items.length === 0) {
          Text('已没有可导入的条目')
            .fontSize(13)
            .fontColor(cardDescColor())
            .width(CARD_PANEL_WIDTH)
        } else {
          ForEach(this.items, (item: string, index: number) => {
            this.PreviewRowCard(item, index)
          }, (item: string, index: number): string => this.itemKey(item, index))
        }
        // 截断说明行（库剩余容量不足——prepare 侧已按剩余容量保留前 N 条，淘汰尾部）
        if (this.truncated > 0) {
          InfoCard({ text: '库空间不足，本次只保留前 ' + this.items.length + ' 条' })
        }
        // 注入窗口说明行（恒显）：库上限远大于注入窗口，新条目进不了注入块——既有机制，
        // 不说明用户会以为「导入的没生效」
        InfoCard({ text: '导入的条目排在库末尾。库内条目较多时，它们不会自动参与对话，需要时可在排序页上移。' })
      }
      .width('100%')
    }
    .width('100%')

    // 底部双键：次钮「返回重来」（回粘贴态保留文本）+ 主键「导入 N 条」
    // ★ 键行宽 = CARD_PANEL_WIDTH（写 '100%' 两键会贴屏缘、与条目卡错位；两键等分）
    // ★ 落库在途两键同禁用：在途回粘贴态而落库仍在跑，成功回来时在粘贴态被 pop
    // ★ 次钮坐 page_bg 无卡体 → fallbackButtonBgOffCard 白底
    Row({ space: 10 }) {
      Button('返回重来')
        .layoutWeight(1)
        .enabled(!this.importing)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBgOffCard(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.backToPaste();
        })
      Button('导入 ' + this.items.length + ' 条')
        .layoutWeight(1)
        .enabled(this.items.length > 0 && !this.importing)
        .fontColor(fallbackButtonFont(this.contentFallback, true))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, true))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, true))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.doImport();
        })
    }
    .width(CARD_PANEL_WIDTH)
    .alignItems(VerticalAlign.Center)
    // 在途状态行（同「正在整理」；落库是事务内查询 + 存档 + 逐条写入，条目多时非瞬返）
    if (this.importing) {
      Text('正在导入')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
  }

  // 预览条目行卡（卡宽 CARD_PANEL_WIDTH + cardBg + 圆角 CARD_RADIUS；右侧删除键 = 行内图标键
  // SymbolGlyph 无底 TEXTUAL（照 ProviderHeadCard 刷新键先例），禁垫 fallbackButton*/resolvedButton*）
  @Builder
  PreviewRowCard(item: string, index: number) {
    Row({ space: 10 }) {
      Text(item)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(cardTitleColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_secondary')])
      }
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .enabled(!this.importing)
      .onClick((): void => {
        this.removeItem(index);
      })
    }
    .width(CARD_PANEL_WIDTH)
    .alignItems(VerticalAlign.Center)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: CARD_SPACING }) {
        if (this.stage === STAGE_PREVIEW) {
          this.PreviewStage()
        } else {
          this.PasteStage()
        }
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
      title: '导入记忆',
      // 每次显示现读生效模型（可能刚在功能模型页换过）；本页无列表数据源，不做其他重拉
      onShown: (): void => {
        this.reloadModel();
      },
      // 执行段返回拦截（BusyOverlay 单源——整理/落库中弹确认，离开 = 撤遮罩 + pop，
      // alive 守卫作废结果 = 放弃本次导入）
      onBackPressed: (): boolean => {
        return confirmLeaveBusyPage(this.getUIContext(), (): void => {
          this.pathStack.pop();
        });
      },
      content: (): void => {
        this.Content();
      }
    })
  }
}

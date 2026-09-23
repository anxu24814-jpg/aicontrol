// 记忆导入页（2026-09-22 记忆导入，任务书-记忆导入-20260922 §3.7）：记忆库管理页「更多」菜单
// 「从其他平台导入」项 push 的三级页——一键复制一段提示词 → 拿去 ChatGPT / Claude 等平台
// 运行 → 把它们的输出粘贴回来 → 「AI 整理」用「记忆提取」卡所选模型整理成规范条目 →
// **先给条目预览**，用户确认后批量写入当前库，写入前自动留一份可回退的快照。
// · 入口库上下文：push param 复用 MemoryImportParam（声明单源在本页，消费侧 import 禁复写
//   ——两份声明字段漂移编译不报错，undefined 会被 typeof 兜到 'global'，点某助手库的导入会
//   静默写进全局库，2026-09-20 D3-5 事故同族）。
// · 三态单页（@State stage）：'paste' 粘贴 → 'loading' 整理中 → 'preview' 预览。三态同页是
//   有意的：整理结果是页内上下文，用一个 push 页承载省掉一次跨页传参，也让「返回重来」变成
//   一次赋值而不是退栈再进。
// · 模型归属 = 「记忆提取」两键（本页只读显示 + 指路，**不做页内换模型**——页内换会隐式改写
//   共享键，语义与成本都最差；要改去功能模型页）。
// · 显示行只显 **modelId 原串**而非模型显示名（与功能模型页的副标题不同）：解析显示名要
//   queryProviders + queryModels 两级查表，该逻辑已在 FunctionalModelPage.resolveModelDisplay
//   与 ToolFunctional.resolveSlot 各存一份，再复制第三份就是三处漂移面（P2-4）；modelId 是
//   resolveMemoryModel 的直接产物，语义无歧义。
// · 三个按钮一律走内容区 fallbackButton* 四件套双态（本站全仓页面按钮的统一形制：主键
//   primary=true 官方强调蓝 + 恒白字、次钮 primary=false；任务书 §3.7 写的 `resolvedButton`
//   四件套是笔误——该族全仓零消费点，只服务弹窗/面板豁免区，本页是内容区）。
// · **页级块一律挂 CARD_PANEL_WIDTH（★ 2026-09-23 决明报障「输入框下方键与预览态返回/导入
//   双键又是全宽」修复点）**：本页宿主滚动列只带顶/底 padding，左右收窄责任在每个页级块——
//   无卡底的输入区三行（TextArea / 计数行 / 出网说明行）、页级主键「AI 整理」、预览态双键 Row
//   全部写 CARD_PANEL_WIDTH；**只有卡内子元素**（GuideCard 内与预览条目行卡内）才写
//   width('100%')（相对卡内容盒恒正确）。判据与两步自检 =《规范-列表卡片与组卡》§4.3 增补
//   十二；先例 = FeedbackPage 主键 + MemoryEditPage 输入区（同形制）。★ 勿把本页页级块塞进
//   一个宽度壳里再让子元素也挂 CARD_PANEL_WIDTH（= 双重收窄，比全宽更难查）。
// · alive 守卫（三重加固 3）：aboutToDisappear 置 alive=false——整理请求回来先判 alive，
//   已离开即丢弃结果、不落库、不提示、不 pop（语义 = 用户退出导入页即放弃本次导入，与
//   「点了才落库」一致）；同一钩子顺带复位 stage 与两个在途闸，避免下次进入残留「整理中」态。
// · 落库在途闸（★ 2026-09-22 自检轮补，域侧闸不盖 apply）：见 importing 成员注释——apply 是
//   单句柄全局事务，预览态落库键常驻可点且落库期间无视觉变化，连点即嵌套 beginTransaction；
//   故 importing 置真期间禁用落库/删除/返回三键 + 显「正在导入」行（反馈形制与库管理页
//   「正在整理 / 正在优化」两行同款）。
// · 刷新：本页不自行刷库列表（本页无列表数据源）——落库链内已广播，父页 onPop 重拉兜底；
//   PageShell.onShown 不做数据重拉。
// · 事务、容量二次校验、存档与广播次序全在 common/MemoryImport.ets（本页只管三态与提示）。
import { pasteboard } from '@kit.BasicServicesKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_MEMORY_IMPORT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, CARD_SPACING, SECTION_TITLE_FONTSIZE, cardBg, cardDescColor, cardTitleColor
} from '../../common/Theme';
import { SectionHeader } from '../SectionHeader';
import {
  CONTENT_FALLBACK_KEY, fallbackButtonBg, fallbackButtonFont, fallbackButtonMaterial,
  fallbackButtonStateEffect, IMMERSIVE_LEVEL_KEY
} from '../../common/ImmersiveLevel';
import { MEMORY_FULL_TIP, MemoryModelPick, resolveMemoryModel } from '../../common/MemoryGen';
import {
  applyMemoryImport, MEMORY_IMPORT_EXTERNAL_PROMPT, MEMORY_IMPORT_INPUT_MAX,
  MEMORY_IMPORT_STATUS_CONFIG, MEMORY_IMPORT_STATUS_FAILED, MEMORY_IMPORT_STATUS_INSERTED,
  MEMORY_IMPORT_STATUS_LIMIT, MEMORY_IMPORT_STATUS_NONE, MEMORY_IMPORT_STATUS_READY,
  MEMORY_IMPORT_STATUS_TOO_LARGE, MemoryImportPlan, MemoryImportResult, prepareMemoryImport
} from '../../common/MemoryImport';
import { MEMORY_SCOPE_GLOBAL } from '../../common/store/MemoryDb';
// push 参数载体 MemoryImportParam 的声明单源在 MemoryLibraryPage.ets（push 发起方）——本文件
// 只 import 消费，**禁本地复写**（D3-5 事故同族：两份声明字段漂移编译不报错，undefined 会被
// 下方 typeof 兜到 'global'，点某助手库的导入会静默写进全局库）
import { MemoryImportParam } from './MemoryLibraryPage';

// 三态取值（@State stage 的值域；字符串常量防手写拼错）
const STAGE_PASTE: string = 'paste';
const STAGE_LOADING: string = 'loading';
const STAGE_PREVIEW: string = 'preview';

// 模型未配置前置提示（★ 与库管理页「立即整理」逐字同句——同一状况同一说法，禁另写）
const IMPORT_NO_MODEL_TIP: string = '请先在功能模型页的「记忆提取」卡选择模型';

@Component
export struct MemoryImportPage {
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 目标库（aboutToAppear 从 push param 解析）：'global' = 全局库 / 助手 id = 助手库
  private libraryId: string = MEMORY_SCOPE_GLOBAL;
  // 三态（'paste' 粘贴 / 'loading' 整理中 / 'preview' 预览）
  @State private stage: string = STAGE_PASTE;
  // 粘贴文本（用户输入；切「返回重来」时保留）
  @State private pasteText: string = '';
  // 生效模型 id 镜像（「解析模型」显示行 + 主键前置判定共用；aboutToAppear / onShown 现读）
  @State private modelId: string = '';
  // 待导入条目（预览态本地清单——删除只改本数组，**不写库**）
  @State private items: string[] = [];
  // 库剩余容量不足被丢弃的条数（0 = 没丢；预览态据此出说明行）
  @State private truncated: number = 0;
  // 落库在途闸（★ 2026-09-22 自检轮补）：apply 是**单句柄全局事务**（MemoryDb 已申报
  // 「不得在别处事务已开启时调用」），而预览态的「导入 N 条」是一枚常驻可点键、落库期间
  // 无任何视觉变化——连点即第二次 beginTransaction（嵌套 = 抛错，用户看到「导入失败」而
  // 第一次其实成功）。域侧 in-flight 单布尔闸只盖 prepare（模型请求），**不盖 apply**，
  // 故在途闸落在本页：置真即禁用落库键与条目删除键（删除键同时在途可改本地清单 →
  // 「已导入 N 条」的 N 与用户所见不符），并显一行「正在导入」（与粘贴态「正在整理」
  // 同款反馈，参照库管理页「正在整理 / 正在优化」两行的既有形制）
  @State private importing: boolean = false;
  // 页面存活守卫（alive 判据见文件头「alive 守卫」注；普通成员不驱动 UI）
  private alive: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    // push param 解析（对象形态 { libraryId }；缺省/异常 = 全局库兜底——库管理页同款守卫）
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
    // 离开页面 = 放弃本次导入（见文件头 alive 守卫）；复位三态与两个在途闸防下次进入残留
    this.alive = false;
    this.stage = STAGE_PASTE;
    this.items = [];
    this.truncated = 0;
    this.importing = false;
  }

  // 生效模型现读（显示行与主键前置判定共用一处——pickMemoryModel 单源语义，缺一键即未配置）
  private reloadModel(): void {
    const picked: MemoryModelPick = resolveMemoryModel();
    this.modelId = picked.providerId !== '' && picked.modelId !== '' ? picked.modelId : '';
  }

  // 复制提示词（官方粘贴板；Promise 失败 toast 不静默——ModelEditPage.copyModelId 同款形制）
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
      return; // 按钮闸（整理中主键已禁用，此处兜底防连点）
    }
    if (this.pasteText.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请先粘贴内容' });
      return;
    }
    if (this.modelId === '') {
      // 模型未配置 = 不可导入（与「立即整理」同口径）；守卫在起请求前判，不让用户白等一轮
      this.getUIContext().getPromptAction().showToast({ message: IMPORT_NO_MODEL_TIP });
      return;
    }
    this.stage = STAGE_LOADING;
    prepareMemoryImport(this.pasteText, this.libraryId)
      .then((plan: MemoryImportPlan): void => {
        // ★ alive 守卫（三重加固 3）：用户已离开页面即丢弃结果——不落库、不出提示、不 pop
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
        // 域内已全吞错误（失败落 failed 态），此处只兜「连结果对象都没拿到」的意外
        if (!this.alive) {
          return;
        }
        this.stage = STAGE_PASTE;
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请稍后重试' });
      });
  }

  // 整理结果态 → 页面提示（'' = 不出提示）。ready/inserted 不走此处（分别进预览态、走落库
  // 提示）；skipped（库未就绪 / 总开关关 / 在途重复触发）沉默——那几种情况用户无事可做。
  // ★ limit 复用 MEMORY_FULL_TIP（与「＋」新建、立即整理同一句）
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
      // 双保险提示（输入框 maxLength 已拦一次，程序化写入/旧草稿才会走到这里）
      return '粘贴内容过长，请控制在 ' + MEMORY_IMPORT_INPUT_MAX + ' 字以内';
    }
    return '';
  }

  // 预览态删一条（只改本地数组，不写库）
  private removeItem(index: number): void {
    if (this.importing) {
      return; // 在途闸（键已禁用，此处兜底——落库读的是本清单，在途删条会让提示条数与所见不符）
    }
    const next: string[] = [];
    for (let i: number = 0; i < this.items.length; i++) {
      if (i !== index) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
  }

  // 返回重来（回粘贴态，保留已粘贴文本——用户多半只是想改几个字再试一次）
  private backToPaste(): void {
    this.stage = STAGE_PASTE;
  }

  // ── 落库（主键「导入 N 条」）：失败一律留在预览态、不得 pop（条目清单保留可重试）──
  private doImport(): void {
    if (this.importing) {
      return; // 在途闸（键已禁用，此处兜底防连点——嵌套事务的唯一防线）
    }
    if (this.items.length === 0) {
      return; // 空清单主键已禁用，此处兜底
    }
    const planned: number = this.items.length;
    this.importing = true;
    applyMemoryImport(this.items, this.libraryId)
      .then((result: MemoryImportResult): void => {
        this.importing = false;
        if (!this.alive) {
          return; // 已离开页面：库已写入（事务已提交），但不提示不 pop
        }
        if (result.status === MEMORY_IMPORT_STATUS_INSERTED) {
          // 条数口径：实际落库数少于预览数 = 事务内二次容量校验截断了尾部（窗口期库被写满）
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
        // 域内事务已 rollBack（库内零改动），本页只出提示并留在预览态供重试
        this.importing = false;
        if (!this.alive) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请稍后重试' });
      });
  }

  // 条目列表重建键（含下标与内容——删除后键变必重建；清单内条目已由解析侧去重，内容不会重复）
  private itemKey(item: string, index: number): string {
    return index.toString() + '|' + item;
  }

  // 说明卡：四步操作说明 + 「复制提示词」键（文案规约：禁冒号分号括号连环——并列动作分句用
  // 句号，步骤序号用中文顿号式「1. 2.」，不写「如：」「（示例）」）
  @Builder
  GuideCard() {
    Column({ space: 10 }) {
      Text('从其他 AI 平台迁移记忆')
        .fontSize(16)
        .fontColor(cardTitleColor())
      Text('1. 点下面的键复制提示词　2. 粘贴到 ChatGPT 或 Claude 等平台运行　' +
        '3. 把它们的回答粘贴到下面的输入框　4. 点 AI 整理，确认条目后导入')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Button('复制提示词')
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
        .systemMaterial(fallbackButtonMaterial(this.contentFallback, this.immersiveLevel, false))
        .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
        .onClick((): void => {
          this.copyExternalPrompt();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 板块标题（无副标题形态——MemoryEditPage「内容」行同款：16fp Bold 卡标题色 + 卡宽对齐；
  // 不用 SectionHeader 是因为它会为空的 subtitle 也渲染一行，白多一段行距）
  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(SECTION_TITLE_FONTSIZE)
      .fontWeight(FontWeight.Bold)
      .fontColor(cardTitleColor())
      .width(CARD_PANEL_WIDTH)
  }

  // 粘贴态：说明卡 → 粘贴区 → 模型行 → 主键
  @Builder
  PasteStage() {
    // 说明卡（卡体：卡宽基准 + 卡底 + 圆角 16 + 内边距 16——同页其余卡同款）
    Column() {
      this.GuideCard()
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)

    // 粘贴区（板块标题 + 多行输入 + 计数行 + 出网事实说明）
    Column({ space: 6 }) {
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

    // 模型行（只读显示 + 指路功能模型页；未配置 = 「未选择」灰字）
    Column({ space: 6 }) {
      this.SectionTitle('解析模型')
      Text(this.modelId !== '' ? this.modelId : '未选择')
        .fontSize(15)
        .fontColor(this.modelId !== '' ? cardTitleColor() : cardDescColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(CARD_PANEL_WIDTH)
      Text('用功能模型页「记忆提取」卡所选模型。未选择时不能导入。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
    .width('100%')

    // 主键（通宽主操作键——宽基准 = 卡宽 CARD_PANEL_WIDTH 而非 width('100%')：本页宿主滚动列
    // 无左右 padding，「通宽」指与同页各卡左右缘齐平，写 '100%' 会贴屏缘宽出 16vp；整理中禁用
    // + 一行状态提示）
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

  // 预览态：条目清单（可逐条删除）→ 说明行 → 底部双键
  @Builder
  PreviewStage() {
    Column({ space: 6 }) {
      SectionHeader({
        title: '待导入条目',
        subtitle: this.items.length + ' 条',
        hint: ''
      })
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
        Text('库空间不足，本次只保留前 ' + this.items.length + ' 条')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width(CARD_PANEL_WIDTH)
      }
      // 注入窗口说明行（恒显，用户预期管理）：库上限远大于注入窗口，导入落卡底，库里条目多时
      // 新条目进不了注入块——这是既有机制不是缺陷，但不说明会让用户以为「导入的没生效」
      Text('导入的条目排在库末尾。库内条目较多时，它们不会自动参与对话，需要时可在排序页上移。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
    .width('100%')

    // 底部双键：次钮「返回重来」（回粘贴态保留文本）+ 主键「导入 N 条」
    // ★ 键行宽 = CARD_PANEL_WIDTH（不是 '100%'——同上：宿主滚动列无左右 padding，写 '100%'
    //   两键整体贴屏缘、与上方条目卡左右缘错位 16vp；两键各 layoutWeight(1) 等分键行宽）
    // ★ 落库在途两键同禁用（在途闸，见 importing 成员注释）：在途点「返回重来」会回到粘贴态
    //   而落库仍在跑，成功回来时页面在粘贴态被 pop——用户无从理解
    Row({ space: 10 }) {
      Button('返回重来')
        .layoutWeight(1)
        .enabled(!this.importing)
        .fontColor(fallbackButtonFont(this.contentFallback, false))
        .backgroundColor(fallbackButtonBg(this.contentFallback, this.immersiveLevel, false))
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
    // 在途状态行（与粘贴态「正在整理」同款；落库是一次事务内查询 + 存档 + 逐条写入，
    // 条目多时非瞬返，用户需要看见「点了有反应」）
    if (this.importing) {
      Text('正在导入')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width(CARD_PANEL_WIDTH)
    }
  }

  // 预览条目行卡（形制照记忆条目卡：CARD_PANEL_WIDTH + cardBg + 圆角 16 + 行卡；右侧删除键 =
  // 行内图标键 SymbolGlyph 无底 TEXTUAL，照 ProviderHeadCard 刷新键先例——宪法「行内操作按钮
  // 官方形制」条，禁垫 fallbackButton*/resolvedButton* 四件套）
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
    .borderRadius(16)
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
  }

  build() {
    PageShell({
      title: '导入记忆',
      // 每次显示现读生效模型（用户可能刚去功能模型页换过「记忆提取」模型；本页三态与粘贴
      // 文本不受影响——只刷显示行与主键判据）。本页无列表数据源，不做其他重拉
      onShown: (): void => {
        this.reloadModel();
      },
      // 无标题栏菜单键（导入动作在页内主键）
      content: (): void => {
        this.Content();
      }
    })
  }
}

// 知识库条目编辑页：条目三字段（名称 / 关键词 / 正文）+ 注入配置 + 触发精度 + 附件文件，
// param = KnowledgeEditParam（bookId + entryId，'' = 新建）。
// 骨架照 SkillEditPage：三段分段胶囊（条目 / 正文 / 文件），经标题栏下方带承载（公共件
// PageTopSegmentBand），吸顶不随内容滚，参数单源在 SegmentBar。分段成立的理由 = 第三段与字段/长文
// 是异构内容（附件清单）。新建态两段（条目 / 正文）——附件要挂在条目行上，未落库时第三段
// 整段不出现，落库后 pop 回清单页，重进编辑页再配附件。
// · 标题栏「保存」单键（checkmark；HDS 菜单数组），**只保存条目
//   三字段**；附件在文件编辑页里即时落库（两处职责不串）。
// · 保存链：进行中闸（防双击并发过查重窗双插）→ 加载闸（编辑态读回行后才许保存，否则空表单
//   覆盖既有行）→ 名称校验（空即 toast 中断）→ 重名拦截（同书标题唯一，判定单源 =
//   KnowledgeText.knowledgeTitleTaken）→ insert（source='user'）/ update（0 行 affected 由
//   KnowledgeDb 抛中文错）→ toast「已保存」→ pop({ saved: true }) 触发书详情页 onPop 重拉。
// · 关键词可选（参与检索加权与自动注入匹配）；正文也允许为空（有条目名就能在清单看见）。
// · 附件链：文件卡列附件（件名 + 字数 + 行内编辑/删除图标键）+「新建文件」「上传文件」并排
//   胶囊双键；上传 = DocumentViewPicker 免权限选择器 → UTF-8 读取（KnowledgePack 带字节粗拦
//   与乱码判拒）→ 校验 → 带初值进文件编辑页让用户过目再存。件名查重与件数上限两道硬拒在
//   KnowledgeDb 写入侧（本页只做入口拦截与文案）。
// · 卡内说明分层：机制说明收进卡标题行右端 ⓘ 气泡（InfoHintButton 单源复用），卡面只留输入
//   时用得上的短句与**字段标签行**（13fp 灰标签在上 + 整宽输入框，形制先例 =
//   ProviderConfigPanel.FieldInput；也见 SearchEngineDetailPage 头注释「卡标题即字段标签」）。
//   标签 ≠ 说明，收说明时不可连标签一起收——占位符一有内容就不显示，只靠它认字段。
// · 注入配置独立成卡（三行常显由 PromptInjectConfig 承担）；正文卡字数计数在卡头；附件行带
//   文件图标块。字段、校验与保存链如上。
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { SegmentButtonV2Items } from '@kit.ArkUI';
import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { PageShell } from '../../common/PageShell';
import { ROUTE_KNOWLEDGE_EDIT_PAGE, ROUTE_KNOWLEDGE_FILE_EDIT_PAGE } from '../../common/RouteNames';
import {
  CARD_PANEL_WIDTH, cardBg, cardDescColor, cardTitleColor, CARD_SECTION_TITLE_FONTSIZE,
  SEGMENT_BAR_HEIGHT, wellBg, CARD_RADIUS
} from '../../common/Theme';
import { PageTopSegmentBand } from '../SegmentBar';
import {
  CONTENT_FALLBACK_KEY, IMMERSIVE_LEVEL_KEY, fallbackButtonBg, fallbackButtonBgTinted, fallbackButtonFont, fallbackButtonFontTinted,
  fallbackButtonMaterial, fallbackButtonMaterialTinted, fallbackButtonStateEffect, overlayMaterial
} from '../../common/ImmersiveLevel';
import {
  broadcastKnowledgeList, deleteEntryFile, insertEntry, KnowledgeEntryInput,
  KnowledgeEntryRow, KnowledgeFileRow, queryEntries, queryEntry,
  queryEntryFiles, toEntryItems, updateEntry
} from '../../common/store/KnowledgeDb';
import { pickedKnowledgeName, readPickedKnowledgeFileText } from '../../common/KnowledgePack';
import {
  clampKnowledgePriority, clampKnowledgeScan, KNOWLEDGE_CONTENT_MAX,
  KNOWLEDGE_FILE_CONTENT_MAX, KNOWLEDGE_FILE_EXTS,
  KNOWLEDGE_FILE_MAX_COUNT, KNOWLEDGE_KEYWORDS_MAX,
  KNOWLEDGE_TITLE_MAX, KnowledgeFileValidation, knowledgeTitleTaken,
  validateKnowledgeFileArgs
} from '../../common/KnowledgeText';
import { KnowledgeEditParam } from './KnowledgeBookPage';
import { KnowledgeFileEditParam } from './KnowledgeFileEditPage';
import { InfoHintButton } from '../InfoHintButton';
import { ConfirmDialog } from '../chat/ConfirmDialog';
// 注入配置组（复用提示词编辑页域件：@Link 三值 + 两回调，联动钳位照 PromptEditPage）
import { PromptInjectConfig, sanitizeInjectPosition, sanitizeInjectDepth,
  sanitizeInjectRole } from './PromptInjectConfig';
import { INJECT_POSITION_HEAD, INJECT_ROLE_ASSISTANT,
  INJECT_ROLE_SYSTEM } from '../../common/providers/RequestInject';

// 标题栏「保存」单键（checkmark；SkillEditPage / MemoryEditPage 同款形制）
function knowledgeSaveMenuHds(onSave: () => void): HdsNavigationMenuContentOptions {
  return {
    value: [{
      content: {
        icon: $r('sys.symbol.checkmark'),
        action: onSave
      }
    }]
  } as HdsNavigationMenuContentOptions;
}

@Component
export struct KnowledgeEditPage {
  // 页面存活守卫：置位后迟到异步回调不写状态、不碰 UI；写库等数据层意图照常完成
  private departed: boolean = false;
  @Prop topPad: number = 0;
  @Prop bottomPad: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  // 归属库 id 与编辑对象 id（'' = 新建）；构造后不变（坑30）
  private bookId: string = '';
  private entryId: string = '';
  // 表单三字段（@State 驱动输入回显）
  @State private title: string = '';
  @State private keywords: string = '';
  @State private content: string = '';
  // 注入配置三值（启用开关已迁条目卡，本页不读写 enabled）：新建态默认 system/head/0；
  // 编辑态从行读并经 sanitize 钳脏值
  @State private injectRole: string = 'system';
  @State private injectPosition: string = 'head';
  @State private injectDepth: number = 0;
  // 触发精度四态：数字字段 @State 存 string（number 无法表达空框，会被迫落 0）；保存时
  // parseInt + clampKnowledgePriority/clampKnowledgeScan（归一单源在 KnowledgeText，禁本页另写钳位）
  @State private matchCase: boolean = false;
  @State private matchWhole: boolean = false;
  @State private priorityText: string = '100';
  @State private scanText: string = '8';
  // 附件文件清单（仅编辑态加载——新建态尚无条目行可挂文件，见文件头）
  @State private files: KnowledgeFileRow[] = [];
  // 分段页签选中项（0 条目 / 1 正文 / 2 文件——@State 驱动面板切换）
  @State private segIndex: number = 0;

  // 标题栏下方带承载（几何与带内下移量单源 = 公共件 PageTopSegmentBand）
  @Builder
  TopSegmentBand() {
    PageTopSegmentBand({
      items: this.entryId === '' ? this.tabItemsNew : this.tabItemsEdit,
      selectedIndex: $segIndex
    })
  }
  // 加载完成闸（SkillEditPage O-13 闸同款）：读失败时页面停在空表单，保存会 updateEntry 覆盖
  // 真实行——未加载完成不许落库。新建态直接置真；普通成员（不驱动 UI 勿 @State）
  private loaded: boolean = false;
  // 保存进行中闸（HttpTemplatePage F6 闸同款；普通成员）：查重与落库无 UNIQUE 兜底，双击快连
  // 会并发过查重窗插两行同名——串行化，finally 复位
  private saving: boolean = false;
  @StorageProp('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // 文件卡双键胶囊的双态入参（内容区回退函数族，口径见 common/ImmersiveLevel.ets 头注释）
  @StorageProp(CONTENT_FALLBACK_KEY) contentFallback: boolean = true;
  @StorageProp(IMMERSIVE_LEVEL_KEY) immersiveLevel: number = 0;
  // 分段页签选项（两套预建实例按 entryId 择一）：编辑态三段、新建态两段。entryId 构造后不变
  //（坑30），故用非响应式成员
  private tabItemsEdit: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '条目' },
    { text: '正文' },
    { text: '文件' }
  ]);
  private tabItemsNew: SegmentButtonV2Items = new SegmentButtonV2Items([
    { text: '条目' },
    { text: '正文' }
  ]);
  // 行内删除附件的目标行与确认弹窗（成员位控制器——坑7 约束）
  private fileDeleteTarget: KnowledgeFileRow | null = null;
  private fileConfirmCtrl: CustomDialogController = new CustomDialogController({
    systemMaterial: overlayMaterial(),
    builder: ConfirmDialog({
      title: '删除文件',
      message: '删除后无法恢复。助手读取这条条目时也不再看到这个文件。',
      confirmLabel: '删除',
      onConfirm: (): void => {
        this.doRemoveFile();
      }
    }),
    autoCancel: true
  });

  aboutToAppear(): void {
    const params: Array<Object | null> =
      (this.pathStack.getParamByName(ROUTE_KNOWLEDGE_EDIT_PAGE) ?? []) as Array<Object | null>;
    const last: Object | null = params.length > 0 ? params[params.length - 1] : null;
    if (last === null) {
      this.getUIContext().getPromptAction().showToast({ message: '缺少条目参数' });
      this.pathStack.pop();
      return;
    }
    const param = last as KnowledgeEditParam;
    this.bookId = param.bookId;
    this.entryId = param.entryId;
    if (this.entryId === '') {
      this.loaded = true; // 新建态无待读行（闸只拦「加载未完成」，不拦新建）
      return;
    }
    queryEntry(this.entryId)
      .then((row: KnowledgeEntryRow | null): void => {
        if (this.departed) {
          return;
        }
        if (row === null) {
          this.getUIContext().getPromptAction().showToast({ message: '条目不存在或已删除' });
          this.pathStack.pop();
          return;
        }
        this.title = row.title;
        this.keywords = row.keywords;
        this.content = row.content;
        // 注入三值回填（同 PromptEditPage 口径：system 恒 head、assistant 无深度 0）。
        // enabled 不回填也不写——开关已迁条目卡
        const role: string = sanitizeInjectRole(row.injectRole);
        this.injectRole = role;
        this.injectPosition = role === INJECT_ROLE_SYSTEM ? INJECT_POSITION_HEAD
          : sanitizeInjectPosition(row.injectPosition);
        const rawDepth: number = sanitizeInjectDepth(row.injectDepth);
        this.injectDepth = role === INJECT_ROLE_ASSISTANT && rawDepth === 0 ? 1 : rawDepth;
        // 触发精度四值回填：布尔列 0/1（=== 1 为真）；两数字经 clamp 归一后写文本态
        this.matchCase = row.matchCase === 1;
        this.matchWhole = row.matchWhole === 1;
        this.priorityText = String(clampKnowledgePriority(row.priority));
        this.scanText = String(clampKnowledgeScan(row.scanDepth));
        this.loaded = true;
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({
          message: '条目读取失败：' + (e as Error).message
        });
      });
  }

  // 附件清单重拉（文件编辑页保存/删除返回后经 onPop 调；失败 toast 不静默 P0-1）
  private reloadFiles(): void {
    if (this.entryId === '') {
      this.files = [];
      return;
    }
    queryEntryFiles(this.entryId)
      .then((rows: KnowledgeFileRow[]): void => {
        if (this.departed) {
          return;
        }
        this.files = rows;
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '附件读取失败：' + (e as Error).message });
      });
  }

  // 文件编辑页跳转（新建/编辑共用；pop 带 result → 重拉清单，坑17）
  private openFilePage(fileId: string, draftName: string, draftContent: string): void {
    const param: KnowledgeFileEditParam = { entryId: this.entryId, fileId: fileId,
      draftName: draftName, draftContent: draftContent };
    this.pathStack.pushPathByName(ROUTE_KNOWLEDGE_FILE_EDIT_PAGE, param, (): void => {
      this.reloadFiles();
    });
  }

  // 上传文件：选择器 → UTF-8 读取（字节粗拦与乱码判拒）→ 校验 → 带初值进文件编辑页审阅，
  // 不直接入库。扩展名在校验处先判，当场给中文原因（别让用户填一半才被告知格式不对）
  private async uploadFile(): Promise<void> {
    if (this.files.length >= KNOWLEDGE_FILE_MAX_COUNT) {
      this.getUIContext().getPromptAction().showToast({
        message: '每个条目最多附 ' + KNOWLEDGE_FILE_MAX_COUNT + ' 个文件，请先删除不再需要的文件'
      });
      return;
    }
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      // 单文件动作：不设 maxSelectNumber 时系统面板默认多选，除首个外静默丢失
      const selectOpts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      selectOpts.maxSelectNumber = 1;
      const uris: Array<string> = await docPicker.select(selectOpts);
      if (this.departed) {
        return;
      }
      if (uris.length === 0) {
        return; // 用户取消，静默
      }
      const name: string = pickedKnowledgeName(uris[0]);
      const text: string = readPickedKnowledgeFileText(uris[0]);
      const v: KnowledgeFileValidation = validateKnowledgeFileArgs(name, text);
      if (!v.ok) {
        this.getUIContext().getPromptAction().showToast({ message: v.error });
        return;
      }
      this.openFilePage('', v.name, v.content);
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '读取文件失败：' + (e as Error).message });
    }
  }

  // 行内删除附件（先记目标再弹确认——不可逆操作与库页删除行同款两段式）
  private removeFile(row: KnowledgeFileRow): void {
    this.fileDeleteTarget = row;
    this.fileConfirmCtrl.open();
  }

  private doRemoveFile(): void {
    const target: KnowledgeFileRow | null = this.fileDeleteTarget;
    if (target === null) {
      return;
    }
    this.fileDeleteTarget = null;
    deleteEntryFile(target.id)
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已删除' });
        this.reloadFiles();
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message });
      });
  }

  // 保存（闸壳防重入见 saving 注释；校验 → 重名拦截 → 落库 → 广播 → 带 result 返回）
  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      await this.saveInner();
    } finally {
      this.saving = false;
    }
  }

  // 注入脏值钳位（PromptEditPage 同口径：system 恒 head、assistant 不含深度 0——注入成末条
  // 会被 Gemini 拒且跨模型不一致）
  private sanitizePositionValue(): string {
    return sanitizeInjectRole(this.injectRole) === INJECT_ROLE_SYSTEM ?
      INJECT_POSITION_HEAD : sanitizeInjectPosition(this.injectPosition);
  }

  private sanitizeDepthValue(): number {
    const d: number = sanitizeInjectDepth(this.injectDepth);
    return sanitizeInjectRole(this.injectRole) === INJECT_ROLE_ASSISTANT && d === 0 ? 1 : d;
  }

  private async saveInner(): Promise<void> {
    // 加载完成闸（未加载完即空表单，落库会覆盖既有行）
    if (!this.loaded) {
      this.getUIContext().getPromptAction().showToast({
        message: '条目未加载完成，暂不能保存，请返回重进'
      });
      return;
    }
    const trimmedTitle: string = this.title.trim();
    if (trimmedTitle === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请填写条目名称' });
      return;
    }
    const input: KnowledgeEntryInput = {
      title: trimmedTitle,
      keywords: this.keywords.trim(),
      content: this.content.trim(),
      // 注入三值经 sanitize 钳位（与回填同口径）。enabled 不传：开关已迁条目卡（setEntryEnabled
      // 单列写），updateEntry 见 undefined 保留原值，insertEntry 落默认 1
      injectRole: sanitizeInjectRole(this.injectRole),
      injectPosition: this.sanitizePositionValue(),
      injectDepth: this.sanitizeDepthValue(),
      // 布尔转 0/1；数字 parseInt + clamp 归一（NaN 落默认 100/8——InputType.Number 挡不住
      // 越界与超长，clamp 必做）
      matchCase: this.matchCase ? 1 : 0,
      matchWhole: this.matchWhole ? 1 : 0,
      priority: clampKnowledgePriority(Number.parseInt(this.priorityText, 10)),
      scanDepth: clampKnowledgeScan(Number.parseInt(this.scanText, 10))
    };
    // 重名拦截（同书标题唯一）：新建与编辑两态同判，编辑态排除自身 id。判定单源 =
    // KnowledgeText.knowledgeTitleTaken（工具侧 manage_knowledge 同用，禁另写比较逻辑）；命中即中断
    try {
      const entries: KnowledgeEntryRow[] = await queryEntries(this.bookId);
      if (this.departed) {
        return;
      }
      if (knowledgeTitleTaken(toEntryItems(entries), trimmedTitle, this.entryId)) {
        this.getUIContext().getPromptAction().showToast({
          message: '已有同名条目，换一个名称再试。'
        });
        return;
      }
      // persist 内部自吞失败并 toast——await 恒 resolve，闸复位交给 save 壳的 finally
      await this.persist(input);
      if (this.departed) {
        return;
      }
    } catch (e) {
      if (this.departed) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({
        message: '保存失败：' + (e as Error).message
      });
    }
  }

  // 落库（新增/编辑两路；source 只在新增时定 'user'，与助手 manage_knowledge 的 'assistant' 区分）
  private persist(input: KnowledgeEntryInput): void {
    const chain: Promise<void> = this.entryId === '' ?
      insertEntry(this.bookId, input, 'user').then((): void => {
      }) : updateEntry(this.entryId, input);
    chain
      .then((): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
        broadcastKnowledgeList();
        this.pathStack.pop({ saved: true });
      })
      .catch((e: Object): void => {
        if (this.departed) {
          return;
        }
        this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message });
      });
  }

  @Builder
  CardTitleRow(title: string) {
    Text(title)
      .fontSize(CARD_SECTION_TITLE_FONTSIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(cardTitleColor())
      .width('100%')
  }

  // ── 第一段：条目（名称 + 关键词）──
  // 两字段各配恒可见标签行（理由见文件头）；机制说明收进 ⓘ 气泡，关键词的「留空合法」句
  // 必须留在卡面（KnowledgeText 的通用格式导出只收带关键词的条目）
  @Builder
  EntryCard() {
    Column({ space: 12 }) {
      Row() {
        Text('条目')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '一条写一个知识点。名称是清单里的标题，也是检索权重最高的字段。助手命中时读到的是这条条目的正文。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Column({ space: 6 }) {
        Text('名称')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        TextInput({ placeholder: '例如 TCP 三次握手', text: this.title })
          .width('100%')
          .maxLength(KNOWLEDGE_TITLE_MAX)
          .onChange((value: string): void => {
            this.title = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Column({ space: 6 }) {
        Text('关键词')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
        TextInput({ placeholder: '例如 TCP、握手、三次握手', text: this.keywords })
          .width('100%')
          .maxLength(KNOWLEDGE_KEYWORDS_MAX)
          .onChange((value: string): void => {
            this.keywords = value;
          })
        // 留空 = 不参与自动注入（检索语义不变）
        Text('多个关键词用顿号或逗号分隔。留空则不会被自动注入，仍可按名称与正文检索。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 启用开关在上一级条目卡（更多键左侧即时开关）：本页无启用行，保存不写 enabled 列
      //（停用后不参与自动注入与工具检索，管理清单仍可见）
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 触发设置卡：先决定怎么命中，再决定命中后放哪，故居注入方式卡之前（不加分段——与
  // 名称/关键词同属配置表单，分段只在异构时用）。开关行 = Toggle 右置且是唯一控制面（行不可
  // 点）；数字字段 = 标签在上 + 定宽输入框（76×36、TextAlign.Center、maxLength 4，形制照
  // WebServiceSettingsPage 端口输入；onChange 只留数字、失焦 clamp 归一回写）。整词说明行
  // 交代行为差异（中文键回落子串），必须留在卡面可见位 ──
  @Builder
  TriggerCard() {
    Column({ space: 12 }) {
      Row() {
        Text('触发设置')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '发送前用关键词匹配最近的消息。命中的条目按优先级从大到小参与注入，' +
            '同优先级按知识库排列顺序在前。注入条数与总字数有上限，先装排在前面的。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('匹配方式')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Row() {
        Text('区分大小写')
          .fontSize(15)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.matchCase })
          .onChange((isOn: boolean): void => {
            this.matchCase = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('关闭后英文不区分大小写。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Row() {
        Text('整词匹配')
          .fontSize(15)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.matchWhole })
          .onChange((isOn: boolean): void => {
            this.matchWhole = isOn;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('只对英文单词生效，中文关键词仍按包含匹配。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Text('检查最近消息')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.scanText })
          .type(InputType.Number)
          .maxLength(4)
          .width(76)
          .height(36)
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .onChange((value: string): void => {
            // 只留数字（归一兜底在 blur 与保存链）
            this.scanText = value.replace(/[^0-9]/g, '');
          })
          .onBlur((): void => {
            // 失焦归一回写（端口输入同款）：空串保留空（保存时落默认），非空经 clamp 显示
            if (this.scanText !== '') {
              this.scanText = String(clampKnowledgeScan(Number.parseInt(this.scanText, 10)));
            }
          })
        Text('条')
          .fontSize(15)
          .fontColor(cardTitleColor())
        Text('在最近几条消息里找关键词，留空按 8 条。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text('优先级')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.priorityText })
          .type(InputType.Number)
          .maxLength(4)
          .width(76)
          .height(36)
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .onChange((value: string): void => {
            this.priorityText = value.replace(/[^0-9]/g, '');
          })
          .onBlur((): void => {
            if (this.priorityText !== '') {
              this.priorityText = String(clampKnowledgePriority(Number.parseInt(this.priorityText, 10)));
            }
          })
        Text('命中多条时，数值大的先注入，同优先级按知识库排列顺序。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 注入方式卡（自条目卡分家：条目管名称/关键词，注入管身份/位置/深度）；三行常显由
  // PromptInjectConfig 承担，说明句在组件内 ──
  @Builder
  InjectCard() {
    Column({ space: 12 }) {
      this.CardTitleRow('注入方式')
      PromptInjectConfig({
        role: $injectRole,
        injectPosition: $injectPosition,
        depth: $injectDepth,
        onRoleChanged: (role: string): void => {
          this.injectRole = role;
          // 联动：身份 system → 位置强制 head；assistant → 深度 0 钳位 1（域件口径）
          if (role === INJECT_ROLE_SYSTEM) {
            this.injectPosition = INJECT_POSITION_HEAD;
          } else if (role === INJECT_ROLE_ASSISTANT && this.injectDepth === 0) {
            this.injectDepth = 1;
          }
        },
        onPositionChanged: (position: string, depth: number): void => {
          this.injectPosition = position;
          this.injectDepth = depth;
        }
      })
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 第二段：正文 ──
  @Builder
  ContentCard() {
    Column({ space: 12 }) {
      // 标题行 + 字数计数（与提示词/技能正文卡同形）
      Row({ space: 8 }) {
        Text('正文')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        Text(this.content.length + ' / ' + KNOWLEDGE_CONTENT_MAX)
          .fontSize(13)
          .fontColor(cardDescColor())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      TextArea({ placeholder: '写下这条知识的正文，助手命中后会读到全文', text: this.content })
        .width('100%')
        .height(240)
        .maxLength(KNOWLEDGE_CONTENT_MAX)
        .onChange((value: string): void => {
          this.content = value;
        })
      Text('正文是纯文本，写清术语含义、规则或背景即可。')
        .fontSize(13)
        .fontColor(cardDescColor())
        .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(16)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // ── 第三段：附件文件组卡（仅编辑态可达）──
  // 行 = 件名 + 字数 + 行内图标键（编辑/删除，形制同 SkillsEditPage 文件卡）；格式说明收进 ⓘ
  //（卡面只留标题与操作；InfoHintButton 单源复用勿另起气泡件）
  @Builder
  FilesCard() {
    Column({ space: 10 }) {
      Row() {
        Text('附件文件')
          .fontSize(CARD_SECTION_TITLE_FONTSIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(cardTitleColor())
          .layoutWeight(1)
        InfoHintButton({
          text: '支持 ' + KNOWLEDGE_FILE_EXTS.join('、') + '，单个文件不超过 ' +
            KNOWLEDGE_FILE_CONTENT_MAX + ' 字，最多 ' + KNOWLEDGE_FILE_MAX_COUNT + ' 个。'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.files.length === 0) {
        Text('还没有附件文件。附件是随条目一起给助手取用的参考资料，例如术语表、字段说明。')
          .fontSize(13)
          .fontColor(cardDescColor())
          .width('100%')
      } else {
        ForEach(this.files, (row: KnowledgeFileRow) => {
          Row({ space: 8 }) {
            // 文件图标块（装饰块不是按钮；与技能附件页成对）
            Column() {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(18)
                .fontColor([cardDescColor()])
            }
            .width(32)
            .height(32)
            .borderRadius(9)
            .backgroundColor(wellBg(this.appColorMode))
            .justifyContent(FlexAlign.Center)
            Column({ space: 3 }) {
              Text(row.name)
                .fontSize(15)
                .fontColor(cardTitleColor())
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(row.content.length + ' 字')
                .fontSize(13)
                .fontColor(cardDescColor())
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            Button() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.openFilePage(row.id, '', '');
            })
            Button() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(18)
                .fontColor([$r('sys.color.font_secondary')])
            }
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick((): void => {
              this.removeFile(row);
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          // 键含 id + 件名 + 字数（上屏项全进键：漏项会让 ForEach 不重建行——坑16 家族）
        }, (row: KnowledgeFileRow): string => row.id + '|' + row.name + '|' +
          String(row.content.length))
      }
      // 附件双键（并排胶囊等宽淡彩；两键都是「加一份」，不设主次）
      Row({ space: 10 }) {
        Button('新建文件')
          .fontSize(14)
          .fontColor(fallbackButtonFontTinted(this.contentFallback))
          .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
          .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            if (this.files.length >= KNOWLEDGE_FILE_MAX_COUNT) {
              this.getUIContext().getPromptAction().showToast({
                message: '每个条目最多附 ' + KNOWLEDGE_FILE_MAX_COUNT + ' 个文件'
              });
              return;
            }
            this.openFilePage('', '', '');
          })
        Button('上传文件')
          .fontSize(14)
          .fontColor(fallbackButtonFontTinted(this.contentFallback))
          .backgroundColor(fallbackButtonBgTinted(this.contentFallback, this.immersiveLevel))
          .systemMaterial(fallbackButtonMaterialTinted(this.contentFallback, this.immersiveLevel))
          .stateEffect(fallbackButtonStateEffect(this.contentFallback, this.immersiveLevel))
          .layoutWeight(1)
          .onClick((): void => {
            this.uploadFile();
          })
      }
      .width('100%')
    }
    .width(CARD_PANEL_WIDTH)
    .padding(14)
    .backgroundColor(cardBg(this.appColorMode))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  // 页面内容（坑39 红线：@BuilderParam content 位挂组件内 @Builder 方法）。骨架照 SkillEditPage
  // 吸顶穿透：滚动层顶部留白 = 胶囊位（topPad−8 钳位 0）+ SEGMENT_BAR_HEIGHT + 28；分段胶囊
  // 经标题栏下方带承载恒驻标题栏下沿（titleBarBottom → PageTopSegmentBand）。三段按 segIndex
  // 单渲染，切换即销毁重建——表单值全在父页 @State，来回切不丢内容
  @Builder
  Content() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 12 }) {
          if (this.segIndex === 0) {
            this.EntryCard()
            // 先决定怎么命中，再决定命中后放哪——故居条目卡与注入方式卡之间
            this.TriggerCard()
            // 注入方式独立成卡（条目管名称/关键词，注入管身份/位置/深度）
            this.InjectCard()
          } else if (this.segIndex === 1) {
            this.ContentCard()
          } else {
            // 文件段仅编辑态可达（新建态只有两段，segIndex 到不了 2）
            this.FilesCard()
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          top: Math.max(this.topPad - 8, 0) + SEGMENT_BAR_HEIGHT + 28,
          bottom: this.bottomPad + 24
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    PageShell({
      title: this.entryId === '' ? '新建条目' : '编辑条目',
      // 标题栏下方带承载
      titleBarBottom: (): void => {
        this.TopSegmentBand();
      },
      menuHds: knowledgeSaveMenuHds((): void => {
        this.save();
      }),
      content: (): void => {
        this.Content();
      }
    })
  }

  aboutToDisappear(): void {
    this.departed = true;
  }
}
